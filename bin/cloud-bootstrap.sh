#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 <repo-url> <pinned-ref>" >&2; exit 2; }
repo_url=$1
ref=$2

tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-cloud.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Authentication is deliberately owned by the image builder (SSH agent or secret),
# never accepted or persisted by this script.
git clone --quiet --no-checkout "$repo_url" "$tmp/repo"
git -C "$tmp/repo" fetch --quiet --depth 1 origin "$ref"
git -C "$tmp/repo" checkout --quiet --detach FETCH_HEAD

# Generated artifacts are disposable: build them from the pinned source
# tree before copying anything to the image, so the pinned ref only has
# to carry canonical source plus build inputs.
"$tmp/repo/bin/build.sh"

# shellcheck source=bin/targets/targets.conf
source "$tmp/repo/bin/targets/targets.conf"
[[ -d "$tmp/repo/$CANONICAL_DEST" ]] || { echo "Build produced no $CANONICAL_DEST directory." >&2; exit 1; }

TARGETS_DIR="$tmp/repo/bin/targets"

canonical_deploy() {
  for entry in "${CANONICAL_CONSUMERS[@]}"; do
    rel=${entry##*:}
    rel=${rel/#~/$HOME}
    target="$rel"
    mkdir -p "$target"
    cp -a "$tmp/repo/$CANONICAL_DEST/." "$target/"
  done
}

transform_bootstrap() {
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
