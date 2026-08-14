#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

passed=0
failed=0

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
  rm -rf "$destination/.git" "$destination/commands"
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
  "$project/bin/build.sh" >/dev/null
  diff -ru "$project/first-build" "$project/commands"
}

test_build_rejects_invalid_frontmatter_without_destroying_output() {
  local project="$TEST_ROOT/invalid-build"
  copy_project "$project"
  "$project/bin/build.sh" >/dev/null
  cp -a "$project/commands" "$project/expected"
  printf '# missing frontmatter\n' > "$project/commands-src/example-skill/SKILL.md"

  if "$project/bin/build.sh" >"$project/stdout" 2>"$project/stderr"; then
    return 1
  fi
  rg -q 'Invalid frontmatter' "$project/stderr"
  diff -ru "$project/expected" "$project/commands"
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

run_test 'build injects once and copies support files' test_build_injects_header_and_support_files
run_test 'invalid build preserves previous deployment' test_build_rejects_invalid_frontmatter_without_destroying_output
run_test 'build accepts crlf frontmatter' test_build_accepts_crlf_frontmatter
run_test 'sync is idempotent and preserves collisions' test_sync_is_idempotent_and_preserves_collisions
run_test 'sync removes links for deleted skills' test_sync_removes_links_for_deleted_skills
run_test 'update check reports current, upgrade, and snooze states' test_update_check_states
run_test 'update check fails open without a remote' test_update_check_fails_open_without_remote
run_test 'apply update fast-forwards and resynchronizes' test_apply_update_fast_forwards_and_resyncs
run_test 'cloud bootstrap installs copies from a pinned ref' test_cloud_bootstrap_copies_pinned_content

printf '\nRESULT: %d passed, %d failed\n' "$passed" "$failed"
(( failed == 0 ))
