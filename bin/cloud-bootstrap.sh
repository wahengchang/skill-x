#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 <repo-url> <pinned-ref>" >&2; exit 2; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"
repo_url=$1
ref=$2
MANAGED_MARKER="skill-x-managed-command"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-cloud.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Authentication is deliberately owned by the image builder (SSH agent or secret),
# never accepted or persisted by this script.
git clone --quiet --no-checkout "$repo_url" "$tmp/repo"
git -C "$tmp/repo" fetch --quiet --depth 1 origin "$ref"
git -C "$tmp/repo" checkout --quiet --detach FETCH_HEAD

# Return success only when this exact symlink is still one recorded by a
# lifecycle manifest in this HOME. A matching destination name or a target that
# happens to live under a skill-x checkout is not enough to claim ownership.
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

# A reused HOME or image layer can still hold symlinks from an interactive
# installation. Only unlink links whose current target is still manifest-owned;
# foreign/user-owned symlinks are preserved rather than copied through.
prepare_pinned_destination() {
  local dest=$1
  [[ -L "$dest" ]] || return 0
  if manifest_owns_symlink "$dest"; then
    rm "$dest"
    echo "Replaced managed symlink with a pinned copy: $dest" >&2
    return 0
  fi
  echo "WARNING: preserving foreign symlink: $dest -> $(readlink "$dest")" >&2
  return 1
}

# Generated artifacts are disposable on current refs. Historical refs may still
# contain/build the legacy commands/ + opencode-commands/ layout; their own
# build.sh remains the authority for recreating that pinned version.
"$tmp/repo/bin/build.sh"

remove_legacy_managed_shims() {
  local dir=$1
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' file; do
    if [[ -L "$file" ]]; then
      manifest_owns_symlink "$file" || continue
      rm "$file"
      echo "Removed OpenCode command shim: $file" >&2
    elif [[ -f "$file" ]] && grep -q "$MANAGED_MARKER" "$file" 2>/dev/null; then
      rm "$file"
      echo "Removed OpenCode command shim: $file" >&2
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 \( -type l -o -type f \) -print0)
}

legacy_deploy() {
  local canonical="$tmp/repo/commands"
  local command_source="$tmp/repo/opencode-commands"
  local opencode_commands="$HOME/.config/opencode/commands"
  local opencode_version
  local targets=(
    "$HOME/.claude/skills"
    "$HOME/.codex/skills"
    "$HOME/.agents/skills"
    "$HOME/.config/opencode/skills"
  )

  [[ -d "$canonical" ]] || { echo "Legacy pinned ref produced no commands directory." >&2; exit 1; }

  local target skill dest
  for target in "${targets[@]}"; do
    mkdir -p "$target"
    while IFS= read -r -d '' skill; do
      dest="$target/$(basename "$skill")"
      prepare_pinned_destination "$dest" || continue
      cp -a "$skill" "$target/"
    done < <(find "$canonical" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  done

  opencode_version=$("$ROOT/bin/opencode-version.sh")
  if [[ "$opencode_version" == v1 && -d "$command_source" ]]; then
    mkdir -p "$opencode_commands"
    local command_file name
    while IFS= read -r -d '' command_file; do
      name=$(basename "$command_file")
      dest="$opencode_commands/$name"
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
    done < <(find "$command_source" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
  elif [[ "$opencode_version" == v2 ]]; then
    remove_legacy_managed_shims "$opencode_commands"
  fi

  echo "Installed pinned skills from $ref (legacy target layout)."
}

TARGETS_CONF="$tmp/repo/bin/targets/targets.conf"
if [[ ! -f "$TARGETS_CONF" ]]; then
  legacy_deploy
  exit 0
fi

# shellcheck source=bin/targets/targets.conf
source "$TARGETS_CONF"
[[ -d "$tmp/repo/$CANONICAL_DEST" ]] || { echo "Build produced no $CANONICAL_DEST directory." >&2; exit 1; }

TARGETS_DIR="$tmp/repo/bin/targets"

canonical_deploy() {
  local entry rel target skill dest
  for entry in "${CANONICAL_CONSUMERS[@]}"; do
    rel=${entry##*:}
    rel=${rel/#~/$HOME}
    target="$rel"
    mkdir -p "$target"
    while IFS= read -r -d '' skill; do
      dest="$target/$(basename "$skill")"
      prepare_pinned_destination "$dest" || continue
      cp -a "$skill" "$target/"
    done < <(find "$tmp/repo/$CANONICAL_DEST" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  done
}

transform_bootstrap() {
  local entry adapter artifact script artifact_dir
  for entry in "${TRANSFORMED_TARGETS[@]}"; do
    adapter=${entry%%:*}
    artifact=${entry##*:}
    script="$TARGETS_DIR/${adapter}.sh"
    artifact_dir="$tmp/repo/$artifact"

    if [[ -f "$script" && -d "$artifact_dir" ]]; then
      echo "Bootstrapping transformed target: $adapter"
      "$script" bootstrap "$artifact_dir"
    fi
  done
}

canonical_deploy
transform_bootstrap

echo "Installed pinned skills from $ref."
