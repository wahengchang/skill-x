#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/commands"
COMMAND_SOURCE="$ROOT/opencode-commands"
OPENCODE_COMMANDS="$HOME/.config/opencode/commands"
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

# Claude Code and Codex expose synced skills through their own command UI
# (/<skill> and $<skill>). OpenCode v1 needs an explicit command file, while
# OpenCode v2 lists skills natively and must not receive duplicates.
opencode_version=$("$ROOT/bin/opencode-version.sh")

remove_managed_command_links() {
  local dir=$1 keep_live=$2
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' link; do
    linked_target=$(readlink "$link")
    [[ "$linked_target" == "$COMMAND_SOURCE"/* ]] || continue
    if [[ "$keep_live" == keep-live && -f "$linked_target" ]]; then
      continue
    fi
    rm "$link"
    echo "Removed OpenCode command link: $link" >&2
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0)
}

if [[ "$opencode_version" == v1 ]]; then
  [[ -d "$COMMAND_SOURCE" ]] || { echo "Run bin/build.sh first." >&2; exit 1; }
  mkdir -p "$OPENCODE_COMMANDS"
  while IFS= read -r -d '' command_file; do
    name=$(basename "$command_file")
    link="$OPENCODE_COMMANDS/$name"
    if [[ -L "$link" ]]; then
      ln -sfn "$command_file" "$link"
    elif [[ -e "$link" ]]; then
      echo "WARNING: skipping non-symlink path: $link" >&2
    else
      ln -s "$command_file" "$link"
    fi
  done < <(find "$COMMAND_SOURCE" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
  remove_managed_command_links "$OPENCODE_COMMANDS" keep-live
  echo "Skills synchronized (OpenCode v1 command shims installed)."
else
  remove_managed_command_links "$OPENCODE_COMMANDS" remove-all
  echo "Skills synchronized (OpenCode v2 exposes skills natively; no command shims installed)."
fi
