#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
git -C "$ROOT" pull --ff-only
"$ROOT/bin/sync-skills.sh"
rm -f "${SKILL_X_STATE_DIR:-$HOME/.skill-x-starter-state}/last-check" \
      "${SKILL_X_STATE_DIR:-$HOME/.skill-x-starter-state}/snooze-until"

