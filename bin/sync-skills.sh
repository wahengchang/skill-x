#!/usr/bin/env bash
# Compatibility wrapper: `bin/skill-x sync` owns synchronization now.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec "$ROOT/bin/skill-x" sync "$@"
