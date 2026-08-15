#!/usr/bin/env bash
set -euo pipefail

if (( $# < 2 )); then
  echo "usage: $0 <suite-name> <command> [args ...]" >&2
  exit 2
fi

suite_name=$1
shift
timeout_seconds=${SKILL_X_SUITE_TIMEOUT_SECONDS:-3600}

case "$timeout_seconds" in
  ''|*[!0-9]*)
    echo "SKILL_X_SUITE_TIMEOUT_SECONDS must be a positive integer" >&2
    exit 2
    ;;
esac
if (( timeout_seconds < 1 )); then
  echo "SKILL_X_SUITE_TIMEOUT_SECONDS must be at least 1" >&2
  exit 2
fi

marker=$(mktemp "${TMPDIR:-/tmp}/skill-x-suite-timeout.XXXXXX")
rm -f "$marker"
watchdog_pid=''
cleanup() {
  if [[ -n "$watchdog_pid" ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
  fi
  rm -f "$marker"
}
trap cleanup EXIT

started=$SECONDS
printf 'SUITE %s (timeout %ss)\n' "$suite_name" "$timeout_seconds"

set +e
# Bash monitor mode gives the child command its own process group. That lets the
# watchdog terminate a stalled command and its descendants instead of only the
# top-level shell process.
set -m
("$@") &
command_pid=$!
set +m

(
  sleep "$timeout_seconds"
  if kill -0 "$command_pid" 2>/dev/null; then
    : > "$marker"
    kill -TERM -- "-$command_pid" 2>/dev/null || kill -TERM "$command_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$command_pid" 2>/dev/null || kill -KILL "$command_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

wait "$command_pid"
status=$?
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=''
set -e

elapsed=$((SECONDS - started))
if [[ -e "$marker" ]]; then
  printf 'SUITE %s: TIMEOUT after %ss (limit %ss)\n' "$suite_name" "$elapsed" "$timeout_seconds" >&2
  exit 124
fi
if (( status != 0 )); then
  printf 'SUITE %s: FAIL (%ss, exit %d)\n' "$suite_name" "$elapsed" "$status" >&2
  exit "$status"
fi

printf 'SUITE %s: PASS (%ss)\n' "$suite_name" "$elapsed"
