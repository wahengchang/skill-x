#!/usr/bin/env bash
set -euo pipefail
targets=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills" "$HOME/.config/opencode/skills")
for target in "${targets[@]}"; do
  printf '\n%s\n' "$target"
  if [[ ! -d "$target" ]]; then echo "  MISSING"; continue; fi
  while IFS= read -r -d '' item; do
    if [[ -L "$item" ]]; then printf '  OK      %s -> %s\n' "$(basename "$item")" "$(readlink "$item")"
    else printf '  COPY    %s\n' "$(basename "$item")"; fi
  done < <(find "$target" -mindepth 1 -maxdepth 1 -print0 | sort -z)
done
opencode_version=$("$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/opencode-version.sh")
printf '\nExplicit invocation:\n'
printf '  Claude Code: /<skill-name> (native)\n'
printf '  Codex:       $<skill-name> or /skills (native)\n'
case "$opencode_version" in
  v1)
    printf '  OpenCode v1: /<skill-name> (generated command shim)\n'
    target="$HOME/.config/opencode/commands"
    if [[ ! -d "$target" ]]; then
      printf '    MISSING %s\n' "$target"
    else
      while IFS= read -r -d '' item; do
        if [[ -L "$item" ]]; then printf '    OK      %s -> %s\n' "$(basename "$item" .md)" "$(readlink "$item")"
        else printf '    COPY    %s\n' "$(basename "$item" .md)"; fi
      done < <(find "$target" -mindepth 1 -maxdepth 1 -name '*.md' -print0 | sort -z)
    fi ;;
  v2) printf '  OpenCode v2: /<skill-name> (native; no generated shims)\n' ;;
  unknown) printf '  OpenCode:    UNKNOWN (set SKILL_X_OPENCODE_VERSION=v1 or v2)\n' ;;
esac
cat <<'EOF'

Codex verification:
1. Restart Codex after synchronization.
2. Ask Codex to use example-skill in a directory outside this repository.
3. If it is discovered, record which path Codex reports loading.
Official documentation should be checked again before removing either defensive path.
EOF
