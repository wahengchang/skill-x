#!/usr/bin/env bash
set -euo pipefail

requested=${SKILL_X_OPENCODE_VERSION:-auto}
case "$requested" in
  v1|v2) printf '%s\n' "$requested"; exit ;;
  auto) ;;
  *) echo "Invalid SKILL_X_OPENCODE_VERSION: $requested (expected auto, v1, or v2)" >&2; exit 2 ;;
esac

if command -v opencode >/dev/null 2>&1; then
  version=$(opencode --version 2>/dev/null || true)
  if [[ "$version" =~ ([0-9]+) ]]; then
    if (( 10#${BASH_REMATCH[1]} >= 2 )); then
      echo v2
    else
      echo v1
    fi
    exit
  fi
fi
echo unknown
