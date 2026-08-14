#!/usr/bin/env bash
# Compatibility wrapper used by the in-skill update prompt: the user has already
# agreed, so the confirmation is passed through.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec "$ROOT/bin/skill-x" update --yes "$@"
