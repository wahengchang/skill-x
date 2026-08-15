#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/commands-src"
HEADER="$ROOT/_shared/update-check-header.md"
TARGETS_DIR="$ROOT/bin/targets"
TARGETS_CONF="$TARGETS_DIR/targets.conf"

[[ -f "$HEADER" ]] || { echo "Missing header: $HEADER" >&2; exit 1; }
[[ -f "$TARGETS_CONF" ]] || { echo "Missing target registry: $TARGETS_CONF" >&2; exit 1; }

# shellcheck source=targets/targets.conf
source "$TARGETS_CONF"

# Verify that every adapter script on disk is declared in
# TRANSFORMED_TARGETS, and that every declared adapter exists on disk.
# Catches drift between bin/targets/*.sh and the registry before any
# files are written.
declared_adapters=()
for entry in "${TRANSFORMED_TARGETS[@]}"; do
  declared_adapters+=("${entry%%:*}")
done
for script in "$TARGETS_DIR"/*.sh; do
  [[ -f "$script" ]] || continue
  stem=$(basename "$script" .sh)
  found=0
  for adapter in "${declared_adapters[@]}"; do
    [[ "$adapter" == "$stem" ]] && { found=1; break; }
  done
  (( found )) || {
    echo "Undeclared adapter script: bin/targets/${stem}.sh (add it to bin/targets/targets.conf)" >&2
    exit 1
  }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Stage every artifact under $tmp. The final swap is a pure directory mv,
# so downstream consumers never observe a half-built tree. We keep two
# parallel arrays (adapter -> artifact) instead of an associative array
# so the script stays portable with bash 3.2.
canonical_tmp="$tmp/$CANONICAL_DEST"
mkdir -p "$canonical_tmp"

staged_paths=()
final_paths=()
staged_paths+=("$canonical_tmp"); final_paths+=("$ROOT/$CANONICAL_DEST")
for entry in "${TRANSFORMED_TARGETS[@]}"; do
  artifact=${entry##*:}
  staged="$tmp/$artifact"
  mkdir -p "$staged"
  staged_paths+=("$staged"); final_paths+=("$ROOT/$artifact")
done

build_canonical_skills() {
  local found=0
  while IFS= read -r -d '' skill; do
    found=1
    rel=${skill#"$SRC/"}
    name=${rel%/SKILL.md}
    out="$canonical_tmp/$name/SKILL.md"
    mkdir -p "$(dirname "$out")"
    awk -v header="$HEADER" '
      { sub(/\r$/, "") }
      NR == 1 && $0 != "---" { exit 42 }
      { print }
      NR > 1 && $0 == "---" && !done {
        print ""
        while ((getline line < header) > 0) { sub(/\r$/, "", line); print line }
        close(header)
        done=1
        next
      }
      END { if (!done) exit 43 }
    ' "$skill" > "$out" || {
      status=$?
      echo "Invalid frontmatter in ${rel}: expected opening and closing ---" >&2
      exit "$status"
    }

    skill_dir=$(dirname "$skill")
    out_dir=$(dirname "$out")
    # Follow shared support-file symlinks so each generated skill is a
    # self-contained artifact even when canonical sources share assets.
    while IFS= read -r -d '' support; do
      support_rel=${support#"$skill_dir/"}
      mkdir -p "$out_dir/$(dirname "$support_rel")"
      cp -aL "$support" "$out_dir/$support_rel"
    done < <(find -L "$skill_dir" -type f ! -name SKILL.md -print0)
  done < <(find "$SRC" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 | sort -z)

  (( found )) || { echo "No skills found in $SRC" >&2; exit 1; }
}

build_canonical_skills

idx=0
for entry in "${TRANSFORMED_TARGETS[@]}"; do
  adapter=${entry%%:*}
  artifact=${entry##*:}
  script="$TARGETS_DIR/${adapter}.sh"
  echo "Building transformed target: $adapter -> ${artifact}/"
  # Transform adapters consume the fully processed canonical staging tree,
  # not raw commands-src/. That keeps shared header injection and support-file
  # materialization centralized in the common build path.
  "$script" build "$canonical_tmp" "${staged_paths[$((idx + 1))]}" || {
    echo "Target $adapter failed" >&2
    exit 1
  }
  idx=$((idx + 1))
done

# Each fully staged tree is moved into its final, gitignored location in one
# shot, so consumers never see a half-written artifact directory.
swap_tree() {
  local staged=$1 final=$2 label=$3
  rm -rf "$final"
  mv "$staged" "$final"
  echo "Built ${label} in $final"
}

for i in "${!staged_paths[@]}"; do
  label=$(basename "${final_paths[$i]}")
  swap_tree "${staged_paths[$i]}" "${final_paths[$i]}" "$label"
done
