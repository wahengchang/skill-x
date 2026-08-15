#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-tests.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Keep the suite hermetic: never let locally installed agents decide which
# code paths the scripts take. Detection and selection tests override these.
export SKILL_X_OPENCODE_VERSION=v1
export SKILL_X_AGENTS=claude,codex,opencode

# shellcheck source=lib/harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"
skill_x_test_parse_args "$@"

# The harness itself: a test that never returns must be terminated and reported
# as a failure, otherwise a worktree lock or a stalled subprocess silently eats
# the whole session. The fixture suite is bounded to a two-second timeout.
test_harness_terminates_a_stalled_test() {
  local output
  if output=$(SKILL_X_TEST_TIMEOUT=2 bash "$PROJECT_ROOT/tests/lib/timeout-fixture.sh" 2>&1); then
    printf '%s\n' "$output" >&2
    echo 'stalled test fixture unexpectedly succeeded' >&2
    return 1
  fi
  rg -q 'TIMEOUT after 2s' <<<"$output"
  rg -q '1 failed' <<<"$output"
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
  copy_built_project "$project"
  mkdir -p "$commands"
  echo 'user owned' > "$commands/example-skill.md"
  cp "$project/opencode-commands/herdr.md" "$commands/herdr.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null 2>"$project/warnings"
  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 "$project/bin/sync-skills.sh" >/dev/null 2>>"$project/warnings"

  # A pre-existing non-managed command is never overwritten.
  [[ ! -L "$commands/example-skill.md" ]]
  [[ $(cat "$commands/example-skill.md") == 'user owned' ]]
  rg -q 'skipping unowned non-symlink path' "$project/warnings"

  # Everything else is linked once, idempotently, at the canonical shim.
  [[ -L "$commands/funny-text-rewriter.md" ]]
  [[ "$(realpath -- "$(readlink "$commands/funny-text-rewriter.md")")" == \
     "$(realpath -- "$project/opencode-commands/funny-text-rewriter.md")" ]]
  [[ $(find "$commands" -mindepth 1 -maxdepth 1 -name 'funny-text-rewriter.md' | wc -l) -eq 1 ]]
  # A copied shim managed by skill-x is safely converted to the local symlink form.
  [[ -L "$commands/herdr.md" ]]
  [[ "$(realpath -- "$(readlink "$commands/herdr.md")")" == \
     "$(realpath -- "$project/opencode-commands/herdr.md")" ]]
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
  copy_built_project "$project"
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
  copy_built_project "$project"
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
  rg -q 'skipping unowned non-symlink path' "$project/warnings"
}

make_git_fixture() {
  local project=$1
  local remote=$2
  copy_built_project "$project"
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
  # A reused image layer or HOME still holds the symlinks an earlier managed
  # sync created. Those are recorded in the manifest, so the pinned copy is
  # allowed to unlink them; anything unmanaged is not touched.
  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 SKILL_X_AGENTS=opencode \
    "$project/bin/skill-x" install >/dev/null 2>&1
  [[ -L "$commands/herdr.md" ]]

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>"$project/cloud-warnings"

  # Pinned images get copies, not links, and never clobber a user's own command.
  [[ -f "$commands/funny-text-rewriter.md" && ! -L "$commands/funny-text-rewriter.md" ]]
  [[ -f "$commands/herdr.md" && ! -L "$commands/herdr.md" ]]
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
  copy_built_project "$project"

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
  copy_built_project "$project"
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
  local from_worktree canonical_repo canonical_worktree
  from_worktree=$(cd "$worktree" && "$xdh" paths)
  canonical_repo=$(cd "$repo" && pwd -P)
  canonical_worktree=$(cd "$worktree" && pwd -P)
  rg -qx "X_MAIN_ROOT=$canonical_repo" <<<"$from_worktree"
  rg -qx "X_DEV_HUB=$canonical_repo/.dev-hub" <<<"$from_worktree"
  rg -qx "X_CURRENT_ROOT=$canonical_worktree" <<<"$from_worktree"
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

test_x_review_documents_cross_model_dispatch() {
  local project="$TEST_ROOT/x-review-skill"
  copy_built_project "$project"
  local skill="$project/commands/x-review/SKILL.md"

  # Two independent reviewer paths, CLI preferred over the host subagent, and
  # the existing blocked verdict is preserved when neither is available.
  rg -q 'Codex CLI' "$skill"
  rg -q 'host subagent' "$skill"
  rg -q 'BLOCKED_NO_INDEPENDENT_REVIEWER' "$skill"
  rg -q 'codex-cli' "$skill"
  rg -q 'host-subagent' "$skill"

  # Default branch-diff mode uses the review-oriented command; focused mode uses
  # general execution with an explicit read-only sandbox.
  rg -q 'codex review' "$skill"
  rg -q 'codex exec' "$skill"
  rg -q -- '--sandbox read-only' "$skill"
  rg -q -- '--uncommitted' "$skill"

  # No invocation shape can grant the reviewer write authority.
  ! rg -q -- '--sandbox workspace-write' "$skill"
  ! rg -q -- '--sandbox danger-full-access' "$skill"
  ! rg -q -- '--dangerously-bypass-approvals-and-sandbox' "$skill"
  ! rg -q -- '--add-dir' "$skill"

  # Bounded timeout and a secret-free auth preflight are documented.
  rg -q 'timeout' "$skill"
  rg -q 'gtimeout' "$skill"
  rg -q 'OPENAI_API_KEY' "$skill"
  rg -q 'auth.json' "$skill"

  # Provenance flags and finding normalization are wired into the artifact.
  rg -q -- '--reviewer-type' "$skill"
  rg -q -- '--reviewer-model' "$skill"
  rg -q -- '--review-mode' "$skill"
  rg -q 'file:line' "$skill"
  rg -q 'recompute the fingerprint' "$skill"
}

test_x_review_artifact_records_reviewer_provenance() {
  local project="$TEST_ROOT/xdh-rv" repo="$TEST_ROOT/xdh-rv-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-review/scripts/xdh"

  local out file
  out=$(cd "$repo" && "$xdh" artifact new --kind RV \
    --target WG-001 --base main \
    --implementer impl --reviewer rev \
    --reviewer-type codex-cli --reviewer-model gpt-5 --review-mode branch-diff \
    --independent yes --fingerprint fp --tree tree)
  file=$(rg -N --replace '$1' '^X_ARTIFACT_FILE=(.*)$' <<<"$out")

  rg -q '^- Reviewer Type: codex-cli$' "$file"
  rg -q '^- Reviewer Model: gpt-5$' "$file"
  rg -q '^- Review Mode: branch-diff$' "$file"
  rg -q '^- Reviewer Agent: rev$' "$file"
  rg -q '^- Independent: yes$' "$file"

  # Omitted provenance falls back to the em-dash placeholder, never empty.
  local out2 file2
  out2=$(cd "$repo" && "$xdh" artifact new --kind RV --target WG-002)
  file2=$(rg -N --replace '$1' '^X_ARTIFACT_FILE=(.*)$' <<<"$out2")
  rg -q '^- Reviewer Type: —$' "$file2"
  rg -q '^- Reviewer Model: —$' "$file2"
  rg -q '^- Review Mode: —$' "$file2"
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
  rg -q '^ITEM\tDIRTY\tworktree\t' <<<"$(cd "$repo" && "$xdh" clean scan)"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -d $worktree ]]
  [[ -f $worktree/scratch.txt ]]

  # 2. Committed but unintegrated work is never destroyed either.
  git -C "$worktree" add -A
  git -C "$worktree" commit -qm 'feat: widget'
  rg -q '^ITEM\tUNMERGED\tworktree\t' <<<"$(cd "$repo" && "$xdh" clean scan)"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -d $worktree ]]

  # 3. Once merged, the worktree and then the branch become removable.
  git -C "$repo" merge -q --no-ff -m 'merge widget' \
    "$(git -C "$worktree" rev-parse --abbrev-ref HEAD)"
  rg -q '^ITEM\tSAFE\tworktree\t' <<<"$(cd "$repo" && "$xdh" clean scan)"
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

test_xdh_concurrent_cycle_creation_yields_one_cycle() {
  local project="$TEST_ROOT/xdh-race-cycle" repo="$TEST_ROOT/xdh-race-cycle-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-discovery/scripts/xdh"

  # Two agents opening discovery on the same scope at the same moment.
  local i
  for i in 1 2 3 4; do
    (cd "$repo" && "$xdh" cycle new --slug shared-scope > "$project/cycle-$i.out" 2>&1) &
  done
  wait

  for i in 1 2 3 4; do
    rg -q '^X_CYCLE=cycle-' "$project/cycle-$i.out"
  done
  # Exactly one Cycle directory, and exactly one of the runs claims to have
  # created it: a second active Cycle for one scope makes every later lookup
  # ambiguous.
  [[ $(find "$repo/.dev-hub/active" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 1 ]]
  [[ $(cat "$project"/cycle-*.out | rg -c '^X_CYCLE_REUSED=no$' || echo 0) -eq 1 ]]
  [[ $(cat "$project"/cycle-*.out | rg '^X_CYCLE=' | sort -u | wc -l) -eq 1 ]]
}

test_xdh_concurrent_allocation_never_reuses_an_id() {
  local project="$TEST_ROOT/xdh-race-id" repo="$TEST_ROOT/xdh-race-id-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-plan-eng/scripts/xdh"
  (cd "$repo" && "$xdh" cycle new --slug race >/dev/null)

  # Four different work items planned at once must get four different numbers.
  local i
  for i in 1 2 3 4; do
    (cd "$repo" && "$xdh" item new --type issue --slug "item-$i" > "$project/item-$i.out" 2>&1) &
  done
  wait
  [[ $(cat "$project"/item-*.out | rg '^X_ITEM_ID=' | sort -u | wc -l) -eq 4 ]]
  [[ $(find "$repo/.dev-hub/active" -name 'IS-*.md' | wc -l) -eq 4 ]]

  # The same work planned twice at once must produce one item, not two.
  for i in 1 2 3; do
    (cd "$repo" && "$xdh" item new --type issue --slug same-work > "$project/same-$i.out" 2>&1) &
  done
  wait
  [[ $(find "$repo/.dev-hub/active" -name 'IS-*-same-work.md' | wc -l) -eq 1 ]]
  [[ $(cat "$project"/same-*.out | rg '^X_ITEM_ID=' | sort -u | wc -l) -eq 1 ]]

  # Two Work Groups claimed at once must not both become WG-001. This is the
  # allocation that used to release its lock before writing the file.
  local wg
  for wg in alpha beta gamma; do
    (cd "$repo" && "$xdh" wg new --slug "$wg" > "$project/wg-$wg.out" 2>&1) &
  done
  wait
  for wg in alpha beta gamma; do
    rg -q '^X_WG_ID=WG-' "$project/wg-$wg.out"
  done
  [[ $(cat "$project"/wg-*.out | rg '^X_WG_ID=' | sort -u | wc -l) -eq 3 ]]
  [[ $(find "$repo/.dev-hub/active" -name 'WG-*.md' | wc -l) -eq 3 ]]
  [[ $(git -C "$repo" branch --list 'x/*' | wc -l) -eq 3 ]]
}

test_xdh_refuses_to_guess_between_ambiguous_cycles() {
  local project="$TEST_ROOT/xdh-ambiguous" repo="$TEST_ROOT/xdh-ambiguous-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-plan-eng/scripts/xdh"

  (cd "$repo" && "$xdh" cycle new --slug first >/dev/null)
  (cd "$repo" && "$xdh" cycle new --slug second >/dev/null)

  # With two active Cycles an unqualified write must stop, not pick one.
  if (cd "$repo" && "$xdh" item new --type issue --slug thing >"$project/amb.out" 2>&1); then
    return 1
  fi
  rg -q 'multiple active cycles' "$project/amb.out"
  [[ -z $(find "$repo/.dev-hub/active" -name 'IS-*.md') ]]

  # Naming the target resolves it, by directory name or by slug.
  (cd "$repo" && "$xdh" item new --type issue --slug thing --cycle second >/dev/null)
  [[ $(find "$repo/.dev-hub/active" -name 'IS-001-thing.md' | wc -l) -eq 1 ]]
  rg -q '^X_CYCLE=cycle-[0-9]{8}-[0-9]{4}-first$' \
    <<<"$(cd "$repo" && "$xdh" cycle show --cycle first)"
}

test_xdh_recreates_a_stale_worktree_registration() {
  local project="$TEST_ROOT/xdh-stale-wt" repo="$TEST_ROOT/xdh-stale-wt-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-plan-eng/scripts/xdh"
  (cd "$repo" && "$xdh" cycle new --slug stale >/dev/null)

  local worktree
  worktree=$(cd "$repo" && "$xdh" wg new --slug widget |
             rg -N --replace '$1' '^X_WG_WORKTREE=(.*)$')
  [[ -d $worktree ]]

  # Someone deletes the directory by hand; Git still has the registration.
  rm -rf "$worktree"
  git -C "$repo" worktree list --porcelain | rg -qF "worktree $worktree"

  # Re-running must not report a usable worktree it cannot provide: the stale
  # registration is pruned and the worktree recreated on the same branch.
  local rerun
  rerun=$(cd "$repo" && "$xdh" wg new --slug widget)
  rg -q '^X_WORKTREE_PRUNED=yes$' <<<"$rerun"
  rg -q '^X_WORKTREE_CREATED=yes$' <<<"$rerun"
  rg -q '^X_WG_ID=WG-001$' <<<"$rerun"
  rg -q '^X_WG_REUSED=yes$' <<<"$rerun"
  [[ -d $worktree ]]
  [[ $(git -C "$repo" -C "$worktree" rev-parse --abbrev-ref HEAD) == x/*-wg-001-widget ]]
  [[ $(git -C "$repo" branch --list 'x/*' | wc -l) -eq 1 ]]

  # A third run adopts the healthy worktree without touching anything.
  rg -q '^X_WORKTREE_CREATED=no$' <<<"$(cd "$repo" && "$xdh" wg new --slug widget)"

  # A directory occupying the path that is not the expected worktree is a stop,
  # never something to silently overwrite.
  rm -rf "$worktree"
  git -C "$repo" worktree prune
  mkdir -p "$worktree"
  echo 'someone elses data' > "$worktree/keep.txt"
  if (cd "$repo" && "$xdh" wg new --slug widget >"$project/occupied.out" 2>&1); then
    return 1
  fi
  rg -q 'already occupied' "$project/occupied.out"
  [[ -f "$worktree/keep.txt" ]]
}

# A fake gh that answers the one query xdh makes, so PR selection can be tested
# without a network or a real GitHub repository.
write_fake_gh() {
  local bin=$1 rows=$2 owner=${3:-upstream}
  mkdir -p "$bin"
  cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr list") cat <<'ROWS'
$rows
ROWS
    ;;
  "repo view") printf '%s\n' '$owner' ;;
  "pr edit") printf '%s\n' "EDITED \$3" >> "$bin/../gh-calls.log" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$bin/gh"
}

test_xdh_pr_lookup_distinguishes_forks() {
  local project="$TEST_ROOT/xdh-pr" repo="$TEST_ROOT/xdh-pr-repo"
  local bin="$TEST_ROOT/xdh-pr-bin"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-ship/scripts/xdh"
  git -C "$repo" checkout -q -b fix
  git -C "$repo" remote add origin 'git@github.com:contributor/skill-x.git'

  # Without a provider the answer is "no provider", never an invented PR.
  rg -q '^X_PR_STATE=no-provider$' \
    <<<"$(cd "$repo" && PATH=/usr/bin:/bin "$xdh" pr status)"

  # Two forks have an open PR from a branch called `fix`. Matching on the
  # branch name alone would pick whichever came first and overwrite it.
  write_fake_gh "$bin" "$(printf '7\thttps://x/pull/7\tfix\tsomeone-else\n9\thttps://x/pull/9\tfix\tcontributor\n11\thttps://x/pull/11\tother\tcontributor')"
  local status
  status=$(cd "$repo" && PATH="$bin:$PATH" "$xdh" pr status)
  rg -q '^X_PR_HEAD_OWNER=contributor$' <<<"$status"
  rg -q '^X_PR_STATE=open$' <<<"$status"
  rg -q '^X_PR_NUMBER=9$' <<<"$status"
  rg -q '^X_PR_URL=https://x/pull/9$' <<<"$status"

  # An update targets that PR and no other.
  printf 'body\n' > "$project/body.md"
  local upsert
  upsert=$(cd "$repo" && PATH="$bin:$PATH" "$xdh" pr upsert \
             --base main --title 't' --body-file "$project/body.md")
  rg -q '^X_PR_ACTION=updated$' <<<"$upsert"
  rg -qx 'EDITED 9' "$TEST_ROOT/xdh-pr-bin/../gh-calls.log"

  # When the owner cannot break the tie, refuse rather than overwrite one.
  write_fake_gh "$bin" "$(printf '7\thttps://x/pull/7\tfix\t\n9\thttps://x/pull/9\tfix\t')"
  rg -q '^X_PR_STATE=ambiguous$' \
    <<<"$(cd "$repo" && PATH="$bin:$PATH" "$xdh" pr status)"
  if (cd "$repo" && PATH="$bin:$PATH" "$xdh" pr upsert --base main --title t \
        --body-file "$project/body.md" >"$project/amb-pr.out" 2>&1); then
    return 1
  fi
  rg -q 'several open PRs match' "$project/amb-pr.out"
}

test_xdh_keeps_every_temporary_file_inside_the_project() {
  local project="$TEST_ROOT/xdh-tmp" repo="$TEST_ROOT/xdh-tmp-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-review/scripts/xdh"

  # Pointing TMPDIR at a directory that does not exist is the only assertion
  # that actually bites: a helper that stages through the shared temp directory
  # fails outright here, while one that stages beside its target does not care.
  # (Checking for leftovers instead would pass even for a /tmp write that is
  # cleaned up afterwards.)
  local forbidden="$TEST_ROOT/xdh-tmp-does-not-exist"
  run_xdh_without_tmpdir() { (cd "$repo" && TMPDIR="$forbidden" "$xdh" "$@"); }

  run_xdh_without_tmpdir cycle new --slug tmp-check >/dev/null
  local item
  item=$(run_xdh_without_tmpdir item new --type issue --slug thing |
         rg -N --replace '$1' '^X_ITEM_FILE=(.*)$')
  run_xdh_without_tmpdir field set "$item" Status ready >/dev/null
  run_xdh_without_tmpdir fingerprint >/dev/null
  run_xdh_without_tmpdir wg new --slug tmp-wg >/dev/null

  [[ ! -e $forbidden ]]
  rg -q '^- Status: ready$' "$item"
  # Nothing is left behind beside the documents that were staged, either.
  [[ -z $(find "$repo/.dev-hub" -name '.xdh-field.*') ]]
  [[ -z $(find "$repo/.dev-hub" -name '.xdh-write.*') ]]
  [[ -z $(find "$repo/.dev-hub/runtime/.tmp" -type f 2>/dev/null) ]]
}

test_xdh_cleanup_survives_a_path_containing_spaces() {
  # The repository sits under a directory with a space, as it routinely does on
  # macOS ("My Projects", "Mobile Documents"). Word-splitting the scan records
  # truncated every path at the first space.
  local project="$TEST_ROOT/xdh-space" repo="$TEST_ROOT/xdh-space/with space/repo"
  copy_built_project "$project"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'
  echo seed > "$repo/seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial
  local xdh="$project/commands/x-housekeeping/scripts/xdh"

  # The decoy is exactly what the truncated path resolved to. If cleanup ever
  # word-splits again, this directory is what rm -rf destroys.
  local decoy="$TEST_ROOT/xdh-space/with"
  mkdir -p "$decoy"
  echo 'unrelated data' > "$decoy/decoy.txt"

  (cd "$repo" && "$xdh" cycle new --slug spaced >/dev/null)
  local worktree
  worktree=$(cd "$repo" && "$xdh" wg new --slug widget |
             rg -N --replace '$1' '^X_WG_WORKTREE=(.*)$')
  [[ $worktree == *' '* ]]

  # Uncommitted work is still protected when the path has a space — the old
  # parse made `git -C <truncated> status` fail, which read as "clean".
  echo scratch > "$worktree/scratch.txt"
  rg -q '^ITEM\tDIRTY\tworktree\t' <<<"$(cd "$repo" && "$xdh" clean scan)"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -d $worktree ]]
  [[ -f "$worktree/scratch.txt" ]]

  # And a genuinely finished worktree is actually removed, not left behind
  # with "removal-failed".
  rm -f "$worktree/scratch.txt"
  rg -q '^ITEM\tSAFE\tworktree\t' <<<"$(cd "$repo" && "$xdh" clean scan)"
  local applied
  applied=$(cd "$repo" && "$xdh" clean apply)
  rg -q '^REMOVED worktree ' <<<"$applied"
  [[ ! -d $worktree ]]

  # Nothing outside the repository was touched.
  [[ -f "$decoy/decoy.txt" ]]
  [[ $(cat "$decoy/decoy.txt") == 'unrelated data' ]]
  [[ -d "$TEST_ROOT/xdh-space/with space" ]]
}

test_xdh_standalone_planning_is_reusable() {
  local project="$TEST_ROOT/xdh-standalone" repo="$TEST_ROOT/xdh-standalone-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-plan-eng/scripts/xdh"
  # No Cycle anywhere: this is x-plan-eng invoked on a single requirement.
  [[ ! -d "$repo/.dev-hub/active" || -z $(find "$repo/.dev-hub/active" -mindepth 1) ]]

  # Work items need no flag and reuse on the second call.
  local first second
  first=$(cd "$repo" && "$xdh" item new --type issue --slug lone-task)
  rg -q '^X_ITEM_ID=IS-001$' <<<"$first"
  rg -q '^X_ITEM_REUSED=no$' <<<"$first"
  second=$(cd "$repo" && "$xdh" item new --type issue --slug lone-task)
  rg -q '^X_ITEM_REUSED=yes$' <<<"$second"
  [[ $(rg '^X_ITEM_FILE=' <<<"$first") == "$(rg '^X_ITEM_FILE=' <<<"$second")" ]]
  [[ $(find "$repo/.dev-hub" -name 'IS-*.md' | wc -l) -eq 1 ]]

  # A second, different item shares the standalone ID space.
  rg -q '^X_ITEM_ID=IS-002$' <<<"$(cd "$repo" && "$xdh" item new --type issue --slug other-task)"

  # Work Groups reuse too: the scope must not move between invocations, or the
  # same slug ends up with a second branch and a second worktree.
  local wg1 wg2
  wg1=$(cd "$repo" && "$xdh" wg new --slug lone-task --items IS-001)
  rg -q '^X_WG_ID=WG-001$' <<<"$wg1"
  rg -q '^X_WG_REUSED=no$' <<<"$wg1"
  wg2=$(cd "$repo" && "$xdh" wg new --slug lone-task)
  rg -q '^X_WG_REUSED=yes$' <<<"$wg2"
  rg -q '^X_WORKTREE_CREATED=no$' <<<"$wg2"
  [[ $(rg '^X_WG_BRANCH=' <<<"$wg1") == "$(rg '^X_WG_BRANCH=' <<<"$wg2")" ]]
  [[ $(rg '^X_WG_FILE=' <<<"$wg1") == "$(rg '^X_WG_FILE=' <<<"$wg2")" ]]
  [[ $(git -C "$repo" branch --list 'x/*' | wc -l) -eq 1 ]]
  [[ $(git -C "$repo" worktree list | wc -l) -eq 2 ]]
  [[ $(find "$repo/.dev-hub" -name 'WG-*.md' | wc -l) -eq 1 ]]

  # Concurrent standalone planning is mutually excluded, which it cannot be
  # while the lock lives in a directory minted fresh per invocation.
  local wg
  for wg in alpha beta gamma; do
    (cd "$repo" && "$xdh" wg new --slug "$wg" > "$project/sa-$wg.out" 2>&1) &
  done
  wait
  [[ $(cat "$project"/sa-*.out | rg '^X_WG_ID=' | sort -u | wc -l) -eq 3 ]]

  # An explicit --dir still wins, for callers that want an isolated bundle.
  local bundle
  bundle=$(cd "$repo" && "$xdh" runtime new --skill x-plan-eng --slug bundle |
           rg -N --replace '$1' '^X_RUNTIME_DIR=(.*)$')
  rg -q "^X_ITEM_FILE=$bundle/IS-001-scoped\.md$" \
    <<<"$(cd "$repo" && "$xdh" item new --type issue --slug scoped --dir "$bundle")"
}

test_xdh_housekeeping_spares_runtime_holding_live_work() {
  local project="$TEST_ROOT/xdh-live" repo="$TEST_ROOT/xdh-live-repo"
  make_xdh_fixture "$project" "$repo"
  local xdh="$project/commands/x-housekeeping/scripts/xdh"

  (cd "$repo" && "$xdh" wg new --slug ongoing >/dev/null)
  local standalone
  standalone=$(cd "$repo/.dev-hub/runtime/standalone" && pwd -P)
  [[ -d $standalone ]]
  local wg_file
  wg_file=$(find "$standalone" -name 'WG-*.md' | head -1)
  [[ -n $wg_file ]]

  # Age it well past the retention window. Age alone must not make live
  # planning state collectable, or an open Work Group gets rm -rf'd.
  touch -t 200001010000.00 "$standalone"
  local scan
  scan=$(cd "$repo" && "$xdh" clean scan)
  rg -q "^ITEM\tACTIVE\truntime\t$standalone\tholds-live-work$" <<<"$scan"
  (cd "$repo" && "$xdh" clean apply >/dev/null)
  [[ -f $wg_file ]]

  # Once the work is finished, the same directory becomes collectable.
  (cd "$repo" && "$xdh" field set "$wg_file" Status merged >/dev/null)
  touch -t 200001010000.00 "$standalone"
  rg -q "^ITEM\tSAFE\truntime\t$standalone\t" <<<"$(cd "$repo" && "$xdh" clean scan)"
}

test_sync_new_canonical_consumer_from_targets_conf() {
  local project="$TEST_ROOT/new-consumer"
  local home="$TEST_ROOT/new-consumer-home"
  copy_built_project "$project"

  mkdir -p "$home/.my-custom-agent/skills"
  cat > "$project/bin/targets/targets.conf" <<'EOF'
# Target registry for bin/build.sh.

CANONICAL_DEST="commands"
CANONICAL_CONSUMERS=(
  "claude-code:~/.claude/skills"
  "codex:~/.codex/skills"
  "codex-defensive:~/.agents/skills"
  "opencode-v2:~/.config/opencode/skills"
  "my-custom-agent:~/.my-custom-agent/skills"
)

TRANSFORMED_TARGETS=(
  "opencode-v1-commands:opencode-commands"
)
EOF

  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null

  [[ -L "$home/.my-custom-agent/skills/example-skill" ]]
  link_target=$(readlink "$home/.my-custom-agent/skills/example-skill")
  expected="$project/commands/example-skill"
  [[ "$(realpath -- "$link_target")" == "$(realpath -- "$expected")" ]]
}

test_cloud_v2_bootstrap_removes_managed_shims_preserves_user_files() {
  local project="$TEST_ROOT/cloud-v2-shims"
  local remote="$TEST_ROOT/cloud-v2-shims.git"
  local home="$TEST_ROOT/cloud-v2-shims-home"
  local commands="$home/.config/opencode/commands"
  make_git_fixture "$project" "$remote"
  local ref
  ref=$(git -C "$project" rev-parse HEAD)
  mkdir -p "$commands"
  cp "$project/opencode-commands/example-skill.md" "$commands/example-skill.md"
  echo 'user owned other' > "$commands/other-command.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v2 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>"$project/cloud-warnings"

  [[ ! -e "$commands/example-skill.md" ]]
  [[ ! -e "$commands/funny-text-rewriter.md" ]]
  [[ $(cat "$commands/other-command.md") == 'user owned other' ]]
  [[ -f "$home/.config/opencode/skills/example-skill/SKILL.md" ]]
}

# Regression for issue #13: build outputs are disposable gitignored
# artifacts, so a clean source-only checkout must produce them on demand
# and must not leave them as tracked changes.
test_build_outputs_are_gitignored_artifacts() {
  local project="$TEST_ROOT/source-only"
  copy_project "$project"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'

  # The .gitignore must list every disposable artifact produced by build.sh.
  rg -q '^commands/$' "$project/.gitignore"
  rg -q '^opencode-commands/$' "$project/.gitignore"

  "$project/bin/build.sh" >/dev/null
  [[ -d "$project/commands" ]]
  [[ -d "$project/opencode-commands" ]]

  git -C "$project" add .
  git -C "$project" commit -qm initial

  local status
  status=$(git -C "$project" status --short -- commands opencode-commands)
  [[ -z "$status" ]]

  # Editing a source skill must regenerate artifacts but never register
  # them as tracked modifications.
  printf '\nchanged body\n' >> "$project/commands-src/example-skill/SKILL.md"
  "$project/bin/build.sh" >/dev/null
  [[ -d "$project/commands" ]]
  status=$(git -C "$project" status --short -- commands opencode-commands)
  [[ -z "$status" ]]
}

# Regression for issue #13: a fresh source-only clone installs all
# supported skills and commands through install.sh alone.
test_install_from_source_only_checkout() {
  local project="$TEST_ROOT/source-install"
  local home="$TEST_ROOT/source-install-home"
  copy_project "$project"
  # Strip every artifact so install.sh has to build from scratch.
  rm -rf "$project/commands" "$project/opencode-commands"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  [[ ! -d "$project/commands" ]]
  [[ ! -d "$project/opencode-commands" ]]

  HOME="$home" "$project/install.sh" >/dev/null
  for path in \
    .claude/skills/example-skill \
    .codex/skills/example-skill \
    .agents/skills/example-skill \
    .config/opencode/skills/example-skill \
    .config/opencode/commands/example-skill.md; do
    [[ -e "$home/$path" ]]
  done
}

# Regression for issue #13: bin/apply-update.sh rebuilds artifacts after a
# successful fast-forward and before sync, so consumers never observe a
# stale tree from before the pull.
test_apply_update_rebuilds_after_pull() {
  local project="$TEST_ROOT/rebuild-update"
  local remote="$TEST_ROOT/rebuild-update.git"
  local author="$TEST_ROOT/rebuild-update-author"
  local home="$TEST_ROOT/rebuild-update-home"
  local state="$TEST_ROOT/rebuild-update-state"
  make_git_fixture "$project" "$remote"
  git clone -q "$remote" "$author"
  git -C "$author" config user.email test@example.invalid
  git -C "$author" config user.name 'Test Runner'

  # Author adds a brand new skill on a remote branch that hasn't been
  # built locally yet, then pushes it.
  mkdir -p "$author/commands-src/remote-skill"
  cat > "$author/commands-src/remote-skill/SKILL.md" <<'EOF'
---
name: remote-skill
description: fixture
---

body
EOF
  git -C "$author" add commands-src/remote-skill
  git -C "$author" commit -qm add-remote-skill
  git -C "$author" push -q

  # Sanity: local project only has commands-src/, no artifact tree.
  [[ ! -d "$project/commands/remote-skill" ]]

  mkdir -p "$state"
  : > "$state/last-check"

  HOME="$home" SKILL_X_STATE_DIR="$state" \
    "$project/bin/apply-update.sh" >/dev/null

  # The new skill must be present in the artifact tree and symlinked
  # into every canonical consumer, because the rebuild happened.
  [[ -f "$project/commands/remote-skill/SKILL.md" ]]
  [[ -f "$project/opencode-commands/remote-skill.md" ]]
  [[ -L "$home/.claude/skills/remote-skill" ]]
  [[ -L "$home/.codex/skills/remote-skill" ]]
  [[ -L "$home/.agents/skills/remote-skill" ]]
  [[ -L "$home/.config/opencode/skills/remote-skill" ]]
  [[ -L "$home/.config/opencode/commands/remote-skill.md" ]]
}

# Regression for issue #13: a pinned ref that contains only canonical
# source plus build inputs must still produce a complete install, because
# cloud-bootstrap.sh builds before copying.
test_cloud_bootstrap_uses_source_only_ref() {
  local project="$TEST_ROOT/source-only-ref"
  local remote="$TEST_ROOT/source-only-ref.git"
  local home="$TEST_ROOT/source-only-ref-home"
  local bare="$TEST_ROOT/source-only-ref-bare.git"
  copy_project "$project"
  # Push a ref that has never been built: only source files are tracked.
  git init -q --bare "$bare"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  [[ ! -d "$project/commands" ]]
  [[ ! -d "$project/opencode-commands" ]]
  git -C "$project" remote add origin "$bare"
  git -C "$project" push -qu origin HEAD
  local ref
  ref=$(git -C "$project" rev-parse HEAD)

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$project/bin/cloud-bootstrap.sh" "file://$bare" "$ref" >/dev/null
  for path in \
    .claude/skills/example-skill \
    .codex/skills/example-skill \
    .agents/skills/example-skill \
    .config/opencode/skills/example-skill \
    .config/opencode/commands/example-skill.md; do
    [[ -e "$home/$path" ]]
  done
  # Pinned installs copy artifacts rather than symlink them.
  [[ ! -L "$home/.claude/skills/example-skill" ]]
}

# ---------------------------------------------------------------------------
# Lifecycle CLI (bin/skill-x)
# ---------------------------------------------------------------------------

# A checkout plus a bare remote it tracks, already installed for one agent.
make_installed_fixture() {
  local project=$1 remote=$2 home=$3 agents=$4
  make_git_fixture "$project" "$remote"
  HOME="$home" SKILL_X_AGENTS="$agents" "$project/bin/skill-x" install >/dev/null 2>&1
}

manifest_of() {
  # -print -quit rather than a pipe into head: the suite runs with pipefail and
  # a killed find would fail the caller.
  find "$1/.local/state/skill-x" -mindepth 2 -maxdepth 2 -name install.json -print -quit 2>/dev/null
}

test_init_installs_only_selected_agents() {
  local project="$TEST_ROOT/select"
  local home="$TEST_ROOT/select-home"
  copy_project "$project"

  HOME="$home" "$project/bin/skill-x" init --agents claude >/dev/null

  [[ -L "$home/.claude/skills/example-skill" ]]
  # Nothing is created for an agent the user did not select.
  [[ ! -e "$home/.codex" ]]
  [[ ! -e "$home/.agents" ]]
  [[ ! -e "$home/.config/opencode" ]]

  # An unknown agent is rejected instead of being silently ignored.
  if HOME="$home" "$project/bin/skill-x" init --agents nope >/dev/null 2>&1; then
    return 1
  fi
}

test_install_is_idempotent_and_records_a_manifest() {
  local project="$TEST_ROOT/idempotent"
  local home="$TEST_ROOT/idempotent home"   # a space proves the JSON round-trips
  copy_project "$project"

  HOME="$home" "$project/bin/skill-x" install --agents claude,opencode >/dev/null
  local manifest first
  manifest=$(manifest_of "$home")
  [[ -n "$manifest" ]]
  cp "$manifest" "$project/manifest-1.json"
  first=$(find "$home/.claude" "$home/.config/opencode" "$home/.local/state/skill-x" -mindepth 1 | sort)

  # An empty SKILL_X_AGENTS falls through to the recorded selection.
  HOME="$home" SKILL_X_AGENTS= "$project/bin/skill-x" install >/dev/null
  [[ "$(find "$home/.claude" "$home/.config/opencode" "$home/.local/state/skill-x" -mindepth 1 | sort)" == "$first" ]]

  # Only the timestamps may move between two identical installs.
  diff <(rg -v '"last_' "$project/manifest-1.json") <(rg -v '"last_' "$manifest")

  rg -q '"agents": \["claude", "opencode"\]' "$manifest"
  rg -q '"opencode_mode": "v1"' "$manifest"
  [[ "$(awk -f "$project/bin/lib/manifest.awk" -v mode=array -v key=skills "$manifest")" == \
     "$(find "$project/commands" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | sed 's#/SKILL.md$##; s#.*/##' | sort)" ]]
  rg -qF "\"checkout_path\": \"$project\"" "$manifest"
  # Paths containing a space survive writing and reading the manifest.
  rg -qF "\"path\": \"$home/.claude/skills/example-skill\"" "$manifest"
  HOME="$home" "$project/bin/skill-x" doctor --strict >/dev/null
}

test_install_repairs_a_moved_checkout() {
  local project="$TEST_ROOT/moved"
  local moved="$TEST_ROOT/moved-elsewhere"
  local home="$TEST_ROOT/moved-home"
  copy_project "$project"
  git -C "$project" init -q
  HOME="$home" "$project/bin/skill-x" install --agents claude >/dev/null

  mv "$project" "$moved"

  # The stale absolute links must be identified, not just reported as broken.
  HOME="$home" "$moved/bin/skill-x" doctor > "$moved/doctor.txt" 2>&1 || true
  rg -q "checkout recorded at $project but running from $moved" "$moved/doctor.txt"
  rg -q 'STALE' "$moved/doctor.txt"
  if HOME="$home" "$moved/bin/skill-x" doctor --strict >/dev/null 2>&1; then
    return 1
  fi

  HOME="$home" SKILL_X_AGENTS= "$moved/bin/skill-x" install >/dev/null
  HOME="$home" "$moved/bin/skill-x" doctor --strict >/dev/null
  [[ $(readlink "$home/.claude/skills/example-skill") == "$moved/commands/example-skill" ]]
}

test_sync_drops_deselected_agents() {
  local project="$TEST_ROOT/deselect"
  local home="$TEST_ROOT/deselect-home"
  copy_project "$project"
  HOME="$home" "$project/bin/skill-x" install --agents claude,opencode >/dev/null
  [[ -L "$home/.config/opencode/skills/example-skill" ]]
  mkdir -p "$home/.config/opencode/commands"
  echo 'user owned' > "$home/.config/opencode/commands/mine.md"

  HOME="$home" "$project/bin/skill-x" sync --agents claude >/dev/null 2>&1

  [[ -L "$home/.claude/skills/example-skill" ]]
  [[ ! -e "$home/.config/opencode/skills/example-skill" ]]
  [[ ! -e "$home/.config/opencode/commands/example-skill.md" ]]
  [[ -f "$home/.config/opencode/commands/mine.md" ]]
  HOME="$home" "$project/bin/skill-x" doctor --strict >/dev/null
}

test_status_reports_behind_and_stable_json() {
  local project="$TEST_ROOT/status"
  local remote="$TEST_ROOT/status.git"
  local home="$TEST_ROOT/status-home"
  local author="$TEST_ROOT/status-author"
  make_installed_fixture "$project" "$remote" "$home" claude

  HOME="$home" "$project/bin/skill-x" status --json > "$TEST_ROOT/status-current.json"
  rg -q '"state": "current"' "$TEST_ROOT/status-current.json"
  rg -q '"update_available": false' "$TEST_ROOT/status-current.json"

  # The JSON contract is the machine-readable surface; keep its shape pinned.
  diff <(rg -o '^  "[a-z_]+"' "$TEST_ROOT/status-current.json" | tr -d ' "') - <<'EOF'
schema
installation_id
checkout_path
recorded_checkout_path
checkout_moved
installed
repository_url
commit
branch
upstream
state
state_reason
behind
ahead
dirty
update_available
agents
agent_versions
opencode_mode
skills
paths
entries
EOF

  git clone -q "$remote" "$author"
  git -C "$author" config user.email test@example.invalid
  git -C "$author" config user.name 'Test Runner'
  echo later > "$author/later"
  git -C "$author" add later
  git -C "$author" commit -qm later
  git -C "$author" push -q

  # An out-of-date checkout must say so without waiting for a skill invocation,
  # which means fetching rather than trusting the local remote-tracking ref.
  HOME="$home" "$project/bin/skill-x" status --json > "$TEST_ROOT/status-behind.json"
  rg -q '"state": "behind"' "$TEST_ROOT/status-behind.json"
  rg -q '"behind": 1' "$TEST_ROOT/status-behind.json"
  rg -q '"update_available": true' "$TEST_ROOT/status-behind.json"
  HOME="$home" "$project/bin/skill-x" status > "$TEST_ROOT/status-behind.txt"
  rg -q '^  state         behind$' "$TEST_ROOT/status-behind.txt"

  # A stale remote-tracking ref must not be able to hide the update.
  git -C "$project" update-ref -d refs/remotes/origin/master 2>/dev/null || true
  HOME="$home" "$project/bin/skill-x" status --json > "$TEST_ROOT/status-refetch.json"
  rg -q '"state": "behind"' "$TEST_ROOT/status-refetch.json"
}

test_status_json_reports_unreachable_without_a_remote() {
  local project="$TEST_ROOT/unreachable"
  local home="$TEST_ROOT/unreachable-home"
  copy_project "$project"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  HOME="$home" "$project/bin/skill-x" install --agents claude >/dev/null

  HOME="$home" "$project/bin/skill-x" status --json > "$TEST_ROOT/status-unreachable.json"
  rg -q '"state": "unreachable"' "$TEST_ROOT/status-unreachable.json"
  rg -q '"state_reason": "no tracked upstream branch"' "$TEST_ROOT/status-unreachable.json"
}

test_update_refuses_dirty_and_diverged_checkouts() {
  local project="$TEST_ROOT/update-safety"
  local remote="$TEST_ROOT/update-safety.git"
  local home="$TEST_ROOT/update-safety-home"
  local author="$TEST_ROOT/update-safety-author"
  make_installed_fixture "$project" "$remote" "$home" claude

  git clone -q "$remote" "$author"
  git -C "$author" config user.email test@example.invalid
  git -C "$author" config user.name 'Test Runner'
  echo upstream > "$author/upstream-file"
  git -C "$author" add upstream-file
  git -C "$author" commit -qm upstream
  git -C "$author" push -q

  local before scratch="$TEST_ROOT/update-safety-scratch"
  mkdir -p "$scratch"
  before=$(readlink "$home/.claude/skills/example-skill")

  # An edit to a tracked file is what a fast-forward could conflict with.
  echo scratch >> "$project/commands-src/example-skill/SKILL.md"
  if HOME="$home" "$project/bin/skill-x" update --yes >/dev/null 2>"$scratch/dirty-error"; then
    return 1
  fi
  rg -q 'refusing to update a dirty checkout' "$scratch/dirty-error"
  [[ ! -e "$project/upstream-file" ]]
  git -C "$project" checkout -q -- commands-src/example-skill/SKILL.md

  # --check reports without touching anything, even when an update exists.
  HOME="$home" "$project/bin/skill-x" update --check > "$scratch/check.txt"
  rg -q 'Update available' "$scratch/check.txt"
  [[ ! -e "$project/upstream-file" ]]

  # Without a terminal there is nobody to ask, so an unconfirmed update fails.
  if HOME="$home" "$project/bin/skill-x" update </dev/null >/dev/null 2>"$scratch/confirm-error"; then
    return 1
  fi
  rg -q 'refusing to update without confirmation' "$scratch/confirm-error"

  git -C "$project" commit -q --allow-empty -m 'local only'
  if HOME="$home" "$project/bin/skill-x" update --yes >/dev/null 2>"$scratch/diverged-error"; then
    return 1
  fi
  rg -q 'refusing to update a diverged checkout' "$scratch/diverged-error"
  [[ ! -e "$project/upstream-file" ]]
  [[ $(readlink "$home/.claude/skills/example-skill") == "$before" ]]
}

test_update_fast_forwards_and_refreshes_everything() {
  local project="$TEST_ROOT/update-apply"
  local remote="$TEST_ROOT/update-apply.git"
  local home="$TEST_ROOT/update-apply-home"
  local author="$TEST_ROOT/update-apply-author"
  make_installed_fixture "$project" "$remote" "$home" claude,opencode

  git clone -q "$remote" "$author"
  git -C "$author" config user.email test@example.invalid
  git -C "$author" config user.name 'Test Runner'
  mkdir -p "$author/commands-src/added-skill"
  cat > "$author/commands-src/added-skill/SKILL.md" <<'EOF'
---
name: added-skill
description: fixture
---

body
EOF
  "$author/bin/build.sh" >/dev/null
  git -C "$author" add -A
  git -C "$author" commit -qm 'add added-skill'
  git -C "$author" push -q

  local state
  state=$(dirname "$(manifest_of "$home")")
  mkdir -p "$state"
  : > "$state/last-check"
  : > "$state/snooze-until"

  HOME="$home" "$project/bin/skill-x" update --yes > "$TEST_ROOT/update-apply.txt" 2>&1
  rg -q 'skills changed    added-skill' "$TEST_ROOT/update-apply.txt"

  [[ -L "$home/.claude/skills/added-skill" ]]
  [[ -L "$home/.config/opencode/commands/added-skill.md" ]]
  [[ -f "$project/commands/added-skill/SKILL.md" ]]
  # The update must leave no throttle or snooze state pretending to be current.
  [[ ! -e "$state/last-check" && ! -e "$state/snooze-until" ]]
  rg -q '"last_update": "2' "$(manifest_of "$home")"
  HOME="$home" "$project/bin/skill-x" doctor --strict >/dev/null
}

test_uninstall_removes_managed_entries_only() {
  local project="$TEST_ROOT/uninstall"
  local home="$TEST_ROOT/uninstall-home"
  copy_project "$project"
  HOME="$home" "$project/bin/skill-x" install --agents claude,codex,opencode >/dev/null

  # A user-owned directory that collides with a managed name, plus an unrelated
  # skill and command that skill-x never touched.
  rm "$home/.claude/skills/herdr"
  mkdir -p "$home/.claude/skills/herdr" "$home/.claude/skills/user-skill"
  echo mine > "$home/.claude/skills/herdr/SKILL.md"
  echo mine > "$home/.claude/skills/user-skill/SKILL.md"
  echo mine > "$home/.config/opencode/commands/user-command.md"

  # Removing one agent keeps the manifest and the other agents intact.
  HOME="$home" "$project/bin/skill-x" uninstall --agents codex --yes >/dev/null
  [[ ! -e "$home/.agents/skills/example-skill" ]]
  [[ ! -e "$home/.codex/skills/example-skill" ]]
  [[ -L "$home/.claude/skills/example-skill" ]]
  rg -q '"agents": \["claude", "opencode"\]' "$(manifest_of "$home")"

  HOME="$home" "$project/bin/skill-x" uninstall --yes > "$project/uninstall.txt"

  [[ ! -e "$home/.claude/skills/example-skill" ]]
  [[ ! -e "$home/.config/opencode/skills/example-skill" ]]
  [[ ! -e "$home/.config/opencode/commands/example-skill.md" ]]
  # Everything the user owns survives, including the colliding name.
  [[ $(cat "$home/.claude/skills/herdr/SKILL.md") == mine ]]
  [[ $(cat "$home/.claude/skills/user-skill/SKILL.md") == mine ]]
  [[ $(cat "$home/.config/opencode/commands/user-command.md") == mine ]]
  rg -q 'preserved .*/.claude/skills/herdr' "$project/uninstall.txt"
  # The checkout stays unless it is explicitly asked for.
  [[ -f "$project/bin/skill-x" ]]
  [[ -z $(manifest_of "$home") ]]
}

test_uninstall_refuses_to_delete_a_dirty_checkout() {
  local project="$TEST_ROOT/uninstall-dirty"
  local home="$TEST_ROOT/uninstall-dirty-home"
  copy_built_project "$project"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  HOME="$home" "$project/bin/skill-x" install --agents claude >/dev/null
  echo scratch > "$project/uncommitted"

  # Even an untracked file is enough: deleting the checkout would destroy it.
  if HOME="$home" "$project/bin/skill-x" uninstall --yes --remove-checkout \
      >/dev/null 2>"$TEST_ROOT/uninstall-dirty-error"; then
    return 1
  fi
  rg -q 'refusing to delete a dirty checkout' "$TEST_ROOT/uninstall-dirty-error"
  [[ -d "$project" ]]

  rm "$project/uncommitted"
  HOME="$home" "$project/bin/skill-x" uninstall --yes --remove-checkout >/dev/null
  [[ ! -e "$project" ]]
}

test_update_state_is_namespaced_per_installation() {
  local one="$TEST_ROOT/ns-one"
  local two="$TEST_ROOT/ns-two"
  local remote_one="$TEST_ROOT/ns-one.git"
  local remote_two="$TEST_ROOT/ns-two.git"
  local home="$TEST_ROOT/ns-home"
  local author="$TEST_ROOT/ns-author"
  make_git_fixture "$one" "$remote_one"
  make_git_fixture "$two" "$remote_two"

  advance() {
    local remote=$1 clone=$2
    git clone -q "$remote" "$clone"
    git -C "$clone" config user.email test@example.invalid
    git -C "$clone" config user.name 'Test Runner'
    git -C "$clone" commit -q --allow-empty -m newer
    git -C "$clone" push -q
  }
  advance "$remote_one" "$author-1"
  advance "$remote_two" "$author-2"

  [[ $(HOME="$home" SKILL_X_CHECK_INTERVAL_SECONDS=0 "$one/bin/update-check") == UPGRADE_AVAILABLE* ]]
  HOME="$home" "$one/bin/snooze.sh" >/dev/null

  # Snoozing one checkout must not silence an unrelated one.
  [[ $(HOME="$home" SKILL_X_CHECK_INTERVAL_SECONDS=0 "$one/bin/update-check") == UP_TO_DATE ]]
  [[ $(HOME="$home" SKILL_X_CHECK_INTERVAL_SECONDS=0 "$two/bin/update-check") == UPGRADE_AVAILABLE* ]]

  # The check can be switched off entirely; the CLI stays authoritative.
  [[ -z $(HOME="$home" SKILL_X_DISABLE_UPDATE_CHECK=1 SKILL_X_CHECK_INTERVAL_SECONDS=0 "$two/bin/update-check") ]]
}

test_cloud_bootstrap_does_not_copy_through_managed_symlinks() {
  local project="$TEST_ROOT/cloud-symlink"
  local remote="$TEST_ROOT/cloud-symlink.git"
  local home="$TEST_ROOT/cloud-symlink-home"
  make_git_fixture "$project" "$remote"
  local ref
  ref=$(git -C "$project" rev-parse HEAD)

  # An interactive install in the same HOME leaves symlinks pointing back into
  # the checkout; a pinned copy must replace them, never write through them.
  HOME="$home" SKILL_X_AGENTS=claude,opencode "$project/bin/skill-x" install >/dev/null
  echo 'CHECKOUT-SENTINEL' >> "$project/commands/example-skill/SKILL.md"
  echo 'CHECKOUT-SENTINEL' >> "$project/opencode-commands/example-skill.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>&1

  rg -q 'CHECKOUT-SENTINEL' "$project/commands/example-skill/SKILL.md"
  rg -q 'CHECKOUT-SENTINEL' "$project/opencode-commands/example-skill.md"
  for path in \
    .claude/skills/example-skill \
    .config/opencode/skills/example-skill \
    .config/opencode/commands/example-skill.md; do
    [[ ! -L "$home/$path" ]]
    [[ -e "$home/$path" ]]
  done
  ! rg -q 'CHECKOUT-SENTINEL' "$home/.claude/skills/example-skill/SKILL.md"
  ! rg -q 'CHECKOUT-SENTINEL' "$home/.config/opencode/commands/example-skill.md"
}

test_cloud_bootstrap_v2_removes_pinned_v1_shims() {
  local project="$TEST_ROOT/cloud-v2"
  local remote="$TEST_ROOT/cloud-v2.git"
  local home="$TEST_ROOT/cloud-v2-home"
  local commands="$home/.config/opencode/commands"
  make_git_fixture "$project" "$remote"
  local ref
  ref=$(git -C "$project" rev-parse HEAD)

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>&1
  [[ -f "$commands/example-skill.md" && ! -L "$commands/example-skill.md" ]]
  echo 'user owned' > "$commands/user-command.md"

  # Rebuilding the image on a reused layer with OpenCode v2 must clear the
  # pinned copies, or every skill shows up twice.
  HOME="$home" SKILL_X_OPENCODE_VERSION=v2 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>&1

  [[ ! -e "$commands/example-skill.md" ]]
  [[ ! -e "$commands/funny-text-rewriter.md" ]]
  [[ $(cat "$commands/user-command.md") == 'user owned' ]]
  [[ -f "$home/.config/opencode/skills/example-skill/SKILL.md" ]]
}

run_test --fast 'harness terminates a stalled test' test_harness_terminates_a_stalled_test
run_test --fast 'build injects once and copies support files' test_build_injects_header_and_support_files
run_test --fast 'invalid build preserves previous deployment' test_build_rejects_invalid_frontmatter_without_destroying_output
run_test --fast 'build accepts crlf frontmatter' test_build_accepts_crlf_frontmatter
run_test --fast 'build generates delegating opencode command shims' test_build_generates_opencode_command_shims
run_test --fast 'opencode version detection and override' test_opencode_version_detection
run_test --fast 'sync is idempotent and preserves collisions' test_sync_is_idempotent_and_preserves_collisions
run_test 'sync removes links for deleted skills' test_sync_removes_links_for_deleted_skills
run_test 'sync installs opencode v1 commands without clobbering' test_sync_installs_opencode_v1_commands
run_test 'sync removes stale opencode commands' test_sync_removes_stale_opencode_commands
run_test 'opencode v2 sync removes generated commands' test_sync_v2_removes_generated_commands
run_test --fast 'build outputs are gitignored disposable artifacts' test_build_outputs_are_gitignored_artifacts
run_test 'install from source-only checkout succeeds' test_install_from_source_only_checkout
run_test 'apply update rebuilds after pull' test_apply_update_rebuilds_after_pull
run_test 'cloud bootstrap builds source-only pinned ref' test_cloud_bootstrap_uses_source_only_ref
run_test 'update check reports current, upgrade, and snooze states' test_update_check_states
run_test 'update check fails open without a remote' test_update_check_fails_open_without_remote
run_test 'apply update fast-forwards and resynchronizes' test_apply_update_fast_forwards_and_resyncs
run_test 'cloud bootstrap installs copies from a pinned ref' test_cloud_bootstrap_copies_pinned_content
run_test 'cloud bootstrap installs pinned command shims' test_cloud_bootstrap_installs_command_shims
run_test --fast 'build materializes shared x-skill assets' test_build_materializes_shared_skill_assets
run_test 'xdh creates cycles and work items idempotently' test_xdh_creates_cycles_and_items_idempotently
run_test 'xdh binds one work group to one branch and worktree' test_xdh_work_group_binds_branch_and_worktree
run_test 'xdh fingerprints content, not time' test_xdh_fingerprint_tracks_content_not_time
run_test --fast 'x-review documents cross-model dispatch' test_x_review_documents_cross_model_dispatch
run_test 'x-review artifact records reviewer provenance' test_x_review_artifact_records_reviewer_provenance
run_test 'xdh housekeeping refuses unsafe removals' test_xdh_housekeeping_refuses_unsafe_removals
run_test 'xdh closes a cycle into a tracked log' test_xdh_cycle_closes_into_a_tracked_log
run_test 'xdh concurrent cycle creation yields one cycle' test_xdh_concurrent_cycle_creation_yields_one_cycle
run_test 'xdh concurrent allocation never reuses an id' test_xdh_concurrent_allocation_never_reuses_an_id
run_test 'xdh refuses to guess between ambiguous cycles' test_xdh_refuses_to_guess_between_ambiguous_cycles
run_test 'xdh recreates a stale worktree registration' test_xdh_recreates_a_stale_worktree_registration
run_test 'xdh pr lookup distinguishes forks' test_xdh_pr_lookup_distinguishes_forks
run_test 'xdh keeps temporary files inside the project' test_xdh_keeps_every_temporary_file_inside_the_project
run_test 'xdh cleanup survives a path containing spaces' test_xdh_cleanup_survives_a_path_containing_spaces
run_test 'xdh standalone planning is reusable' test_xdh_standalone_planning_is_reusable
run_test 'xdh housekeeping spares runtime holding live work' test_xdh_housekeeping_spares_runtime_holding_live_work
run_test 'new canonical consumer from targets.conf is synced locally' test_sync_new_canonical_consumer_from_targets_conf
run_test 'cloud v2 bootstrap removes managed shims preserves user files' test_cloud_v2_bootstrap_removes_managed_shims_preserves_user_files

run_test 'init installs only the selected agents' test_init_installs_only_selected_agents
run_test 'install is idempotent and records a manifest' test_install_is_idempotent_and_records_a_manifest
run_test 'install repairs a moved checkout' test_install_repairs_a_moved_checkout
run_test 'sync drops deselected agents' test_sync_drops_deselected_agents
run_test 'status reports behind with stable json' test_status_reports_behind_and_stable_json
run_test 'status reports unreachable without an upstream' test_status_json_reports_unreachable_without_a_remote
run_test 'update refuses dirty and diverged checkouts' test_update_refuses_dirty_and_diverged_checkouts
run_test 'update fast-forwards and refreshes everything' test_update_fast_forwards_and_refreshes_everything
run_test 'uninstall removes managed entries only' test_uninstall_removes_managed_entries_only
run_test 'uninstall refuses to delete a dirty checkout' test_uninstall_refuses_to_delete_a_dirty_checkout
run_test 'update state is namespaced per installation' test_update_state_is_namespaced_per_installation
run_test 'cloud bootstrap never copies through managed symlinks' test_cloud_bootstrap_does_not_copy_through_managed_symlinks
run_test 'cloud bootstrap v2 removes pinned v1 shims' test_cloud_bootstrap_v2_removes_pinned_v1_shims

skill_x_test_finish 'integration'
