#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-plan-content.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

# shellcheck source=lib/harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"
skill_x_test_parse_args "$@"

FACETS_DIR="$PROJECT_ROOT/commands-src/_x-shared/facets"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print the body of every ```bash / ```sh fenced block in the given file.
extract_fenced_bash() {
  awk '
    /^[[:space:]]*```(bash|sh)[[:space:]]*$/ { infence = 1; next }
    /^[[:space:]]*```[[:space:]]*$/ { infence = 0 }
    infence { print }
  ' "$@"
}

# Print the content of a single H2 section (from the `## <heading>` line to the
# next `## ` heading or end of file).
extract_section() {
  local file=$1 heading=$2
  awk -v h="## $heading" '
    index($0, h) == 1 { inse = 1; next }
    inse && /^## / { inse = 0 }
    inse { print }
  ' "$file"
}

# A forbidden mutation must not appear inside a bash/sh fence.
assert_no_forbidden_in_fences() {
  local file=$1
  if extract_fenced_bash "$file" | rg -qF -e 'item new' -e 'wg new' -e 'worktree add' \
      -e 'git worktree' -e 'field set' -e 'plan ready'; then
    echo "forbidden token inside a bash/sh fence in $file" >&2
    extract_fenced_bash "$file" | rg -nF -e 'item new' -e 'wg new' -e 'worktree add' \
      -e 'git worktree' -e 'field set' -e 'plan ready' >&2
    return 1
  fi
}

# A forbidden mutation must not appear as a first-token command line.
assert_no_first_token_forbidden() {
  local file=$1 matches
  if matches=$(rg -n '^\s*(xdh|"\$XDH")\s+(item new|wg new|field set|plan ready)\b|^\s*git\s+(branch|worktree\s+add)\b' "$file"); then
    echo "forbidden first-token command in $file:" >&2
    echo "$matches" >&2
    return 1
  fi
}

frontmatter_name() {
  awk -F': ' '/^name: / { sub(/\r$/, "", $2); print $2; exit }' "$1"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_facet_contracts_exist_and_are_clean() {
  for facet in product design devex engineering; do
    local contract="$FACETS_DIR/$facet-facet-contract.md"
    [[ -f "$contract" ]] || { echo "missing $contract" >&2; return 1; }
    ! rg -q '^## Handover' "$contract"
    ! rg -q '^## Continuing' "$contract"
  done
}

test_facet_contracts_have_no_runnable_forbidden() {
  for facet in product design devex engineering; do
    local contract="$FACETS_DIR/$facet-facet-contract.md"
    assert_no_forbidden_in_fences "$contract" || return 1
    assert_no_first_token_forbidden "$contract" || return 1
  done
}

test_specialist_facet_mode_sections_have_no_runnable_forbidden() {
  local section="$TEST_ROOT/facet-mode-section.tmp"
  local -a specialists=(
    "x-plan-product|Facet mode"
    "x-plan-design|Facet mode"
    "x-plan-devex|Facet mode"
    "x-plan-eng|Engineering Facet"
  )
  local entry skill heading
  for entry in "${specialists[@]}"; do
    skill=${entry%%|*}
    heading=${entry##*|}
    extract_section "$PROJECT_ROOT/commands-src/$skill/SKILL.md" "$heading" > "$section"
    [[ -s "$section" ]] || { echo "empty facet-mode section for $skill" >&2; return 1; }
    assert_no_forbidden_in_fences "$section" || return 1
    assert_no_first_token_forbidden "$section" || return 1
  done
}

test_x_plan_references_only_local_facet_contracts() {
  local skill="$PROJECT_ROOT/commands-src/x-plan/SKILL.md"
  for facet in product design devex engineering; do
    rg -qF "references/$facet-facet-contract.md" "$skill"
  done
  ! rg -q 'commands-src/x-plan-' "$skill"
  ! rg -q '_x-shared/facets/' "$skill"
}

test_x_plan_has_precedence_ladder_and_mandatory_engineering() {
  local skill="$PROJECT_ROOT/commands-src/x-plan/SKILL.md"
  for token in \
    'explicit target' \
    'handover Target' \
    'items of the only active WG' \
    'only draft item in the only active Cycle' \
    'only standalone draft item' \
    'structured user-input capability' \
    'conversational question and stop' \
    'BLOCKED_NO_USER_INPUT_CAPABILITY'; do
    rg -qF "$token" "$skill"
  done
  rg -qF 'Engineering mandatory' "$skill" || rg -qF 'mandatory' "$skill"
}

test_new_skills_have_symlinks_and_references() {
  local s
  for s in x-plan x-plan-product x-plan-design x-plan-devex; do
    [[ -L "$PROJECT_ROOT/commands-src/$s/scripts" ]] || { echo "missing scripts symlink: $s" >&2; return 1; }
    [[ -L "$PROJECT_ROOT/commands-src/$s/templates" ]] || { echo "missing templates symlink: $s" >&2; return 1; }
    [[ -f "$PROJECT_ROOT/commands-src/$s/scripts/xdh" ]] || { echo "scripts symlink does not resolve: $s" >&2; return 1; }
    [[ -f "$PROJECT_ROOT/commands-src/$s/templates/issue.md" ]] || { echo "templates symlink does not resolve: $s" >&2; return 1; }
  done
  for facet in product design devex engineering; do
    local link="$PROJECT_ROOT/commands-src/x-plan/references/$facet-facet-contract.md"
    [[ -L "$link" && -f "$link" ]] || { echo "x-plan references/$facet-facet-contract.md missing/broken" >&2; return 1; }
  done
  for s in x-plan-product x-plan-design x-plan-devex x-plan-eng; do
    local link="$PROJECT_ROOT/commands-src/$s/references/facet-contract.md"
    [[ -L "$link" && -f "$link" ]] || { echo "$s references/facet-contract.md missing/broken" >&2; return 1; }
  done
}

test_frontmatter_name_matches_folder() {
  local s name
  for s in x-plan x-plan-product x-plan-design x-plan-devex x-plan-eng; do
    name=$(frontmatter_name "$PROJECT_ROOT/commands-src/$s/SKILL.md")
    [[ "$name" == "$s" ]] || { echo "name mismatch: $s -> $name" >&2; return 1; }
  done
}

test_facet_contracts_cover_required_topics() {
  rg -qF 'pending Owner Decision' "$FACETS_DIR/product-facet-contract.md"
  rg -qF 'scope expansion' "$FACETS_DIR/product-facet-contract.md"

  for cap in 'Image Generate' 'Image Display' 'Image Compare'; do
    rg -qF "$cap" "$FACETS_DIR/design-facet-contract.md"
  done
  rg -qF 'capability ladder' "$FACETS_DIR/design-facet-contract.md"

  for token in 'setup' 'first change' 'test' 'debug' 'CI/release'; do
    rg -qF "$token" "$FACETS_DIR/devex-facet-contract.md"
  done

  rg -qF 'mandatory' "$FACETS_DIR/engineering-facet-contract.md"
}

test_x_plan_eng_direct_mode_gate() {
  local skill="$PROJECT_ROOT/commands-src/x-plan-eng/SKILL.md"
  rg -qF 'plan check' "$skill"
  rg -qF 'wg new' "$skill"
  rg -qF 'plan ready' "$skill"
  ! rg -q '^\s*(xdh|"\$XDH")\s+field set' "$skill"
  ! rg -qF 'field set <IS file> Status ready' "$skill"
}

test_literal_happy_paths_assign_item_owner() {
  local skill
  for skill in x-plan x-plan-eng; do
    local file="$PROJECT_ROOT/commands-src/$skill/SKILL.md"
    rg -qF 'item new --type issue' "$file"
    rg -qF -- '--owner "<owner>"' "$file"
    rg -qF 'field set <item> Owner "<owner>"' "$file"
    ! rg -qF 'wg new assigns the Owner' "$file"
  done
}

test_build_materializes_references_as_real_files() {
  local project="$TEST_ROOT/built"
  copy_built_project "$project"

  local p
  for facet in product design devex engineering; do
    p="$project/commands/x-plan/references/$facet-facet-contract.md"
    [[ -f "$p" && ! -L "$p" ]] || { echo "not a real file: $p" >&2; return 1; }
  done
  for s in x-plan-product x-plan-design x-plan-devex x-plan-eng; do
    p="$project/commands/$s/references/facet-contract.md"
    [[ -f "$p" && ! -L "$p" ]] || { echo "not a real file: $p" >&2; return 1; }
  done

  [[ ! -e "$project/commands/_x-shared" ]] || { echo "_x-shared was shipped as a skill" >&2; return 1; }
}

run_test 'facet contracts exist and are clean' test_facet_contracts_exist_and_are_clean
run_test 'facet contracts have no runnable forbidden invocation' test_facet_contracts_have_no_runnable_forbidden
run_test 'facet-mode sections have no runnable forbidden invocation' test_specialist_facet_mode_sections_have_no_runnable_forbidden
run_test 'x-plan references only local facet contracts' test_x_plan_references_only_local_facet_contracts
run_test 'x-plan has the precedence ladder and mandatory engineering' test_x_plan_has_precedence_ladder_and_mandatory_engineering
run_test 'new skills have symlinks and references' test_new_skills_have_symlinks_and_references
run_test 'frontmatter name matches folder' test_frontmatter_name_matches_folder
run_test 'facet contracts cover required topics' test_facet_contracts_cover_required_topics
run_test 'x-plan-eng direct mode documents the two-phase gate' test_x_plan_eng_direct_mode_gate
run_test 'literal happy paths assign item owner' test_literal_happy_paths_assign_item_owner
run_test 'build materializes references as real files' test_build_materializes_references_as_real_files

# ---------------------------------------------------------------------------
# Content contract: the remaining accepted behaviors must be stated, not merely
# implemented, so the skill text and the machine gates agree.
# ---------------------------------------------------------------------------

test_product_scope_stop_and_no_silent_defaults() {
  local skill="$PROJECT_ROOT/commands-src/x-plan-product/SKILL.md"
  rg -qF 'pending Owner Decision' "$skill"
  rg -qF 'never silently adopts a recommended answer' "$skill"

  local contract="$FACETS_DIR/product-facet-contract.md"
  rg -qF 'stop there rather than silently adopting' "$contract"

  # The orchestrator must forbid silently applying a default to a facet decision.
  local orchestrator="$PROJECT_ROOT/commands-src/x-plan/SKILL.md"
  rg -qF 'must never silently apply a default' "$orchestrator"
}

test_input_capability_fallback_is_runtime_agnostic() {
  local skill="$PROJECT_ROOT/commands-src/x-plan/SKILL.md"
  rg -qF 'structured input facility' "$skill" || rg -qF 'structured user-input' "$skill"
  rg -qF 'conversational question and stop' "$skill"
  rg -qF 'BLOCKED_NO_USER_INPUT_CAPABILITY' "$skill"
  rg -qF 'only when no later response can be obtained' "$skill"
}

test_design_ux_and_capability_ladder() {
  local contract="$FACETS_DIR/design-facet-contract.md"
  for cap in 'Image Generate' 'Image Display' 'Image Compare'; do
    rg -qF "$cap" "$contract"
  done
  rg -qF 'capability ladder' "$contract"
  rg -qF 'downgrade' "$contract"

  local skill="$PROJECT_ROOT/commands-src/x-plan-design/SKILL.md"
  rg -qF 'capability ladder' "$skill"
  rg -qF 'downgrades' "$skill"
}

test_devex_journey_chain() {
  local contract="$FACETS_DIR/devex-facet-contract.md"
  for stage in 'setup' 'first change' 'test' 'debug' 'CI/release'; do
    rg -qF "$stage" "$contract"
  done
  rg -qF 'never an assumption' "$contract"

  local skill="$PROJECT_ROOT/commands-src/x-plan-devex/SKILL.md"
  rg -qF 'setup → first change → test → debug → CI/release' "$skill"
  rg -qF 'by assumption' "$skill"
}

test_target_scope_precedence_and_terminal_wg_status() {
  local skill="$PROJECT_ROOT/commands-src/x-plan/SKILL.md"
  for token in 'explicit target' 'handover Target' 'only active WG' 'only standalone draft item'; do
    rg -qF "$token" "$skill"
  done
  rg -qF 'Status: draft' "$skill"
  # "active WG" is defined by the terminal-status vocabulary, never by mtime.
  rg -qF 'terminal' "$skill"
  rg -qF 'merged' "$skill"
  rg -qF 'x_status_is_terminal' "$skill"
  rg -qF 'X_TERMINAL_WG_STATUSES' "$skill"
  rg -qF 'Never union WGs' "$skill"
  rg -qF 'Cycle and standalone scopes' "$skill"
}

test_lifecycle_planning_handoffs() {
  local skill
  for skill in x-discovery x-review x-debug x-ship x-housekeeping; do
    rg -qF 'Discovery → Planning → Implementation' "$PROJECT_ROOT/commands-src/$skill/SKILL.md"
    ! rg -q 'Engineering Planning' "$PROJECT_ROOT/commands-src/$skill/SKILL.md"
  done
  rg -qF 'Next: x-plan' "$PROJECT_ROOT/commands-src/x-discovery/SKILL.md"
}

test_specialist_facet_mode_vocabulary_excludes_not_applicable() {
  local skill
  for skill in x-plan-product x-plan-design x-plan-devex; do
    extract_section "$PROJECT_ROOT/commands-src/$skill/SKILL.md" 'Facet mode' > "$TEST_ROOT/fm.tmp"
    rg -qF 'xdh plan facet set' "$TEST_ROOT/fm.tmp"
    rg -qF '<value>' "$TEST_ROOT/fm.tmp"
    # The `<value>` vocabulary line must not list not-applicable as a writable status.
    ! rg -q '<value>.*not-applicable' "$TEST_ROOT/fm.tmp"
  done
  extract_section "$PROJECT_ROOT/commands-src/x-plan-eng/SKILL.md" 'Engineering Facet' > "$TEST_ROOT/eng.tmp"
  rg -qF '<value>' "$TEST_ROOT/eng.tmp"
  ! rg -q '<value>.*not-applicable' "$TEST_ROOT/eng.tmp"
  ! rg -q '<value>.*deferred-owner' "$TEST_ROOT/eng.tmp"
}

run_test 'product scope stop and no silent defaults' test_product_scope_stop_and_no_silent_defaults
run_test 'input capability fallback is runtime agnostic' test_input_capability_fallback_is_runtime_agnostic
run_test 'design UX and capability ladder' test_design_ux_and_capability_ladder
run_test 'devex journey chain' test_devex_journey_chain
run_test 'target scope precedence and terminal WG status' test_target_scope_precedence_and_terminal_wg_status
run_test 'lifecycle planning handoffs' test_lifecycle_planning_handoffs
run_test 'specialist facet-mode vocabulary excludes not-applicable' test_specialist_facet_mode_vocabulary_excludes_not_applicable

skill_x_test_finish 'plan content'
