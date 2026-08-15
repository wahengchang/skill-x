#!/usr/bin/env bash
# Compatibility wrapper: `bin/skill-x doctor` owns diagnostics now.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec "$ROOT/bin/skill-x" doctor "$@"
