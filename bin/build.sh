#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/commands-src"
DEST="$ROOT/commands"
COMMAND_DEST="$ROOT/opencode-commands"
HEADER="$ROOT/_shared/update-check-header.md"

[[ -f "$HEADER" ]] || { echo "Missing header: $HEADER" >&2; exit 1; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

found=0
while IFS= read -r -d '' skill; do
  found=1
  rel=${skill#"$SRC/"}
  out="$tmp/commands/${rel%/SKILL.md}/SKILL.md"
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
  while IFS= read -r -d '' support; do
    support_rel=${support#"$skill_dir/"}
    mkdir -p "$out_dir/$(dirname "$support_rel")"
    cp -a "$support" "$out_dir/$support_rel"
  done < <(find "$skill_dir" -type f ! -name SKILL.md -print0)

  name=$(basename "$(dirname "$skill")")
  mkdir -p "$tmp/opencode-commands"
  cat > "$tmp/opencode-commands/$name.md" <<EOF
---
description: Run the $name skill
---

Use the \`skill\` tool to load the canonical \`$name\` skill, then follow its instructions for this request:

\$ARGUMENTS
EOF
done < <(find "$SRC" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 | sort -z)

(( found )) || { echo "No skills found in $SRC" >&2; exit 1; }
rm -rf "$DEST"
mv "$tmp/commands" "$DEST"
rm -rf "$COMMAND_DEST"
mv "$tmp/opencode-commands" "$COMMAND_DEST"
trap - EXIT
echo "Built skills in $DEST and OpenCode v1 shims in $COMMAND_DEST"
