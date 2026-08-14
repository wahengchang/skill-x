#!/usr/bin/env bash
# Resolve which OpenCode generation the local machine should be treated as.
# Prints exactly "v1" or "v2" on stdout; explanations go to stderr.
#
# v1 needs generated command shims for /<skill>; v2 exposes skills as slash
# commands natively, so shims there would only create duplicate entries.
set -euo pipefail

requested=${SKILL_X_OPENCODE_VERSION:-auto}
case "$requested" in
  v1|1) echo v1; exit 0 ;;
  v2|2) echo v2; exit 0 ;;
  auto) ;;
  *)
    echo "Unknown SKILL_X_OPENCODE_VERSION: $requested (expected auto, v1, or v2)" >&2
    exit 2
    ;;
esac

raw=""
if command -v opencode >/dev/null 2>&1; then
  raw=$(opencode --version 2>/dev/null | head -n 1 || true)
fi

version=$(printf '%s\n' "$raw" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1 || true)
major=${version%%.*}

if [[ -z "$major" ]]; then
  echo "Could not detect the OpenCode version; assuming v1. Set SKILL_X_OPENCODE_VERSION=v1 or v2 to decide explicitly." >&2
  echo v1
elif (( major >= 2 )); then
  echo v2
else
  echo v1
fi
