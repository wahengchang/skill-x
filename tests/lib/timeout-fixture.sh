#!/usr/bin/env bash
# Controlled fixture for the harness timeout path: a suite whose only test
# never finishes. Run with a small SKILL_X_TEST_TIMEOUT; the harness must
# report TIMEOUT and exit non-zero instead of hanging.
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-timeout-fixture.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

# Bounded by default so the fixture is cheap to run from the fast suite.
: "${SKILL_X_TEST_TIMEOUT:=2}"

# shellcheck source=harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"

stalled_test() {
  sleep 600
}

run_test --fast 'stalled test is terminated' stalled_test

skill_x_test_finish 'timeout fixture'
