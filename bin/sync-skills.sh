#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/commands"
TARGETS=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills" "$HOME/.config/opencode/skills")
[[ -d "$SOURCE" ]] || { echo "Run bin/build.sh first." >&2; exit 1; }

for target in "${TARGETS[@]}"; do
  mkdir -p "$target"
  while IFS= read -r -d '' skill; do
    name=$(basename "$skill")
    link="$target/$name"
    if [[ -L "$link" ]]; then
      ln -sfn "$skill" "$link"
    elif [[ -e "$link" ]]; then
      echo "WARNING: skipping non-symlink path: $link" >&2
    else
      ln -s "$skill" "$link"
    fi
  done < <(find "$SOURCE" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

  # Remove links we manage that now point at a skill removed from commands/.
  while IFS= read -r -d '' link; do
    linked_target=$(readlink "$link")
    if [[ "$linked_target" == "$SOURCE"/* && ! -d "$linked_target" ]]; then
      rm "$link"
      echo "Removed stale link: $link" >&2
    fi
  done < <(find "$target" -mindepth 1 -maxdepth 1 -type l -print0)
done
echo "Skills synchronized."

