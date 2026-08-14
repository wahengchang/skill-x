#!/usr/bin/env bash
set -euo pipefail
STATE_DIR=${SKILL_X_STATE_DIR:-"$HOME/.skill-x-starter-state"}
DAYS=${SKILL_X_SNOOZE_DAYS:-7}
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "SKILL_X_SNOOZE_DAYS must be a non-negative integer" >&2; exit 1; }
mkdir -p "$STATE_DIR"
printf '%s\n' "$(( $(date +%s) + DAYS * 86400 ))" > "$STATE_DIR/snooze-until"
echo "Update reminder snoozed for $DAYS days."

