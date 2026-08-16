#!/usr/bin/env bash
# Shared test harness for every suite under tests/.
#
# Responsibilities:
#   - suite selection (fast subset vs. full regression run)
#   - per-test timing plus a slowest-cases summary
#   - a bounded timeout so a deadlock or a stuck worktree cannot burn an
#     unbounded amount of developer time
#   - project fixtures that are built once and copied per test, so tests stay
#     isolated without paying for a fresh `cp -a` of .git plus a rebuild each
#     time
#
# Callers must define PROJECT_ROOT and TEST_ROOT before sourcing this file, and
# call skill_x_test_finish at the end of the suite.
#
# shellcheck shell=bash

: "${PROJECT_ROOT:?harness requires PROJECT_ROOT}"
: "${TEST_ROOT:?harness requires TEST_ROOT}"

# fast: only tests registered with --fast. full: everything.
SKILL_X_TEST_SUITE=${SKILL_X_TEST_SUITE:-full}
# Seconds a single test may run before it is terminated as a failure.
SKILL_X_TEST_TIMEOUT=${SKILL_X_TEST_TIMEOUT:-240}

passed=0
failed=0
skipped=0
timed_out=0

_skill_x_test_index=0
_skill_x_test_timings=()

_skill_x_validate_timeout() {
  [[ $SKILL_X_TEST_TIMEOUT =~ ^[1-9][0-9]*$ ]] || {
    echo "SKILL_X_TEST_TIMEOUT must be a whole number of seconds, got: $SKILL_X_TEST_TIMEOUT" >&2
    exit 2
  }
}
_skill_x_validate_timeout

skill_x_test_parse_args() {
  while (( $# )); do
    case $1 in
      --fast) SKILL_X_TEST_SUITE=fast ;;
      --full) SKILL_X_TEST_SUITE=full ;;
      --timeout)
        shift
        [[ $# -gt 0 ]] || { echo 'missing value for --timeout' >&2; exit 2; }
        SKILL_X_TEST_TIMEOUT=$1
        ;;
      *)
        echo "unknown option: $1 (expected --fast, --full, or --timeout SECONDS)" >&2
        exit 2
        ;;
    esac
    shift
  done
  _skill_x_validate_timeout
}

# Milliseconds since the epoch. EPOCHREALTIME is bash 5+; older bashes (macOS
# ships 3.2) fall back to whole seconds rather than losing timing entirely.
skill_x_test_now_ms() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local seconds=${EPOCHREALTIME%%[.,]*}
    local fraction=${EPOCHREALTIME#*[.,]}
    fraction=${fraction}000
    printf '%s%s\n' "$seconds" "${fraction:0:3}"
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

skill_x_test_format_ms() {
  local ms=$1
  printf '%d.%02ds\n' "$((ms / 1000))" "$(((ms % 1000) / 10))"
}

_skill_x_suite_started=$(skill_x_test_now_ms)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A pristine, artifact-free copy of the repository. Built once per suite: the
# checkout's .git directory is the expensive part of `cp -a` and no test wants
# it, so copying the template is both faster and closer to what a fresh clone
# of the tracked inputs looks like.
skill_x_test_ensure_template() {
  [[ -n ${SKILL_X_TEST_TEMPLATE:-} ]] && return 0
  SKILL_X_TEST_TEMPLATE="$TEST_ROOT/.template"
  mkdir -p "$SKILL_X_TEST_TEMPLATE"
  cp -a "$PROJECT_ROOT/." "$SKILL_X_TEST_TEMPLATE/"
  rm -rf \
    "$SKILL_X_TEST_TEMPLATE/.git" \
    "$SKILL_X_TEST_TEMPLATE/commands" \
    "$SKILL_X_TEST_TEMPLATE/opencode-commands"
  # Agent-local state is not part of a fresh repository fixture.
  rm -rf "$SKILL_X_TEST_TEMPLATE/.claude"

  # `example-skill` and `funny-text-rewriter` used to be shipped sample skills.
  # Keep their stable names only as test fixtures so long-lived regression cases
  # can exercise build/sync/update behavior without depending on production
  # skills or forcing sample content back into commands-src/.
  mkdir -p \
    "$SKILL_X_TEST_TEMPLATE/commands-src/example-skill" \
    "$SKILL_X_TEST_TEMPLATE/commands-src/funny-text-rewriter"
  cat > "$SKILL_X_TEST_TEMPLATE/commands-src/example-skill/SKILL.md" <<'EOF'
---
name: example-skill
description: Test-only canonical skill fixture.
---

# Test fixture
EOF
  cat > "$SKILL_X_TEST_TEMPLATE/commands-src/funny-text-rewriter/SKILL.md" <<'EOF'
---
name: funny-text-rewriter
description: Test-only secondary skill fixture.
---

# Test fixture
EOF
}

# The same template with `bin/build.sh` already run once. Build outputs are
# deterministic and contain no absolute paths (support files are dereferenced
# copies), so a prebuilt tree relocates safely into each test's own directory.
skill_x_test_ensure_built_template() {
  [[ -n ${SKILL_X_TEST_BUILT_TEMPLATE:-} ]] && return 0
  skill_x_test_ensure_template
  local built="$TEST_ROOT/.template-built"
  mkdir -p "$built"
  cp -a "$SKILL_X_TEST_TEMPLATE/." "$built/"
  "$built/bin/build.sh" >/dev/null
  SKILL_X_TEST_BUILT_TEMPLATE=$built
}

# A fresh checkout of the tracked build inputs, without generated artifacts.
copy_project() {
  local destination=$1
  skill_x_test_ensure_template
  mkdir -p "$destination"
  cp -a "$SKILL_X_TEST_TEMPLATE/." "$destination/"
}

# Same as copy_project, plus the artifact trees a plain `bin/build.sh` would
# have produced. Only for tests that build unmodified sources; anything that
# edits commands-src/, _shared/, or bin/targets/ before building must use
# copy_project and run the build itself.
copy_built_project() {
  local destination=$1
  skill_x_test_ensure_built_template
  mkdir -p "$destination"
  cp -a "$SKILL_X_TEST_BUILT_TEMPLATE/." "$destination/"
}

# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

# run_test [--fast] <name> <command...>
#
# --fast marks the test as part of the routine subset; without it the test only
# runs in the full suite.
run_test() {
  local in_fast_suite=0
  if [[ ${1:-} == --fast ]]; then
    in_fast_suite=1
    shift
  fi
  local name=$1
  shift

  if [[ $SKILL_X_TEST_SUITE == fast && $in_fast_suite -eq 0 ]]; then
    skipped=$((skipped + 1))
    return 0
  fi

  printf 'TEST  %s ... ' "$name"

  _skill_x_test_index=$((_skill_x_test_index + 1))
  local marker="$TEST_ROOT/.timeout-marker.$_skill_x_test_index"
  local finished="$TEST_ROOT/.test-finished.$_skill_x_test_index"
  rm -f "$marker" "$finished"
  local start elapsed status=0
  start=$(skill_x_test_now_ms)

  ( set -euo pipefail; "$@" ) &
  local pid=$!

  # Watchdog: bounded wait, then terminate the test (and any direct children it
  # left behind) so a stalled case fails loudly instead of hanging the suite.
  # It retires by polling rather than by being signalled: a TERM would sit
  # unhandled until its own `sleep` returned — the very stall this is meant to
  # bound — and killing it would print job-control noise into the suite output.
  # Whole seconds only.
  (
    waited=0
    while (( waited < SKILL_X_TEST_TIMEOUT )); do
      [[ -e $finished ]] && exit 0
      kill -0 "$pid" 2>/dev/null || exit 0
      sleep 1
      waited=$((waited + 1))
    done
    [[ -e $finished ]] && exit 0
    : > "$marker" 2>/dev/null || true
    if command -v pkill >/dev/null 2>&1; then
      pkill -TERM -P "$pid" 2>/dev/null || true
    fi
    kill -TERM "$pid" 2>/dev/null || true
    # Grace period before SIGKILL, given up as soon as the test is actually gone
    # so the watchdog never holds the suite's output open longer than needed.
    for _ in 1 2; do
      kill -0 "$pid" 2>/dev/null || exit 0
      sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
  ) &

  { wait "$pid"; } 2>/dev/null || status=$?
  : > "$finished"

  elapsed=$(($(skill_x_test_now_ms) - start))
  _skill_x_test_timings+=("$elapsed $name")

  if [[ -e $marker ]]; then
    printf 'TIMEOUT after %ss\n' "$SKILL_X_TEST_TIMEOUT"
    timed_out=$((timed_out + 1))
    failed=$((failed + 1))
    return 0
  fi

  if (( status == 0 )); then
    printf 'PASS (%s)\n' "$(skill_x_test_format_ms "$elapsed")"
    passed=$((passed + 1))
  else
    printf 'FAIL (%s)\n' "$(skill_x_test_format_ms "$elapsed")"
    failed=$((failed + 1))
  fi
}

# Prints the suite summary and returns non-zero if anything failed or timed out.
skill_x_test_finish() {
  local label=${1:-suite}
  local total=0
  [[ -n $_skill_x_suite_started ]] && total=$(($(skill_x_test_now_ms) - _skill_x_suite_started))

  if (( ${#_skill_x_test_timings[@]} > 0 )); then
    printf '\nSlowest cases in %s:\n' "$label"
    local line ms name
    while IFS= read -r line; do
      ms=${line%% *}
      name=${line#* }
      printf '  %8s  %s\n' "$(skill_x_test_format_ms "$ms")" "$name"
    done < <(printf '%s\n' "${_skill_x_test_timings[@]}" | sort -rn | head -5)
  fi

  printf '\nRESULT [%s | %s suite]: %d passed, %d failed' \
    "$label" "$SKILL_X_TEST_SUITE" "$passed" "$failed"
  (( timed_out > 0 )) && printf ' (%d timed out)' "$timed_out"
  (( skipped > 0 )) && printf ', %d skipped (full suite only)' "$skipped"
  printf ' in %s\n' "$(skill_x_test_format_ms "$total")"

  (( failed == 0 ))
}
