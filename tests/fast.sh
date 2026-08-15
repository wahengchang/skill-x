#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-fast-tests.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

export SKILL_X_OPENCODE_VERSION=v1
export SKILL_X_AGENTS=claude,codex,opencode

passed=0
failed=0
project="$TEST_ROOT/project"
home="$TEST_ROOT/home"

# Prepare one source-only project fixture and reuse its build/install state for
# all fast checks. The full suite intentionally keeps per-test isolation.
mkdir -p "$project"
cp -a "$PROJECT_ROOT/." "$project/"
rm -rf \
  "$project/.git" \
  "$project/.claude" \
  "$project/.dev-hub" \
  "$project/commands" \
  "$project/opencode-commands"

mkdir -p "$project/commands-src/fast-smoke/scripts"
cat > "$project/commands-src/fast-smoke/SKILL.md" <<'SKILL'
---
name: fast-smoke
description: Fast-suite fixture.
---

# Fast smoke body
SKILL
printf '#!/usr/bin/env bash\necho fast-smoke\n' > "$project/commands-src/fast-smoke/scripts/helper.sh"
chmod +x "$project/commands-src/fast-smoke/scripts/helper.sh"

run_test() {
  local name=$1
  shift
  local started=$SECONDS
  printf 'TEST  %s ... ' "$name"
  set +e
  (set -euo pipefail; "$@")
  local status=$?
  set -e
  local elapsed=$((SECONDS - started))
  if (( status == 0 )); then
    printf 'PASS (%ss)\n' "$elapsed"
    passed=$((passed + 1))
  else
    printf 'FAIL (%ss)\n' "$elapsed" >&2
    failed=$((failed + 1))
  fi
}

test_source_only_install_builds_and_smokes() {
  [[ ! -e "$project/commands" && ! -e "$project/opencode-commands" ]]

  HOME="$home" "$project/bin/skill-x" install --agents claude,codex,opencode >/dev/null

  local skill="$project/commands/fast-smoke/SKILL.md"
  [[ -f "$skill" ]]
  [[ $(rg -c '此區塊由 bin/build.sh' "$skill") -eq 1 ]]
  rg -q '^# Fast smoke body$' "$skill"
  cmp \
    "$project/commands-src/fast-smoke/scripts/helper.sh" \
    "$project/commands/fast-smoke/scripts/helper.sh"

  local shim="$project/opencode-commands/fast-smoke.md"
  [[ -f "$shim" ]]
  rg -qF 'Use the `skill` tool to load the `fast-smoke` skill' "$shim"
  rg -qF '$ARGUMENTS' "$shim"

  # Shared x-* support files must be materialized into canonical artifacts.
  [[ -x "$project/commands/x-discovery/scripts/xdh" ]]
  [[ ! -L "$project/commands/x-discovery/scripts/xdh" ]]

  [[ -L "$home/.claude/skills/fast-smoke" ]]
  [[ -L "$home/.codex/skills/fast-smoke" ]]
  [[ -L "$home/.agents/skills/fast-smoke" ]]
  [[ -L "$home/.config/opencode/commands/fast-smoke.md" ]]

  HOME="$home" "$project/bin/skill-x" doctor --strict >/dev/null
}

test_sync_is_idempotent() {
  local claude_target codex_target command_target
  claude_target=$(readlink "$home/.claude/skills/fast-smoke")
  codex_target=$(readlink "$home/.codex/skills/fast-smoke")
  command_target=$(readlink "$home/.config/opencode/commands/fast-smoke.md")

  HOME="$home" "$project/bin/skill-x" sync --agents claude,codex,opencode >/dev/null

  [[ $(readlink "$home/.claude/skills/fast-smoke") == "$claude_target" ]]
  [[ $(readlink "$home/.codex/skills/fast-smoke") == "$codex_target" ]]
  [[ $(readlink "$home/.config/opencode/commands/fast-smoke.md") == "$command_target" ]]
  HOME="$home" "$project/bin/skill-x" doctor --strict >/dev/null
}

test_generated_artifacts_are_ignored() {
  git -C "$project" init -q
  git -C "$project" check-ignore -q commands/fast-smoke/SKILL.md
  git -C "$project" check-ignore -q opencode-commands/fast-smoke.md
}

run_test 'source-only install builds artifacts and essential smoke paths' test_source_only_install_builds_and_smokes
run_test 'sync remains idempotent' test_sync_is_idempotent
run_test 'generated artifact trees remain disposable' test_generated_artifacts_are_ignored

printf '\nRESULT: %d passed, %d failed\n' "$passed" "$failed"
(( failed == 0 ))
