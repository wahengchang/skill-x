#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
COMMAND_SOURCE="$ROOT/opencode-commands"
OPENCODE_COMMANDS="$HOME/.config/opencode/commands"
MANAGED_MARKER="skill-x-managed-command"

echo 'Skill discovery paths'
targets=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills" "$HOME/.config/opencode/skills")
for target in "${targets[@]}"; do
  printf '\n%s\n' "$target"
  if [[ ! -d "$target" ]]; then echo "  MISSING"; continue; fi
  while IFS= read -r -d '' item; do
    if [[ -L "$item" ]]; then printf '  OK      %s -> %s\n' "$(basename "$item")" "$(readlink "$item")"
    else printf '  COPY    %s\n' "$(basename "$item")"; fi
  done < <(find "$target" -mindepth 1 -maxdepth 1 -print0 | sort -z)
done

opencode_version=$("$ROOT/bin/opencode-version.sh")
cat <<EOF

Explicit invocation per agent
  Claude Code   /<skill>              automatic from ~/.claude/skills/<skill>/SKILL.md
  Codex         \$<skill> or /skills   automatic from ~/.codex/skills/<skill>/SKILL.md
                                      (deprecated custom prompts are not installed)
  OpenCode v1   /<skill>              requires a command shim in ~/.config/opencode/commands/
  OpenCode v2   /<skill>              native skill slash catalog; shims are intentionally absent

Resolved OpenCode edition: $opencode_version (override with SKILL_X_OPENCODE_VERSION=v1|v2)
EOF

printf '\n%s\n' "$OPENCODE_COMMANDS"
if [[ "$opencode_version" == v2 ]]; then
  stale=0
  if [[ -d "$OPENCODE_COMMANDS" ]]; then
    while IFS= read -r -d '' link; do
      [[ "$(readlink "$link")" == "$COMMAND_SOURCE"/* ]] || continue
      printf '  STALE   %s (remove with bin/sync-skills.sh)\n' "$(basename "$link")"
      stale=1
    done < <(find "$OPENCODE_COMMANDS" -mindepth 1 -maxdepth 1 -type l -print0 | sort -z)
  fi
  (( stale )) || echo '  N/A     OpenCode v2 lists skills natively; no shims expected'
elif [[ ! -d "$COMMAND_SOURCE" ]]; then
  echo '  MISSING opencode-commands/ not built; run bin/build.sh'
else
  while IFS= read -r -d '' command_file; do
    name=$(basename "$command_file")
    installed="$OPENCODE_COMMANDS/$name"
    if [[ -L "$installed" && "$(readlink "$installed")" == "$command_file" ]]; then
      printf '  OK      /%s -> %s\n' "${name%.md}" "$(readlink "$installed")"
    elif [[ -f "$installed" ]] && grep -q "$MANAGED_MARKER" "$installed" 2>/dev/null; then
      printf '  COPY    /%s\n' "${name%.md}"
    elif [[ -e "$installed" ]]; then
      printf '  FOREIGN /%s (not managed by skill-x; left untouched)\n' "${name%.md}"
    else
      printf '  MISSING /%s (run bin/sync-skills.sh)\n' "${name%.md}"
    fi
  done < <(find "$COMMAND_SOURCE" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
fi

cat <<'EOF'

Manual smoke test (one per agent, after restarting it):
1. Claude Code: run /example-skill and confirm the skill body is loaded.
2. Codex: run $example-skill, then /skills, and confirm the skill is listed.
3. OpenCode: run /example-skill. On v1 the shim must load the canonical skill
   through the skill tool; on v2 the entry must appear exactly once.
Record which path each agent reports loading before simplifying either
defensive Codex path.
EOF
