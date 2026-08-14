#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"$ROOT/bin/build.sh"
"$ROOT/bin/sync-skills.sh"
echo "Installation complete. Run bin/doctor.sh to inspect it."
