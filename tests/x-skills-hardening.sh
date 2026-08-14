#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-hardening.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { echo "HARDENING FAIL: $*" >&2; exit 1; }

for path in \
  commands-src/x-plan-eng/scripts/x-worktree \
  commands-src/x-ship/scripts/x-pr \
  commands-src/x-review/scripts/x-review-target \
  commands-src/x-housekeeping/scripts/x-clean \
  commands/x-plan-eng/scripts/x-worktree \
  commands/x-ship/scripts/x-pr; do
  [[ -x "$PROJECT_ROOT/$path" ]] || fail "missing executable helper: $path"
done

# Portable scripts must not introduce an undocumented Perl dependency.
! grep -Eq '(^|[^[:alnum:]_])perl([^[:alnum:]_]|$)' \
  "$PROJECT_ROOT/commands-src/x-discovery/scripts/x-cycle" || fail "x-cycle still requires Perl"

git init -q --bare "$TEST_ROOT/origin.git"
project="$TEST_ROOT/project"
mkdir -p "$project/commands-src"
cp -a "$PROJECT_ROOT/commands-src/x-discovery" "$project/commands-src/"
cp -a "$PROJECT_ROOT/commands-src/x-plan-eng" "$project/commands-src/"
cp -a "$PROJECT_ROOT/commands-src/x-review" "$project/commands-src/"
cp -a "$PROJECT_ROOT/commands-src/x-housekeeping" "$project/commands-src/"
cp -a "$PROJECT_ROOT/commands-src/x-ship" "$project/commands-src/"

git -C "$project" init -q -b main
git -C "$project" config user.email test@example.invalid
git -C "$project" config user.name 'Test Runner'
printf 'fixture\n' > "$project/README.md"
git -C "$project" add .
git -C "$project" commit -qm initial
git -C "$project" remote add origin "$TEST_ROOT/origin.git"
git -C "$project" push -qu -u origin main

cycle=$(cd "$project" && "$project/commands-src/x-discovery/scripts/x-cycle" release-cycle 'R&D / release')
[[ -f "$cycle/hub.md" ]] || fail "x-cycle did not initialize hub"
[[ $(cd "$project" && "$project/commands-src/x-discovery/scripts/x-cycle" release-cycle ignored) == "$cycle" ]] || fail "x-cycle is not idempotent"
grep -q 'R&D / release' "$cycle/hub.md" || fail "x-cycle did not render title portably"

cycle_name=$(basename "$cycle")
first=$(cd "$project" && "$project/commands-src/x-plan-eng/scripts/x-worktree" ensure "$cycle_name" WG-001 hardening main)
second=$(cd "$project" && "$project/commands-src/x-plan-eng/scripts/x-worktree" ensure "$cycle_name" WG-001 hardening main)
first_target=$(printf '%s\n' "$first" | grep -E '^(branch|worktree)=')
second_target=$(printf '%s\n' "$second" | grep -E '^(branch|worktree)=')
[[ "$first_target" == "$second_target" ]] || fail "x-worktree rerun changed target"
printf '%s\n' "$second" | grep -q '^action=reused$' || fail "x-worktree did not report reuse"
feature=$(printf '%s\n' "$first" | awk -F= '$1=="worktree" {print substr($0, index($0,"=")+1)}')
branch=$(printf '%s\n' "$first" | awk -F= '$1=="branch" {print substr($0, index($0,"=")+1)}')
[[ -d $feature ]] || fail "x-worktree did not create linked worktree"
[[ $(git -C "$project" worktree list --porcelain | grep -c '^worktree ') -eq 2 ]] || fail "x-worktree created duplicate worktrees"

# Review scratch must live at the main repo .dev-hub, even when invoked inside a linked worktree.
printf 'untracked review content\n' > "$feature/review-target.txt"
fingerprint=$(cd "$feature" && "$project/commands-src/x-review/scripts/x-review-target")
[[ $fingerprint =~ ^[0-9a-f]{64}$ ]] || fail "review fingerprint is not SHA-256"
[[ -d "$project/.dev-hub/runtime" ]] || fail "review scratch did not use main repo .dev-hub"
[[ ! -d "$feature/.dev-hub/runtime" ]] || fail "review scratch leaked into linked worktree"
rm "$feature/review-target.txt"

printf 'feature\n' > "$feature/feature.txt"
git -C "$feature" add feature.txt
git -C "$feature" commit -qm feature
git -C "$project" merge -q --no-ff "$branch" -m merge-local

# Local integration is insufficient: dry-run must report blocked and --remove must refuse.
blocked=$($project/commands-src/x-housekeeping/scripts/x-clean "$feature" "$branch" main)
printf '%s\n' "$blocked" | grep -q '^action=blocked-remote-unverified$' || fail "x-clean reported local-only merge as safe"
if "$project/commands-src/x-housekeeping/scripts/x-clean" --remove "$feature" "$branch" main >/dev/null 2>&1; then
  fail "x-clean removed branch before remote reachability"
fi

git -C "$project" push -q origin main
git -C "$project" fetch -q origin main
safe=$($project/commands-src/x-housekeeping/scripts/x-clean "$feature" "$branch" main)
printf '%s\n' "$safe" | grep -q '^action=safe-remove$' || fail "x-clean did not recognize remote-proven merge"
$project/commands-src/x-housekeeping/scripts/x-clean --remove "$feature" "$branch" main >/dev/null
[[ ! -e $feature ]] || fail "x-clean did not remove worktree"
! git -C "$project" show-ref --verify --quiet "refs/heads/$branch" || fail "x-clean did not remove branch"

# x-pr must create once and then update the same open PR.
fake_bin="$TEST_ROOT/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
state=${FAKE_GH_STATE:?}
log=${FAKE_GH_LOG:?}
printf '%s\n' "$*" >> "$log"
if [[ $1 == auth && $2 == status ]]; then exit 0; fi
if [[ $1 == pr && $2 == list ]]; then
  [[ -f $state ]] && printf '41\thttps://github.test/example/repo/pull/41\n'
  exit 0
fi
if [[ $1 == pr && $2 == create ]]; then
  : > "$state"
  printf 'https://github.test/example/repo/pull/41\n'
  exit 0
fi
if [[ $1 == pr && $2 == edit ]]; then exit 0; fi
exit 2
GH
chmod +x "$fake_bin/gh"
body="$TEST_ROOT/pr-body.md"
printf 'body\n' > "$body"
export FAKE_GH_STATE="$TEST_ROOT/pr-state" FAKE_GH_LOG="$TEST_ROOT/pr-log"
created=$(PATH="$fake_bin:$PATH" "$project/commands-src/x-ship/scripts/x-pr" ensure main feature/test 'Test PR' "$body")
updated=$(PATH="$fake_bin:$PATH" "$project/commands-src/x-ship/scripts/x-pr" ensure main feature/test 'Test PR' "$body")
printf '%s\n' "$created" | grep -q '^action=created$' || fail "x-pr did not create first PR"
printf '%s\n' "$updated" | grep -q '^action=updated$' || fail "x-pr did not update existing PR"
[[ $(grep -c '^pr create ' "$FAKE_GH_LOG") -eq 1 ]] || fail "x-pr created duplicate PRs"
[[ $(grep -c '^pr edit ' "$FAKE_GH_LOG") -eq 1 ]] || fail "x-pr did not update existing PR"

echo 'X-SKILLS HARDENING: PASS'
