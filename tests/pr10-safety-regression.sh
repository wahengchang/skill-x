#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-pr10-safety.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

export SKILL_X_OPENCODE_VERSION=v1
export SKILL_X_AGENTS=claude,codex,opencode

# shellcheck source=lib/harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"
skill_x_test_parse_args "$@"

manifest_of() {
  find "$1/.local/state/skill-x" -mindepth 2 -maxdepth 2 -name install.json -print -quit 2>/dev/null
}

manifest_target_for_path() {
  local project=$1 manifest=$2 wanted=$3
  local agent kind path target
  while IFS=$'\t' read -r agent kind path target; do
    if [[ "$path" == "$wanted" ]]; then
      printf '%s\n' "$target"
      return 0
    fi
  done < <(awk -f "$project/bin/lib/manifest.awk" -v mode=entries "$manifest")
  return 1
}

make_git_remote_fixture() {
  local project=$1 remote=$2
  copy_project "$project"
  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  git init -q --bare "$remote"
  git -C "$project" remote add origin "file://$remote"
  git -C "$project" push -q -u origin HEAD:main
}

test_sync_preserves_foreign_symlinks() {
  local project="$TEST_ROOT/sync-foreign"
  local home="$TEST_ROOT/sync-foreign-home"
  local foreign="$TEST_ROOT/user-example"
  copy_project "$project"

  mkdir -p "$home/.claude/skills" "$foreign"
  echo 'user-owned' > "$foreign/SKILL.md"
  ln -s "$foreign" "$home/.claude/skills/example-skill"

  HOME="$home" "$project/bin/skill-x" install --agents claude >/dev/null 2>&1

  [[ $(readlink "$home/.claude/skills/example-skill") == "$foreign" ]]
  [[ $(cat "$foreign/SKILL.md") == 'user-owned' ]]

  local manifest
  manifest=$(manifest_of "$home")
  [[ -n "$manifest" ]]
  if manifest_target_for_path "$project" "$manifest" "$home/.claude/skills/example-skill" >/dev/null; then
    echo 'foreign pre-existing symlink was incorrectly adopted into the manifest' >&2
    return 1
  fi

  # A link that was managed and then manually retargeted must also survive sync,
  # but its prior manifest entry stays so doctor can report it as FOREIGN.
  local managed="$home/.claude/skills/funny-text-rewriter"
  local expected
  expected=$(readlink "$managed")
  local replacement="$TEST_ROOT/user-funny"
  mkdir -p "$replacement"
  echo 'replacement' > "$replacement/SKILL.md"
  ln -sfn "$replacement" "$managed"

  HOME="$home" "$project/bin/skill-x" sync --agents claude >/dev/null 2>&1

  [[ $(readlink "$managed") == "$replacement" ]]
  [[ $(manifest_target_for_path "$project" "$manifest" "$managed") == "$expected" ]]
  HOME="$home" "$project/bin/skill-x" doctor > "$TEST_ROOT/doctor.txt" 2>&1
  grep -q 'FOREIGN' "$TEST_ROOT/doctor.txt"
  grep -qF "$managed" "$TEST_ROOT/doctor.txt"
  if HOME="$home" "$project/bin/skill-x" doctor --strict >/dev/null 2>&1; then
    echo 'doctor --strict accepted a retargeted managed symlink' >&2
    return 1
  fi
}

test_remove_checkout_refuses_ignored_local_files() {
  local project="$TEST_ROOT/remove-ignored"
  local home="$TEST_ROOT/remove-ignored-home"
  copy_project "$project"

  git -C "$project" init -q
  git -C "$project" config user.email test@example.invalid
  git -C "$project" config user.name 'Test Runner'
  git -C "$project" add .
  git -C "$project" commit -qm initial
  HOME="$home" "$project/bin/skill-x" install --agents claude >/dev/null 2>&1

  printf '.env\n' >> "$project/.git/info/exclude"
  echo 'LOCAL_SECRET=keep-me' > "$project/.env"

  if HOME="$home" "$project/bin/skill-x" uninstall --yes --remove-checkout \
      >/dev/null 2>"$TEST_ROOT/remove-ignored.err"; then
    echo 'uninstall deleted a checkout containing ignored local data' >&2
    return 1
  fi
  grep -q 'refusing to delete a dirty checkout' "$TEST_ROOT/remove-ignored.err"
  [[ -f "$project/.env" ]]
  [[ -L "$home/.claude/skills/example-skill" ]]
  [[ -n $(manifest_of "$home") ]]

  # Generated artifact trees are intentionally disposable and ignored; once the
  # unrelated ignored local file is gone they must not prevent checkout removal.
  rm "$project/.env"
  HOME="$home" "$project/bin/skill-x" uninstall --yes --remove-checkout >/dev/null 2>&1
  [[ ! -e "$project" ]]
}

test_cloud_bootstrap_preserves_foreign_symlink() {
  local project="$TEST_ROOT/cloud-foreign"
  local remote="$TEST_ROOT/cloud-foreign.git"
  local home="$TEST_ROOT/cloud-foreign-home"
  local foreign="$TEST_ROOT/cloud-user-skill"
  make_git_remote_fixture "$project" "$remote"

  local ref
  ref=$(git -C "$project" rev-parse HEAD)
  mkdir -p "$home/.claude/skills" "$foreign"
  echo 'cloud-user-owned' > "$foreign/SKILL.md"
  ln -s "$foreign" "$home/.claude/skills/example-skill"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$project/bin/cloud-bootstrap.sh" "file://$remote" "$ref" >/dev/null 2>"$TEST_ROOT/cloud-foreign.err"

  [[ -L "$home/.claude/skills/example-skill" ]]
  [[ $(readlink "$home/.claude/skills/example-skill") == "$foreign" ]]
  [[ $(cat "$foreign/SKILL.md") == 'cloud-user-owned' ]]
  grep -q 'preserving foreign symlink' "$TEST_ROOT/cloud-foreign.err"
}

run_test 'sync preserves foreign symlink ownership' test_sync_preserves_foreign_symlinks
run_test 'remove-checkout protects ignored local files' test_remove_checkout_refuses_ignored_local_files
run_test 'cloud bootstrap preserves foreign symlinks' test_cloud_bootstrap_preserves_foreign_symlink

skill_x_test_finish 'pr10 safety regression'
