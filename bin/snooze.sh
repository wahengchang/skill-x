#!/usr/bin/env bash
# Defer the invocation-time update reminder for this installation only.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"

STATE_DIR=$(sx_state_dir "$(sx_install_id "$ROOT")")
DAYS=${SKILL_X_SNOOZE_DAYS:-7}
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "SKILL_X_SNOOZE_DAYS must be a non-negative integer" >&2; exit 1; }
mkdir -p "$STATE_DIR"
printf '%s\n' "$(( $(date +%s) + DAYS * 86400 ))" > "$STATE_DIR/snooze-until"
echo "Update reminder snoozed for $DAYS days."
