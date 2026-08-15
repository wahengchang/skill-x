#!/usr/bin/env bash
# Adapter for OpenCode v1's commands/ directory.
#
# OpenCode v1 does not auto-load ~/.config/opencode/skills/<name>/SKILL.md
# as a slash command; it expects a thin command file at
# ~/.config/opencode/commands/<name>.md and forwards $ARGUMENTS to its
# body. The body must point at the canonical skill so the SKILL.md stays
# the single source of truth. OpenCode v2 exposes skills natively, so this
# adapter removes only skill-x-managed shims and preserves user-owned commands.
#
# Actions:
#   build   $1=canonical staging root  $2=staging artifact directory
#           Generates <name>.md shim files from fully processed canonical skills.
#   sync    $1=artifact directory
#           Symlinks generated shims into user's OpenCode commands dir.
#   bootstrap $1=artifact directory
#           Copies generated shims into pinned image; preserves user files.
set -euo pipefail

MANAGED_MARKER="skill-x-managed-command"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
# shellcheck source=bin/lib/common.sh
. "$REPO_ROOT/bin/lib/common.sh"
OPENCODE_VERSION=$("$REPO_ROOT/bin/opencode-version.sh")
OPENCODE_COMMANDS="$HOME/.config/opencode/commands"

manifest_owns_symlink() {
  local dest=$1 linked manifest agent kind path target
  [[ -L "$dest" ]] || return 1
  linked=$(readlink "$dest")
  while IFS= read -r manifest; do
    while IFS=$'\t' read -r agent kind path target; do
      if [[ "$kind" == symlink && "$path" == "$dest" && "$target" == "$linked" ]]; then
        return 0
      fi
    done < <(sx_manifest_entries "$manifest")
  done < <(sx_all_manifests)
  return 1
}

write_opencode_command() {
  local name=$1 description=$2 out=$3
  local quoted=${description//\'/\'\'}
  cat > "$out" <<EOF
---
description: '$quoted'
---

<!-- $MANAGED_MARKER: $name -->
<!-- 由 bin/build.sh 產生，請改 commands-src/$name/SKILL.md 後重新 build。 -->

Use the \`skill\` tool to load the \`$name\` skill, then follow its instructions exactly.
The skill itself is the single source of truth; do not act on any summary of it.

Arguments from the user: \$ARGUMENTS

If those arguments are empty, ask the user what they want the skill to work on before continuing.
EOF
}

remove_managed_shims() {
  local artifact_dir=$1 dir=$2 mode=$3 file linked_target
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' file; do
    if [[ -L "$file" ]]; then
      manifest_owns_symlink "$file" || continue
      linked_target=$(readlink "$file")
      if [[ "$mode" == keep-live && -f "$linked_target" ]]; then
        continue
      fi
      rm "$file"
      echo "Removed OpenCode command shim: $file" >&2
    elif [[ -f "$file" ]]; then
      if ! grep -q "$MANAGED_MARKER" "$file" 2>/dev/null; then
        continue
      fi
      rm "$file"
      echo "Removed OpenCode command shim: $file" >&2
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 \( -type l -o -type f \) -print0)
}

action=${1:-build}

case "$action" in
  build)
    src=$2
    dest=$3
    mkdir -p "$dest"

    while IFS= read -r -d '' skill; do
      rel=${skill#"$src/"}
      name=${rel%/SKILL.md}

      description=$(awk '
        { sub(/\r$/, "") }
        NR == 1 { next }
        $0 == "---" { exit }
        /^description:[[:space:]]*/ {
          sub(/^description:[[:space:]]*/, "")
          sub(/^"/, ""); sub(/"$/, "")
          sub(/^'"'"'/, ""); sub(/'"'"'$/, "")
          print
          exit
        }
      ' "$skill")
      [[ -n "$description" ]] || description="Run the $name skill."

      write_opencode_command "$name" "$description" "$dest/$name.md"
    done < <(find "$src" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 | sort -z)
    ;;

  sync)
    artifact_dir=$2

    if [[ "$OPENCODE_VERSION" != v1 ]]; then
      remove_managed_shims "$artifact_dir" "$OPENCODE_COMMANDS" remove-all
      exit 0
    fi

    mkdir -p "$OPENCODE_COMMANDS"
    while IFS= read -r -d '' command_file; do
      name=$(basename "$command_file")
      link="$OPENCODE_COMMANDS/$name"
      if [[ -L "$link" ]]; then
        if manifest_owns_symlink "$link"; then
          ln -sfn "$command_file" "$link"
        else
          echo "WARNING: preserving foreign command symlink: $link -> $(readlink "$link")" >&2
        fi
      elif [[ -e "$link" ]]; then
        if grep -q "$MANAGED_MARKER" "$link" 2>/dev/null; then
          rm "$link"
          ln -s "$command_file" "$link"
        else
          echo "WARNING: skipping non-symlink path: $link" >&2
        fi
      else
        ln -s "$command_file" "$link"
      fi
    done < <(find "$artifact_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

    remove_managed_shims "$artifact_dir" "$OPENCODE_COMMANDS" keep-live
    ;;

  bootstrap)
    artifact_dir=$2

    if [[ "$OPENCODE_VERSION" != v1 ]]; then
      remove_managed_shims "$artifact_dir" "$OPENCODE_COMMANDS" remove-all
      exit 0
    fi

    mkdir -p "$OPENCODE_COMMANDS"
    while IFS= read -r -d '' command_file; do
      name=$(basename "$command_file")
      dest="$OPENCODE_COMMANDS/$name"
      if [[ -e "$dest" || -L "$dest" ]]; then
        if [[ -L "$dest" ]]; then
          if manifest_owns_symlink "$dest"; then
            rm "$dest"
          else
            echo "WARNING: skipping existing non-managed command: $dest" >&2
            continue
          fi
        elif grep -q "$MANAGED_MARKER" "$dest" 2>/dev/null; then
          rm "$dest"
        else
          echo "WARNING: skipping existing non-managed command: $dest" >&2
          continue
        fi
      fi
      cp -a "$command_file" "$dest"
    done < <(find "$artifact_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
    ;;

  *)
    echo "Unknown action: $action" >&2
    exit 1
    ;;
esac
