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
cat <<'EOF'

Codex verification:
1. Restart Codex after synchronization.
2. Ask Codex to use example-skill in a directory outside this repository.
3. If it is discovered, record which path Codex reports loading.
Official documentation should be checked again before removing either defensive path.
EOF

