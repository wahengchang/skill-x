#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/commands-src"
DEST="$ROOT/commands"
COMMAND_DEST="$ROOT/opencode-commands"
HEADER="$ROOT/_shared/update-check-header.md"
MANAGED_MARKER="skill-x-managed-command"

[[ -f "$HEADER" ]] || { echo "Missing header: $HEADER" >&2; exit 1; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/commands" "$tmp/opencode-commands"

# The shim is deliberately thin: it points OpenCode v1 at the canonical skill
# instead of restating it, so commands-src/ stays the single source of truth.
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

found=0
while IFS= read -r -d '' skill; do
  found=1
  rel=${skill#"$SRC/"}
  name=${rel%/SKILL.md}
  out="$tmp/commands/$name/SKILL.md"
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
  write_opencode_command "$name" "$description" "$tmp/opencode-commands/$name.md"

  skill_dir=$(dirname "$skill")
  out_dir=$(dirname "$out")
  while IFS= read -r -d '' support; do
    support_rel=${support#"$skill_dir/"}
    mkdir -p "$out_dir/$(dirname "$support_rel")"
    cp -a "$support" "$out_dir/$support_rel"
  done < <(find "$skill_dir" -type f ! -name SKILL.md -print0)
done < <(find "$SRC" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 | sort -z)

(( found )) || { echo "No skills found in $SRC" >&2; exit 1; }
rm -rf "$DEST" "$COMMAND_DEST"
mv "$tmp/commands" "$DEST"
mv "$tmp/opencode-commands" "$COMMAND_DEST"
echo "Built skills in $DEST"
echo "Built OpenCode v1 command shims in $COMMAND_DEST"
