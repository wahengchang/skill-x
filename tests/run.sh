#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

passed=0
failed=0

# Keep the suite hermetic: never let a locally installed OpenCode decide which
# code path the sync scripts take. The detection test overrides this itself.
export SKILL_X_OPENCODE_VERSION=v1

run_test() {
  local name=$1
  shift
  printf 'TEST  %s ... ' "$name"
  set +e
  (set -euo pipefail; "$@")
  local status=$?
  set -e
  if (( status == 0 )); then
    echo PASS
    passed=$((passed + 1))
  else
    echo FAIL
    failed=$((failed + 1))
  fi
}

copy_project() {
  local destination=$1
  mkdir -p "$destination"
  cp -a "$PROJECT_ROOT/." "$destination/"
  rm -rf "$destination/.git" "$destination/commands" "$destination/opencode-commands"
}

test_build_injects_header_and_support_files() {
  local project="$TEST_ROOT/build"
  copy_project "$project"
  mkdir -p "$project/commands-src/demo/scripts"
  cat > "$project/commands-src/demo/SKILL.md" <<'EOF'
---
name: demo
description: fixture
---

# Demo body
EOF
  echo 'echo helper' > "$project/commands-src/demo/scripts/helper.sh"

  "$project/bin/build.sh" >/dev/null
  [[ $(rg -c '此區塊由 bin/build.sh' "$project/commands/demo/SKILL.md") -eq 1 ]]
  rg -q '^# Demo body$' "$project/commands/demo/SKILL.md"
  cmp "$project/commands-src/demo/scripts/helper.sh" "$project/commands/demo/scripts/helper.sh"

  # A second build must be deterministic and must not inject the header twice.
  cp -a "$project/commands" "$project/first-build"
  cp -a "$project/opencode-commands" "$project/first-build-commands"
  "$project/bin/build.sh" >/dev/null
  diff -ru "$project/first-build" "$project/commands"
  diff -ru "$project/first-build-commands" "$project/opencode-commands"
}

test_build_generates_opencode_command_shims() {
  local project="$TEST_ROOT/shims"
  copy_project "$project"
  mkdir -p "$project/commands-src/demo"
  cat > "$project/commands-src/demo/SKILL.md" <<'EOF'
---
name: demo
description: Fixture that doesn't lose its apostrophe.
---

# Demo body
UNIQUE-CANONICAL-SENTINEL
EOF

  "$project/bin/build.sh" >/dev/null
  local shim="$project/opencode-commands/demo.md"
  [[ -f "$shim" ]]
  [[ -f "$project/opencode-commands/example-skill.md" ]]

  # The frontmatter description is carried over with YAML-safe quoting.
  rg -q "^description: 'Fixture that doesn''t lose its apostrophe\.'$" "$shim"
  # The shim delegates to the canonical skill and forwards arguments.
  rg -qF 'Use the `skill` tool to load the `demo` skill' "$shim"
  rg -qF '$ARGUMENTS' "$shim"
  # It must not duplicate the canonical instructions or the update-check header.
  ! rg -q 'UNIQUE-CANONICAL-SENTINEL' "$shim"
  ! rg -q '此區塊由 bin/build.sh' "$shim"
}

test_opencode_version_detection() {
  local project="$TEST_ROOT/version"
  local fake="$TEST_ROOT/version-bin"
  copy_project "$project"
  mkdir -p "$fake"

  fake_opencode() {
    printf '#!/usr/bin/env bash\necho %s\n' "$1" > "$fake/opencode"
    chmod +x "$fake/opencode"
  }

  fake_opencode 1.18.16
  [[ $(PATH="$fake:$PATH" SKILL_X_OPENCODE_VERSION=auto "$project/bin/opencode-version.sh") == v1 ]]
  fake_opencode 2.0.3
  [[ $(PATH="$fake:$PATH" SKILL_X_OPENCODE_VERSION=auto "$project/bin/opencode-version.sh") == v2 ]]

  # An explicit override wins over whatever is installed.
  [[ $(PATH="$fake:$PATH" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/opencode-version.sh") == v1 ]]

  # Without a detectable binary the installer stays useful and says so.
  rm "$fake/opencode"
  local output
  output=$(PATH="$fake:/usr/bin:/bin" SKILL_X_OPENCODE_VERSION=auto "$project/bin/opencode-version.sh" 2>"$project/detect-stderr")
  [[ "$output" == v1 ]]
  rg -q 'SKILL_X_OPENCODE_VERSION' "$project/detect-stderr"

  # An unusable value fails loudly instead of guessing.
  if SKILL_X_OPENCODE_VERSION=v3 "$project/bin/opencode-version.sh" >/dev/null 2>&1; then
    return 1
  fi
}

test_sync_installs_opencode_v1_commands() {
  local project="$TEST_ROOT/opencode-v1"
  local home="$TEST_ROOT/opencode-v1-home"
  local commands="$home/.config/opencode/commands"
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  mkdir -p "$commands"
  echo 'user owned' > "$commands/example-skill.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null 2>"$project/warnings"
  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null 2>>"$project/warnings"

  # A pre-existing non-managed command is never overwritten.
  [[ ! -L "$commands/example-skill.md" ]]
  [[ $(cat "$commands/example-skill.md") == 'user owned' ]]
  rg -q 'skipping non-symlink path' "$project/warnings"

  # Everything else is linked once, idempotently, at the canonical shim.
  [[ -L "$commands/funny-text-rewriter.md" ]]
  [[ $(readlink "$commands/funny-text-rewriter.md") == "$project/opencode-commands/funny-text-rewriter.md" ]]
  [[ $(find "$commands" -mindepth 1 -maxdepth 1 -name 'funny-text-rewriter.md' | wc -l) -eq 1 ]]
}

test_sync_removes_stale_opencode_commands() {
  local project="$TEST_ROOT/opencode-stale"
  local home="$TEST_ROOT/opencode-stale-home"
  local commands="$home/.config/opencode/commands"
  copy_project "$project"
  mkdir -p "$project/commands-src/temp-skill"
  cat > "$project/commands-src/temp-skill/SKILL.md" <<'EOF'
---
name: temp-skill
description: fixture
---

body
EOF
  "$project/bin/build.sh" >/dev/null
  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null
  [[ -L "$commands/temp-skill.md" ]]

  rm -rf "$project/commands-src/temp-skill"
  "$project/bin/build.sh" >/dev/null
  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null 2>/dev/null

  [[ ! -e "$commands/temp-skill.md" ]]
  [[ -L "$commands/example-skill.md" ]]
}

test_sync_v2_removes_generated_commands() {
  local project="$TEST_ROOT/opencode-v2"
  local home="$TEST_ROOT/opencode-v2-home"
  local commands="$home/.config/opencode/commands"
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null
  echo 'user owned' > "$commands/user-command.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v2 "$project/bin/sync-skills.sh" >/dev/null 2>/dev/null

  # v2 lists skills natively, so generated shims must not linger as duplicates.
  [[ ! -e "$commands/example-skill.md" ]]
  [[ ! -e "$commands/funny-text-rewriter.md" ]]
  [[ -f "$commands/user-command.md" ]]
  # Skills themselves stay synchronized.
  [[ -L "$home/.config/opencode/skills/example-skill" ]]
}

test_build_rejects_invalid_frontmatter_without_destroying_output() {
  local project="$TEST_ROOT/invalid-build"
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  cp -a "$project/commands" "$project/expected"
  cp -a "$project/opencode-commands" "$project/expected-commands"
  printf '# missing frontmatter\n' > "$project/commands-src/example-skill/SKILL.md"

  if "$project/bin/build.sh" >"$project/stdout" 2>"$project/stderr"; then
    return 1
  fi
  rg -q 'Invalid frontmatter' "$project/stderr"
  diff -ru "$project/expected" "$project/commands"
  diff -ru "$project/expected-commands" "$project/opencode-commands"
}

test_build_accepts_crlf_frontmatter() {
  local project="$TEST_ROOT/crlf"
  copy_project "$project"
  printf -- '---\r\nname: crlf-skill\r\ndescription: fixture\r\n---\r\n\r\nbody\r\n' \
    > "$project/commands-src/example-skill/SKILL.md"

  "$project/bin/build.sh" >/dev/null
  rg -q '^name: crlf-skill$' "$project/commands/example-skill/SKILL.md"
  ! rg -q $'\r' "$project/commands/example-skill/SKILL.md"
}

test_sync_removes_links_for_deleted_skills() {
  local project="$TEST_ROOT/sync-remove"
  local home="$TEST_ROOT/sync-remove-home"
  copy_project "$project"
  mkdir -p "$project/commands-src/second-skill"
  cat > "$project/commands-src/second-skill/SKILL.md" <<'EOF'
---
name: second-skill
description: fixture
---

body
EOF
  "$project/bin/build.sh" >/dev/null
  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null

  rm -rf "$project/commands-src/second-skill"
  "$project/bin/build.sh" >/dev/null
  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null

  [[ -L "$home/.claude/skills/example-skill" ]]
  [[ ! -e "$home/.claude/skills/second-skill" ]]
}

test_sync_is_idempotent_and_preserves_collisions() {
  local project="$TEST_ROOT/sync"
  local home="$TEST_ROOT/sync-home"
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  mkdir -p "$home/.claude/skills/example-skill"
  echo keep > "$home/.claude/skills/example-skill/user-file"

  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null 2>"$project/warnings"
  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null 2>>"$project/warnings"
  [[ -f "$home/.claude/skills/example-skill/user-file" ]]
  for path in \
    .codex/skills/example-skill \
    .agents/skills/example-skill \
    .config/opencode/skills/example-skill; do
    [[ -L "$home/$path" ]]
    [[ $(readlink "$home/$path") == "$project/commands/example-skill" ]]
  done
  rg -q 'skipping non-symlink path' "$project/warnings"
}

make_git_fixture() {
  local project=$1
  local remote=$2
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  git init -q --bare "$remote"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  git -C "$project" remote add origin "$remote"
  git -C "$project" push -qu origin HEAD
}

test_update_check_states() {
  local project="$TEST_ROOT/update"
  local remote="$TEST_ROOT/update.git"
  local state="$TEST_ROOT/update-state"
  local other="$TEST_ROOT/update-other"
  make_git_fixture "$project" "$remote"

  [[ $(SKILL_X_STATE_DIR="$state" "$project/bin/update-check") == UP_TO_DATE ]]

  git clone -q "$remote" "$other"
  git -C "$other" config user.email test@example.invalid
  git -C "$other" config user.name 'Test Runner'
  echo newer > "$other/new-file"
  git -C "$other" add new-file
  git -C "$other" commit -qm newer
  git -C "$other" push -q

  local output
  output=$(SKILL_X_STATE_DIR="$state" SKILL_X_CHECK_INTERVAL_SECONDS=0 "$project/bin/update-check")
  [[ "$output" == UPGRADE_AVAILABLE* ]]

  SKILL_X_STATE_DIR="$state" SKILL_X_SNOOZE_DAYS=7 "$project/bin/snooze.sh" >/dev/null
  [[ $(SKILL_X_STATE_DIR="$state" SKILL_X_CHECK_INTERVAL_SECONDS=0 "$project/bin/update-check") == UP_TO_DATE ]]
}

test_update_check_fails_open_without_remote() {
  local project="$TEST_ROOT/no-remote"
  local state="$TEST_ROOT/no-remote-state"
  copy_project "$project"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial

  [[ -z $(SKILL_X_STATE_DIR="$state" "$project/bin/update-check") ]]
  [[ ! -e "$state/last-check" ]]
}

test_apply_update_fast_forwards_and_resyncs() {
  local project="$TEST_ROOT/apply"
  local remote="$TEST_ROOT/apply.git"
  local author="$TEST_ROOT/apply-author"
  local home="$TEST_ROOT/apply-home"
  local state="$TEST_ROOT/apply-state"
  make_git_fixture "$project" "$remote"
  git clone -q "$remote" "$author"
  git -C "$author" config user.email test@example.invalid
  git -C "$author" config user.name 'Test Runner'
  echo update > "$author/update-marker"
  git -C "$author" add update-marker
  git -C "$author" commit -qm update
  git -C "$author" push -q
  mkdir -p "$state"
  : > "$state/last-check"
  : > "$state/snooze-until"

  HOME="$home" SKILL_X_STATE_DIR="$state" "$project/bin/apply-update.sh" >/dev/null
  [[ -f "$project/update-marker" ]]
  [[ -L "$home/.codex/skills/example-skill" ]]
  [[ ! -e "$state/last-check" && ! -e "$state/snooze-until" ]]
}

test_cloud_bootstrap_copies_pinned_content() {
  local project="$TEST_ROOT/cloud-source"
  local remote="$TEST_ROOT/cloud.git"
  local home="$TEST_ROOT/cloud-home"
  make_git_fixture "$project" "$remote"
  local ref
  ref=$(git -C "$project" rev-parse HEAD)

  HOME="$home" "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null
  for path in \
    .claude/skills/example-skill \
    .codex/skills/example-skill \
    .agents/skills/example-skill \
    .config/opencode/skills/example-skill; do
    [[ -f "$home/$path/SKILL.md" ]]
    [[ ! -L "$home/$path" ]]
  done
}

test_cloud_bootstrap_installs_command_shims() {
  local project="$TEST_ROOT/cloud-commands-source"
  local remote="$TEST_ROOT/cloud-commands.git"
  local home="$TEST_ROOT/cloud-commands-home"
  local commands="$home/.config/opencode/commands"
  make_git_fixture "$project" "$remote"
  local ref
  ref=$(git -C "$project" rev-parse HEAD)
  mkdir -p "$commands"
  echo 'user owned' > "$commands/example-skill.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>"$project/cloud-warnings"

  # Pinned images get copies, not links, and never clobber a user's own command.
  [[ -f "$commands/funny-text-rewriter.md" && ! -L "$commands/funny-text-rewriter.md" ]]
  rg -qF '$ARGUMENTS' "$commands/funny-text-rewriter.md"
  [[ $(cat "$commands/example-skill.md") == 'user owned' ]]
  rg -q 'non-managed command' "$project/cloud-warnings"

  # v2 images rely on the native slash catalog instead.
  local home_v2="$TEST_ROOT/cloud-commands-home-v2"
  HOME="$home_v2" SKILL_X_OPENCODE_VERSION=v2 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null
  [[ ! -e "$home_v2/.config/opencode/commands" ]]
  [[ -f "$home_v2/.config/opencode/skills/example-skill/SKILL.md" ]]
}

X_SKILLS=(x-discovery x-plan-eng x-review x-debug x-ship x-housekeeping)

test_build_materializes_shared_skill_assets() {
  local project="$TEST_ROOT/x-assets"
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null

  local skill
  for skill in "${X_SKILLS[@]}"; do
    # The source tree shares one copy through a symlink; the deployment must
    # contain real files, because each skill is synced to the tools on its own.
    [[ -L "$project/commands-src/$skill/scripts" ]]
    [[ ! -L "$project/commands/$skill/scripts" ]]
    [[ -x "$project/commands/$skill/scripts/xdh" ]]
    [[ -f "$project/commands/$skill/scripts/lib/common.sh" ]]
    [[ -f "$project/commands/$skill/templates/issue.md" ]]
    cmp "$project/commands-src/_x-shared/scripts/xdh" "$project/commands/$skill/scripts/xdh"
  done

  # The shared source directory is not itself a skill.
  [[ ! -e "$project/commands/_x-shared" ]]
  [[ ! -e "$project/opencode-commands/_x-shared.md" ]]
}

# Build the project, then hand back a throwaway Git repository plus the path to
# the *deployed* xdh — the exact file a synced tool would execute.
make_xdh_fixture() {
  local project=$1 repo=$2
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'
  echo seed > "$repo/seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial
}

test_xdh_creates_cycles_and_items_idempotently() {
  local project="$TEST_ROOT/xdh-cycle" repo="$TEST_ROOT/xdh-cycle-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-discovery/scripts/xdh"

  local first second
  first=$(cd "$repo" && "$xdh" cycle new --slug 'Login Flow!!' --title 'Login flow')
  rg -q '^X_CYCLE=cycle-[0-9]{8}-[0-9]{4}-login-flow$' <<<"$first"
  rg -q '^X_CYCLE_REUSED=no$' <<<"$first"

  # A second discovery pass over the same scope updates the Cycle in place.
  second=$(cd "$repo" && "$xdh" cycle new --slug login-flow)
  rg -q '^X_CYCLE_REUSED=yes$' <<<"$second"
  [[ $(rg '^X_CYCLE=' <<<"$first") == "$(rg '^X_CYCLE=' <<<"$second")" ]]
  [[ $(find "$repo/.dev-hub/active" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 1 ]]

  # Runtime state is ignored; the cycle log directory is not.
  rg -qx '\.dev-hub/active/' "$repo/.gitignore"
  rg -qx '\.dev-hub/runtime/' "$repo/.gitignore"
  ! rg -q 'logs' "$repo/.gitignore"

  # IDs increment across kinds and never collide; re-planning reuses the file.
  (cd "$repo" && "$xdh" item new --type issue --slug session-timeout >/dev/null)
  (cd "$repo" && "$xdh" item new --type spike --slug token-store >/dev/null)
  local again
  again=$(cd "$repo" && "$xdh" item new --type issue --slug session-timeout --title Ignored)
  rg -q '^X_ITEM_ID=IS-001$' <<<"$again"
  rg -q '^X_ITEM_REUSED=yes$' <<<"$again"
  rg -q '^X_NEXT_ID=IS-002$' <<<"$(cd "$repo" && "$xdh" id next --kind IS)"
  rg -q '^X_NEXT_ID=SP-002$' <<<"$(cd "$repo" && "$xdh" id next --kind SP)"
}

test_xdh_work_group_binds_branch_and_worktree() {
  local project="$TEST_ROOT/xdh-wg" repo="$TEST_ROOT/xdh-wg-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-plan-eng/scripts/xdh"

  (cd "$repo" && "$xdh" cycle new --slug auth >/dev/null)
  local first second worktree
  first=$(cd "$repo" && "$xdh" wg new --slug login --items IS-001)
  rg -q '^X_WG_ID=WG-001$' <<<"$first"
  rg -q '^X_WG_BRANCH=x/[0-9]{8}-[0-9]{4}-wg-001-login$' <<<"$first"
  worktree=$(rg -N --replace '$1' '^X_WG_WORKTREE=(.*)$' <<<"$first")
  [[ -d $worktree ]]

  second=$(cd "$repo" && "$xdh" wg new --slug login)
  rg -q '^X_WG_REUSED=yes$' <<<"$second"
  rg -q '^X_WORKTREE_CREATED=no$' <<<"$second"
  [[ $(git -C "$repo" worktree list | wc -l) -eq 2 ]]
  [[ $(git -C "$repo" branch --list 'x/*' | wc -l) -eq 1 ]]

  # A skill invoked inside the linked worktree must still find the shared hub.
  local from_worktree
  from_worktree=$(cd "$worktree" && "$xdh" paths)
  rg -qx "X_MAIN_ROOT=$repo" <<<"$from_worktree"
  rg -qx "X_DEV_HUB=$repo/.dev-hub" <<<"$from_worktree"
  rg -qx "X_CURRENT_ROOT=$worktree" <<<"$from_worktree"
}

test_xdh_fingerprint_tracks_content_not_time() {
  local project="$TEST_ROOT/xdh-fp" repo="$TEST_ROOT/xdh-fp-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-review/scripts/xdh"

  git -C "$repo" checkout -q -b feature
  echo change > "$repo/seed.txt"
  local fp
  fp=$(cd "$repo" && "$xdh" fingerprint --base main | rg -N --replace '$1' '^X_FINGERPRINT=(.*)$')
  [[ -n $fp ]]

  # Uncommitted work counts as content: committing it must not move the target.
  git -C "$repo" add -A
  git -C "$repo" commit -qm 'feat: change'
  rg -q '^X_REVIEW_FRESHNESS=FRESH$' \
    <<<"$(cd "$repo" && "$xdh" fingerprint verify --expect "$fp" --base main)"

  # Any later edit invalidates the approval.
  echo more >> "$repo/seed.txt"
  if (cd "$repo" && "$xdh" fingerprint verify --expect "$fp" --base main >"$project/verify.out" 2>&1); then
    return 1
  fi
  rg -q '^X_REVIEW_FRESHNESS=STALE$' "$project/verify.out"
}

test_xdh_housekeeping_refuses_unsafe_removals() {
  local project="$TEST_ROOT/xdh-clean" repo="$TEST_ROOT/xdh-clean-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-housekeeping/scripts/xdh"

  (cd "$repo" && "$xdh" cycle new --slug cleanup >/dev/null)
  local worktree
  worktree=$(cd "$repo" && "$xdh" wg new --slug widget |
             rg -N --replace '$1' '^X_WG_WORKTREE=(.*)$')

  # 1. Uncommitted work is never destroyed.
  echo scratch > "$worktree/scratch.txt"
  rg -q '^ITEM DIRTY worktree ' <<<"$(cd "$repo" && "$xdh" clean scan)"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -d $worktree ]]
  [[ -f $worktree/scratch.txt ]]

  # 2. Committed but unintegrated work is never destroyed either.
  git -C "$worktree" add -A
  git -C "$worktree" commit -qm 'feat: widget'
  rg -q '^ITEM UNMERGED worktree ' <<<"$(cd "$repo" && "$xdh" clean scan)"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -d $worktree ]]

  # 3. Once merged, the worktree and then the branch become removable.
  git -C "$repo" merge -q --no-ff -m 'merge widget' \
    "$(git -C "$worktree" rev-parse --abbrev-ref HEAD)"
  rg -q '^ITEM SAFE worktree ' <<<"$(cd "$repo" && "$xdh" clean scan)"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ ! -d $worktree ]]
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -z $(git -C "$repo" branch --list 'x/*') ]]
}

test_xdh_cycle_closes_into_a_tracked_log() {
  local project="$TEST_ROOT/xdh-close" repo="$TEST_ROOT/xdh-close-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-housekeeping/scripts/xdh"

  local cycle
  cycle=$(cd "$repo" && "$xdh" cycle new --slug release |
          rg -N --replace '$1' '^X_CYCLE=(.*)$')
  (cd "$repo" && "$xdh" item new --type issue --slug alpha >/dev/null)
  (cd "$repo" && "$xdh" item new --type issue --slug beta >/dev/null)

  # An unfinished item blocks closure and the Cycle survives.
  if (cd "$repo" && "$xdh" cycle close --cycle "$cycle" --summary x >"$project/close.out" 2>&1); then
    return 1
  fi
  rg -q '^BLOCKER work-item IS-001-alpha\.md status=draft$' "$project/close.out"
  [[ -d "$repo/.dev-hub/active/$cycle" ]]

  local f
  for f in "$repo/.dev-hub/active/$cycle"/work-items/*.md; do
    (cd "$repo" && "$xdh" field set "$f" Status done >/dev/null)
  done
  (cd "$repo" && "$xdh" cycle close --cycle "$cycle" \
     --summary 'Shipped alpha and beta.' --decisions 'Kept the old store.' >/dev/null)

  [[ ! -d "$repo/.dev-hub/active/$cycle" ]]
  rg -q '^\*\*Summary:\*\* Shipped alpha and beta\.$' "$repo/.dev-hub/logs/$cycle.md"
  rg -q '^- Work items: IS-001-alpha, IS-002-beta$' "$repo/.dev-hub/logs/$cycle.md"

  # The log is the part that must survive in Git.
  git -C "$repo" add -A
  rg -qx "\.dev-hub/logs/$cycle.md" <<<"$(git -C "$repo" diff --cached --name-only)"
}

run_test 'build injects once and copies support files' test_build_injects_header_and_support_files
run_test 'invalid build preserves previous deployment' test_build_rejects_invalid_frontmatter_without_destroying_output
run_test 'build accepts crlf frontmatter' test_build_accepts_crlf_frontmatter
run_test 'build generates delegating opencode command shims' test_build_generates_opencode_command_shims
run_test 'opencode version detection and override' test_opencode_version_detection
run_test 'sync is idempotent and preserves collisions' test_sync_is_idempotent_and_preserves_collisions
run_test 'sync removes links for deleted skills' test_sync_removes_links_for_deleted_skills
run_test 'sync installs opencode v1 commands without clobbering' test_sync_installs_opencode_v1_commands
run_test 'sync removes stale opencode commands' test_sync_removes_stale_opencode_commands
run_test 'opencode v2 sync removes generated commands' test_sync_v2_removes_generated_commands
run_test 'update check reports current, upgrade, and snooze states' test_update_check_states
run_test 'update check fails open without a remote' test_update_check_fails_open_without_remote
run_test 'apply update fast-forwards and resynchronizes' test_apply_update_fast_forwards_and_resyncs
run_test 'cloud bootstrap installs copies from a pinned ref' test_cloud_bootstrap_copies_pinned_content
run_test 'cloud bootstrap installs pinned command shims' test_cloud_bootstrap_installs_command_shims
run_test 'build materializes shared x-skill assets' test_build_materializes_shared_skill_assets
run_test 'xdh creates cycles and work items idempotently' test_xdh_creates_cycles_and_items_idempotently
run_test 'xdh binds one work group to one branch and worktree' test_xdh_work_group_binds_branch_and_worktree
run_test 'xdh fingerprints content, not time' test_xdh_fingerprint_tracks_content_not_time
run_test 'xdh housekeeping refuses unsafe removals' test_xdh_housekeeping_refuses_unsafe_removals
run_test 'xdh closes a cycle into a tracked log' test_xdh_cycle_closes_into_a_tracked_log

printf '\nRESULT: %d passed, %d failed\n' "$passed" "$failed"
(( failed == 0 ))
