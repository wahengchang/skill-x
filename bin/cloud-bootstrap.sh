#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 <repo-url> <pinned-ref>" >&2; exit 2; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
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
[[ -d "$tmp/repo/commands" ]] || { echo "Pinned ref has no commands directory." >&2; exit 1; }

targets=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills" "$HOME/.config/opencode/skills")
for target in "${targets[@]}"; do
  mkdir -p "$target"
  cp -a "$tmp/repo/commands/." "$target/"
done
echo "Installed pinned skills from $ref."

opencode_version=$("$ROOT/bin/opencode-version.sh")
command_source="$tmp/repo/opencode-commands"
if [[ "$opencode_version" == v1 && -d "$command_source" ]]; then
  commands_target="$HOME/.config/opencode/commands"
  mkdir -p "$commands_target"
  while IFS= read -r -d '' command_file; do
    name=$(basename "$command_file")
    dest="$commands_target/$name"
    if [[ -e "$dest" ]] && ! grep -q "$MANAGED_MARKER" "$dest" 2>/dev/null; then
      echo "WARNING: skipping existing non-managed command: $dest" >&2
      continue
    fi
    cp -a "$command_file" "$dest"
  done < <(find "$command_source" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
  echo "Installed pinned OpenCode v1 command shims."
elif [[ "$opencode_version" == v2 ]]; then
  echo "OpenCode v2 detected; relying on its native skill slash commands."
fi
