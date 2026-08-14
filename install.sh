#!/usr/bin/env bash
# Bootstrap entry point. The lifecycle lives in bin/skill-x; this only exists so
# that a fresh clone has an obvious first command to run.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$ROOT/bin/skill-x" init "$@"
