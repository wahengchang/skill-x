#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-uninstall-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export SKILL_X_STATE_DIR="$TMP/state"
OLD="$TMP/deleted-old-checkout"
FOREIGN="$TMP/foreign"
mkdir -p \
  "$HOME/.claude/skills" \
  "$HOME/.codex/skills" \
  "$HOME/.config/opencode/skills/example-skill" \
  "$HOME/.config/opencode/commands" \
  "$FOREIGN/q-review"

# q-review existed in skill-x history but was later removed. The old checkout is
# gone, so this is a dangling link that cannot be discovered from current files.
ln -s "$OLD/commands/q-review" "$HOME/.claude/skills/q-review"
ln -s "$OLD/opencode-commands/q-review.md" "$HOME/.config/opencode/commands/q-review.md"

# Historical name alone is not enough to delete a live foreign skill.
printf '%s\n' '# user-owned q-review' > "$FOREIGN/q-review/SKILL.md"
ln -s "$FOREIGN/q-review" "$HOME/.codex/skills/q-review"

# Unknown dangling names must also survive even when they use a similar layout.
ln -s "$OLD/commands/not-from-skill-x" "$HOME/.claude/skills/not-from-skill-x"

# Old pinned copies are removable only when their generated header proves this
# repository owned them.
cat > "$HOME/.config/opencode/skills/example-skill/SKILL.md" <<'EOF'
<!-- generated -->
skill-x repository
bin/update-check
EOF

printf '# skill-x-managed-command\n' > "$HOME/.config/opencode/commands/old-managed.md"
printf '# user command\n' > "$HOME/.config/opencode/commands/user.md"

bash "$ROOT/uninstall.sh" --yes >/dev/null

[[ ! -L "$HOME/.claude/skills/q-review" ]]
[[ -L "$HOME/.codex/skills/q-review" ]]
[[ -L "$HOME/.claude/skills/not-from-skill-x" ]]
[[ ! -e "$HOME/.config/opencode/skills/example-skill" ]]
[[ ! -L "$HOME/.config/opencode/commands/q-review.md" ]]
[[ ! -e "$HOME/.config/opencode/commands/old-managed.md" ]]
[[ -e "$HOME/.config/opencode/commands/user.md" ]]

echo 'legacy uninstall regression: ok'
