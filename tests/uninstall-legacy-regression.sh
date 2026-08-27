#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-uninstall-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export SKILL_X_STATE_DIR="$TMP/state"
mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/commands" "$TMP/foreign"

ln -s "$ROOT/commands/retired-skill" "$HOME/.claude/skills/retired-skill"
ln -s "$ROOT/commands/old-codex-skill" "$HOME/.codex/skills/old-codex-skill"
ln -s "$TMP/foreign" "$HOME/.claude/skills/user-skill"
printf '# skill-x-managed-command\n' > "$HOME/.config/opencode/commands/old.md"
printf '# user command\n' > "$HOME/.config/opencode/commands/user.md"

bash "$ROOT/uninstall.sh" --yes >/dev/null

[[ ! -L "$HOME/.claude/skills/retired-skill" ]]
[[ ! -L "$HOME/.codex/skills/old-codex-skill" ]]
[[ -L "$HOME/.claude/skills/user-skill" ]]
[[ ! -e "$HOME/.config/opencode/commands/old.md" ]]
[[ -e "$HOME/.config/opencode/commands/user.md" ]]

echo 'legacy uninstall regression: ok'
