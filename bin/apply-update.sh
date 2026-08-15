#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
git -C "$ROOT" pull --ff-only
# Generated outputs are disposable build artifacts; rebuild the new HEAD
# before syncing so consumers never observe a stale or absent tree.
"$ROOT/bin/build.sh"
"$ROOT/bin/sync-skills.sh"
rm -f "${SKILL_X_STATE_DIR:-$HOME/.skill-x-starter-state}/last-check" \
      "${SKILL_X_STATE_DIR:-$HOME/.skill-x-starter-state}/snooze-until"

