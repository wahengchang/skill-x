#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/commands-src"
DEST="$ROOT/skills"
MODE="build"

case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  *)
    echo "Usage: bin/build-registry.sh [--check]" >&2
    exit 2
    ;;
esac

[[ -d "$SRC" ]] || { echo "Missing source directory: $SRC" >&2; exit 1; }
[[ ! -L "$DEST" ]] || { echo "Refusing symlink destination: $DEST" >&2; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/skills-registry.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
staged="$tmp/skills"
mkdir -p "$staged"

found=0
while IFS= read -r -d '' source_file; do
  found=1
  skill_dir=$(dirname "$source_file")
  folder_name=$(basename "$skill_dir")
  output_dir="$staged/$folder_name"
  output_file="$output_dir/SKILL.md"

  frontmatter_end=$(awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$source_file")
  [[ -n "$frontmatter_end" ]] || {
    echo "Invalid frontmatter: ${source_file#$ROOT/}" >&2
    exit 1
  }

  declared_name=$(sed -n "2,${frontmatter_end}p" "$source_file" |
    sed -n 's/^name:[[:space:]]*//p' | head -n 1)
  description=$(sed -n "2,${frontmatter_end}p" "$source_file" |
    sed -n 's/^description:[[:space:]]*//p' | head -n 1)

  [[ "$declared_name" == "$folder_name" ]] || {
    echo "Skill name mismatch: folder=$folder_name frontmatter=$declared_name" >&2
    exit 1
  }
  [[ -n "$description" ]] || {
    echo "Missing description: ${source_file#$ROOT/}" >&2
    exit 1
  }

  mkdir -p "$output_dir"
  awk '
    { sub(/\r$/, "") }
    /^## Provenance[[:space:]]*$/ { skipping = 1; next }
    skipping && /^## / { skipping = 0 }
    skipping { next }
    { print }
  ' "$source_file" > "$output_file"

  while IFS= read -r -d '' support_file; do
    relative=${support_file#"$skill_dir/"}
    mkdir -p "$output_dir/$(dirname "$relative")"
    cp -aL "$support_file" "$output_dir/$relative"
  done < <(find -L "$skill_dir" -type f ! -name SKILL.md -print0)
done < <(find "$SRC" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 | sort -z)

(( found )) || { echo "No skills found in $SRC" >&2; exit 1; }

if [[ "$MODE" == "check" ]]; then
  [[ -d "$DEST" ]] || {
    echo "Missing published skills/. Run bin/build-registry.sh." >&2
    exit 1
  }
  if ! diff -qr "$DEST" "$staged" >/dev/null; then
    echo "Published skills/ is stale. Run bin/build-registry.sh and commit the result." >&2
    diff -ruN "$DEST" "$staged" || true
    exit 1
  fi
  echo "Published skills/ matches commands-src/."
  exit 0
fi

rm -rf "$DEST"
mv "$staged" "$DEST"
echo "Built npx-skills distribution in $DEST"

