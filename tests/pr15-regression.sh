#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-pr15-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
export SKILL_X_OPENCODE_VERSION=v1

copy_project() {
  local destination=$1
  mkdir -p "$destination"
  cp -a "$PROJECT_ROOT/." "$destination/"
  rm -rf "$destination/.git" "$destination/commands" "$destination/opencode-commands"
}

test_configured_canonical_dest_and_adapter_contract() {
  local project="$TEST_ROOT/target-contract"
  local home="$TEST_ROOT/target-contract-home"
  copy_project "$project"

  cat > "$project/bin/targets/probe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  build)
    src=$2
    dest=$3
    # The adapter must receive the common canonical artifact, not raw commands-src.
    rg -q '此區塊由 bin/build.sh' "$src/example-skill/SKILL.md"
    mkdir -p "$dest"
    printf 'processed-canonical\n' > "$dest/probe.txt"
    ;;
  sync|bootstrap)
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$project/bin/targets/probe.sh"

  cat > "$project/bin/targets/targets.conf" <<'EOF'
CANONICAL_DEST="generated-canonical"
CANONICAL_CONSUMERS=(
  "custom:~/.custom-agent/skills"
)
TRANSFORMED_TARGETS=(
  "opencode-v1-commands:opencode-commands"
  "probe:probe-artifact"
)
EOF

  "$project/bin/build.sh" >/dev/null
  [[ -f "$project/generated-canonical/example-skill/SKILL.md" ]]
  [[ -f "$project/probe-artifact/probe.txt" ]]

  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null
  local link="$home/.custom-agent/skills/example-skill"
  [[ -L "$link" ]]
  [[ "$(cd "$(dirname "$(readlink "$link")")" && pwd -P)/$(basename "$(readlink "$link")")" == \
     "$project/generated-canonical/example-skill" ]]
}

test_cloud_bootstrap_supports_legacy_pinned_ref() {
  local legacy="$TEST_ROOT/legacy-source"
  local bare="$TEST_ROOT/legacy.git"
  local home="$TEST_ROOT/legacy-home"
  copy_project "$legacy"

  rm -rf "$legacy/bin/targets"
  cat > "$legacy/bin/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
rm -rf "$ROOT/commands" "$ROOT/opencode-commands"
mkdir -p "$ROOT/commands" "$ROOT/opencode-commands"
cp -a "$ROOT/commands-src/example-skill" "$ROOT/commands/example-skill"
cat > "$ROOT/opencode-commands/example-skill.md" <<'SHIM'
---
description: 'legacy fixture'
---
<!-- skill-x-managed-command: example-skill -->
Use the `skill` tool to load the `example-skill` skill.
SHIM
EOF
  chmod +x "$legacy/bin/build.sh"

  git -C "$legacy" init -q
  git -C "$legacy" config user.email test@example.invalid
  git -C "$legacy" config user.name 'Test Runner'
  git -C "$legacy" add .
  git -C "$legacy" commit -qm legacy-layout
  git init -q --bare "$bare"
  git -C "$legacy" remote add origin "$bare"
  git -C "$legacy" push -qu origin HEAD
  local ref
  ref=$(git -C "$legacy" rev-parse HEAD)

  mkdir -p "$home/.config/opencode/commands"
  printf 'user owned\n' > "$home/.config/opencode/commands/user-command.md"

  HOME="$home" SKILL_X_OPENCODE_VERSION=v1 \
    "$PROJECT_ROOT/bin/cloud-bootstrap.sh" "file://$bare" "$ref" >/dev/null

  [[ -f "$home/.claude/skills/example-skill/SKILL.md" ]]
  [[ ! -L "$home/.claude/skills/example-skill" ]]
  rg -q 'skill-x-managed-command' "$home/.config/opencode/commands/example-skill.md"
  [[ $(cat "$home/.config/opencode/commands/user-command.md") == 'user owned' ]]
}

test_configured_canonical_dest_and_adapter_contract
test_cloud_bootstrap_supports_legacy_pinned_ref

echo 'PR #15 regression tests: PASS'
