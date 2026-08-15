#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/commands"
TARGETS_CONF="$ROOT/bin/targets/targets.conf"
TARGETS_DIR="$ROOT/bin/targets"

[[ -f "$TARGETS_CONF" ]] || { echo "Missing target registry: $TARGETS_CONF" >&2; exit 1; }
[[ -d "$SOURCE" ]] || { echo "Run bin/build.sh first." >&2; exit 1; }

# shellcheck source=bin/targets/targets.conf
source "$TARGETS_CONF"

canonical_sync() {
  for entry in "${CANONICAL_CONSUMERS[@]}"; do
    consumer=${entry%%:*}
    target=${entry##*:}
    target=${target/#~/$HOME}

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

    while IFS= read -r -d '' link; do
      linked_target=$(readlink "$link")
      if [[ "$linked_target" == "$SOURCE"/* && ! -d "$linked_target" ]]; then
        rm "$link"
        echo "Removed stale link: $link" >&2
      fi
    done < <(find "$target" -mindepth 1 -maxdepth 1 -type l -print0)
  done
}

transform_sync() {
  for entry in "${TRANSFORMED_TARGETS[@]}"; do
    adapter=${entry%%:*}
    artifact=${entry##*:}
    script="$TARGETS_DIR/${adapter}.sh"
    artifact_dir="$ROOT/$artifact"

    if [[ -f "$script" ]]; then
      echo "Syncing transformed target: $adapter"
      "$script" sync "$artifact_dir"
    fi
  done
}

canonical_sync
transform_sync

echo "Skills synchronized."
