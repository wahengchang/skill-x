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
[[ -d "$tmp/repo/commands" ]] || { echo "Pinned ref has no commands directory." >&2; exit 1; }

targets=("$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills" "$HOME/.config/opencode/skills")
for target in "${targets[@]}"; do
  mkdir -p "$target"
  cp -a "$tmp/repo/commands/." "$target/"
done
opencode_version=$("$tmp/repo/bin/opencode-version.sh")
if [[ "$opencode_version" == v1 ]]; then
  mkdir -p "$HOME/.config/opencode/commands"
  cp -a "$tmp/repo/opencode-commands/." "$HOME/.config/opencode/commands/"
elif [[ "$opencode_version" == unknown ]]; then
  echo "WARNING: OpenCode version unavailable; set SKILL_X_OPENCODE_VERSION=v1 or v2 to configure slash commands." >&2
fi
echo "Installed pinned skills from $ref."
