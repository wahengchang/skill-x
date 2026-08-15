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
  [[ "$(cd "$(readlink "$link")" && pwd -P)" == \
     "$(cd "$project/generated-canonical/example-skill" && pwd -P)" ]]
}

test_rejects_unsafe_artifact_destinations_without_damage() {
  local project="$TEST_ROOT/unsafe-path" victim="$TEST_ROOT/victim"
  copy_project "$project"
  mkdir -p "$victim"
  echo sentinel > "$victim/keep"
  sed -i.bak 's/CANONICAL_DEST="commands"/CANONICAL_DEST="..\/victim"/' "$project/bin/targets/targets.conf"
  rm "$project/bin/targets/targets.conf.bak"
  ! "$project/bin/build.sh" >"$project/out" 2>"$project/err"
  rg -q 'Invalid CANONICAL_DEST' "$project/err"
  [[ $(cat "$victim/keep") == sentinel ]]

  for value in /tmp/absolute . ''; do
    sed "s|CANONICAL_DEST=.*|CANONICAL_DEST=\"$value\"|" "$PROJECT_ROOT/bin/targets/targets.conf" > "$project/bin/targets/targets.conf"
    ! "$project/bin/build.sh" >/dev/null 2>&1
  done

  # Duplicate and parent/child destinations are rejected by the shared validator.
  (
    ROOT="$project"
    source "$project/bin/lib/targets.sh"
    CANONICAL_DEST=commands
    TRANSFORMED_TARGETS=("probe:commands")
    ! skill_x_validate_artifact_paths >/dev/null 2>&1
    TRANSFORMED_TARGETS=("probe:commands/child")
    ! skill_x_validate_artifact_paths >/dev/null 2>&1
  )
}

test_custom_artifacts_are_gitignored() {
  local project="$TEST_ROOT/custom-ignore"
  copy_project "$project"
  sed -i.bak 's/CANONICAL_DEST="commands"/CANONICAL_DEST="generated-canonical"/; s/:opencode-commands"/:generated-shims"/' "$project/bin/targets/targets.conf"
  rm "$project/bin/targets/targets.conf.bak"
  git -C "$project" init -q
  git -C "$project" add . && git -C "$project" -c user.name=test -c user.email=test@example.invalid commit -qm base
  "$project/bin/build.sh" >/dev/null
  [[ -z $(git -C "$project" status --short) ]]
}

test_destination_migration_removes_only_managed_links() {
  local project="$TEST_ROOT/migration" home="$TEST_ROOT/migration-home"
  copy_project "$project"
  mkdir -p "$project/commands-src/removed"
  cp "$project/commands-src/example-skill/SKILL.md" "$project/commands-src/removed/SKILL.md"
  "$project/bin/build.sh" >/dev/null
  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null
  local target="$home/.claude/skills"
  echo owned > "$target/user-file"
  ln -s "$TEST_ROOT/unrelated" "$target/user-link"
  rm -rf "$project/commands-src/removed"
  sed -i.bak 's/CANONICAL_DEST="commands"/CANONICAL_DEST="new-commands"/' "$project/bin/targets/targets.conf"
  rm "$project/bin/targets/targets.conf.bak"
  "$project/bin/build.sh" >/dev/null
  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null 2>/dev/null
  [[ ! -L "$target/removed" && -f "$target/user-file" && -L "$target/user-link" ]]
}

test_destination_migration_isolates_checkouts() {
  local a="$TEST_ROOT/checkout-a" b="$TEST_ROOT/checkout-b" home="$TEST_ROOT/checkouts-home"
  copy_project "$a"
  mkdir -p "$a/commands-src/only-in-a"
  cp "$a/commands-src/example-skill/SKILL.md" "$a/commands-src/only-in-a/SKILL.md"
  "$a/bin/build.sh" >/dev/null
  HOME="$home" "$a/bin/sync-skills.sh" >/dev/null

  copy_project "$b"
  "$b/bin/build.sh" >/dev/null
  HOME="$home" "$b/bin/sync-skills.sh" >/dev/null

  # A skill present only in checkout A must survive checkout B's sync: the
  # per-installation manifest must not let checkout B claim A's managed link.
  [[ -L "$home/.claude/skills/only-in-a" ]]
  [[ "$(cd "$(readlink "$home/.claude/skills/only-in-a")" && pwd -P)" == \
     "$(cd "$a/commands/only-in-a" && pwd -P)" ]]
}

test_doctor_reads_canonical_consumers_from_metadata() {
  local project="$TEST_ROOT/doctor" home="$TEST_ROOT/doctor-home"
  copy_project "$project"
  awk '/CANONICAL_CONSUMERS=\(/ { print; print "  \"probe:~/.probe/skills\""; next } { print }' \
    "$project/bin/targets/targets.conf" > "$project/bin/targets/targets.conf.new"
  mv "$project/bin/targets/targets.conf.new" "$project/bin/targets/targets.conf"
  "$project/bin/build.sh" >/dev/null
  HOME="$home" "$project/bin/sync-skills.sh" >/dev/null 2>/dev/null
  HOME="$home" "$project/bin/doctor.sh" > "$project/doctor.out"
  rg -qF "$home/.probe/skills" "$project/doctor.out"
  rg -q 'OpenCode v1' "$project/doctor.out"
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
test_rejects_unsafe_artifact_destinations_without_damage
test_custom_artifacts_are_gitignored
test_destination_migration_removes_only_managed_links
test_destination_migration_isolates_checkouts
test_doctor_reads_canonical_consumers_from_metadata
test_cloud_bootstrap_supports_legacy_pinned_ref

echo 'PR #15 regression tests: PASS'
