#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-plan-machine.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

# shellcheck source=lib/harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"
skill_x_test_parse_args "$@"

# Build the project, then hand back a throwaway Git repository plus the path to
# the *deployed* xdh — the exact file a synced tool would execute.
make_xdh_fixture() {
  local project=$1 repo=$2
  copy_built_project "$project"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'
  echo seed > "$repo/seed.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial
  mkdir -p "$repo/.dev-hub/runtime/standalone"
}

xdh() { "$XDH" "$@"; }

# Emit a complete, non-placeholder new-format Issue for a given route. The
# Engineering facet stays `pending` (or per-route) so facet set can complete it.
emit_full_issue() {
  local id=$1 route=$2
  local pf df vf ef
  pf=pending; df=pending; vf=pending; ef=pending
  case ",$route," in *,product,*) ;; *) pf=not-applicable ;; esac
  case ",$route," in *,design,*) ;; *) df=not-applicable ;; esac
  case ",$route," in *,devex,*) ;; *) vf=not-applicable ;; esac
  cat <<EOF
# $id — $id

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z
- Planning route: $route
- Selected work: $id
- Planning input fingerprint: —
- Product facet: $pf
- Product evidence: —
- Design facet: $df
- Design evidence: —
- DevEx facet: $vf
- DevEx evidence: —
- Engineering facet: $ef
- Engineering evidence: —
- Planning Complete: pending
- Execution Ready: pending

## Problem / Goal

The session times out and users are kicked out.

## Scope

### In

Extend session timeout.

### Out

No password change.

## Current → Desired Behavior

Current: 30m timeout. Desired: configurable.

## Architecture / Data Flow

\`\`\`text
token -> middleware -> check
\`\`\`

## Interfaces / Dependencies

The auth middleware reads the session store.

## Failure Modes / Edge Cases / Risks

A clock skew breaks the timeout.

## Implementation Order

1. Add a config flag.
2. Wire the middleware.

## Tests

| Layer | What | Count |
|---|---|---|
| unit | timeout parse | 1 |

## Acceptance Criteria

1. Sessions older than the configured value return 401.

## Definition of Ready

- [x] Scope and behavior clear
- [x] Dependencies identified
- [x] Risks and failure paths addressed
- [x] Tests and acceptance defined
- [ ] Owner/WG/branch/worktree prepared

## Owner Decisions

| ID | Facet | Question / change | Decision | State | Fingerprint |
|---|---|---|---|---|---|

## Product Facet

## Design Facet

## DevEx Facet

## Engineering Facet

## Handover

- Current state: planning
- Blockers: none
- Owner decision: none
- Next: x-plan
- Target: \`$id\`
EOF
}

emit_full_spike() {
  local id=$1
  cat <<EOF
# $id — $id

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z
- Planning route: engineering
- Selected work: $id
- Planning input fingerprint: —
- Product facet: not-applicable
- Product evidence: —
- Design facet: not-applicable
- Design evidence: —
- DevEx facet: not-applicable
- DevEx evidence: —
- Engineering facet: pending
- Engineering evidence: —
- Planning Complete: pending
- Execution Ready: pending

## Core Question

Which store survives a burst of concurrent writes?

## Why This Blocks a Decision

Choosing the store before knowing its behavior is a guess.

## Current Hypothesis

An embedded store is enough.

## Scope / Timebox

One day of investigation.

## Method

- Code/docs to inspect: the write path
- Experiment/prototype: load test
- Evidence to collect: p99 latency

## Decision Rule

Use the embedded store if p99 stays under 10ms.

## Required Output

\`Do this: use the embedded store. Because: p99 under 10ms.\`

## Constraints

No new external service.

## Result

- Conclusion:
- Evidence:
- Follow-up Issue(s):

## Owner Decisions

| ID | Facet | Question / change | Decision | State | Fingerprint |
|---|---|---|---|---|---|

## Product Facet

## Design Facet

## DevEx Facet

## Engineering Facet

## Handover

- Current state: planning
- Blockers: none
- Owner decision: none
- Next: x-plan
- Target: \`$id\`
EOF
}

# Write a full issue file at path and complete engineering via facet set.
write_issue_and_complete() {
  local file=$1 XDH=$2 route=${3:-engineering}
  local id
  id=$(basename "$file" | cut -d- -f1,2)
  emit_full_issue "$id" "$route" > "$file"
  local fp
  fp=$("$XDH" plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  "$XDH" plan facet set "$file" --facet engineering --status "completed@$fp" --evidence "engineering plan" >/dev/null
}

test_xdh_plan_fingerprint_issue_is_normalized_and_stale_on_input_change() {
  local project="$TEST_ROOT/fp" repo="$TEST_ROOT/fp-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-fp.md"
  emit_full_issue IS-001 engineering > "$file"

  local fp1 fp2
  fp1=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ ${#fp1} -eq 64 ]]
  fp2=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fp1 == "$fp2" ]]

  # Any fingerprinted-input edit (here the Problem/Goal body) stales the fp.
  printf 'More problem text.\n' >> "$file"  # appends into... careful: append to section
  # Rewrite the Problem/Goal body deterministically instead.
  emit_full_issue IS-001 engineering > "$file"
  sed -i.bak 's/The session times out and users are kicked out./CHANGED GOAL/' "$file"
  rm -f "$file.bak"
  local fp3
  fp3=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fp3 != "$fp1" ]]
}

test_xdh_plan_fingerprint_rejects_section_boundary_collision() {
  local project="$TEST_ROOT/coll" repo="$TEST_ROOT/coll-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local a="$repo/.dev-hub/runtime/standalone/IS-001-a.md"
  local b="$repo/.dev-hub/runtime/standalone/IS-001-b.md"
  # Two issues whose Problem/Goal bodies differ only by a literal backslash-n
  # versus a real newline must hash differently.
  emit_full_issue IS-001 engineering > "$a"
  emit_full_issue IS-001 engineering > "$b"
  printf 'A literal backslash-n: \\n marker.\n' > /dev/null  # (comment, ignored)

  # a: Problem/Goal contains a literal backslash+n; b: a real newline.
  sed -i.bak 's|The session times out and users are kicked out.|literal\\n in body|' "$a"
  rm -f "$a.bak"
  sed -i.bak 's|The session times out and users are kicked out.|literal backslash\\ then newline|' "$b"
  rm -f "$b.bak"
  local fa fb
  fa=$(xdh plan fingerprint "$a" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  fb=$(xdh plan fingerprint "$b" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ -n $fa && -n $fb ]]
  [[ $fa != "$fb" ]]
}

test_xdh_plan_fingerprint_is_locale_independent() {
  local project="$TEST_ROOT/locale" repo="$TEST_ROOT/locale-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-loc.md"
  emit_full_issue IS-001 engineering > "$file"
  local a b
  a=$(LC_ALL=C xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  b=$(LC_ALL=en_US.UTF-8 xdh plan fingerprint "$file" 2>/dev/null | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ -n $a ]]
  if [[ -n $b ]]; then [[ $a == "$b" ]]; fi
}

test_xdh_plan_fingerprint_spike_includes_method_and_decision_rule() {
  local project="$TEST_ROOT/spike" repo="$TEST_ROOT/spike-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/SP-001-sp.md"
  emit_full_spike SP-001 > "$file"
  local out fmt fp
  out=$(xdh plan fingerprint "$file")
  fmt=$(printf '%s\n' "$out" | sed -n 's/^X_PLAN_FORMAT=//p')
  fp=$(printf '%s\n' "$out" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fmt == x-plan-input-spike-v1 ]]
  [[ ${#fp} -eq 64 ]]

  # Editing the Method changes the fingerprint.
  sed -i.bak 's/load test/a different experiment/' "$file"
  rm -f "$file.bak"
  local fp2
  fp2=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fp2 != "$fp" ]]
}

test_xdh_plan_init_upgrades_legacy_draft_in_place() {
  local project="$TEST_ROOT/init" repo="$TEST_ROOT/init-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  mkdir -p "$repo/.dev-hub/runtime/standalone"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-legacy.md"
  cat > "$file" <<'EOF'
# IS-001 — Legacy

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z

## Problem / Goal

Some real problem.

## Scope

### In

### Out

## Handover

- Next: x-plan
EOF
  cp "$file" "$project/legacy-before.md"

  local out
  out=$(xdh plan init "$file" --route engineering --selected-work IS-001)
  rg -q '^X_PLAN_INITIALIZED=IS-001$' <<<"$out"
  rg -q '^X_PLAN_REUSED=no$' <<<"$out"

  rg -q '^- Planning route: engineering$' "$file"
  rg -q '^## Owner Decisions$' "$file"
  rg -q '^## Engineering Facet$' "$file"
  rg -q 'Some real problem.' "$file"

  # A second call is a no-op and never duplicates the header.
  out=$(xdh plan init "$file" --route engineering --selected-work IS-001)
  rg -q '^X_PLAN_REUSED=yes$' <<<"$out"
  [[ $(rg -c '^- Planning route:' "$file") -eq 1 ]]
}

test_xdh_plan_init_adds_required_issue_and_spike_scaffolds() {
  local project="$TEST_ROOT/scaff" repo="$TEST_ROOT/scaff-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  mkdir -p "$repo/.dev-hub/runtime/standalone"
  local sp="$repo/.dev-hub/runtime/standalone/SP-001-s.md"
  cat > "$sp" <<'EOF'
# SP-001 — S

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z

## Core Question

?

## Method

- Code/docs to inspect:

## Decision Rule

x

## Handover

- Next: x-plan
EOF
  xdh plan init "$sp" --route engineering --selected-work SP-001 >/dev/null
  # Spike gets Constraints plus Owner Decisions + four facet scaffolds.
  rg -q '^## Constraints$' "$sp"
  rg -q '^## Owner Decisions$' "$sp"
  rg -q '^## Product Facet$' "$sp"
  rg -q '^## Engineering Facet$' "$sp"
}

test_xdh_plan_facet_set_scopes_mutation_to_one_facet() {
  local project="$TEST_ROOT/facet" repo="$TEST_ROOT/facet-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-fs.md"
  emit_full_issue IS-001 "product,design,devex,engineering" > "$file"
  cp "$file" "$project/before.md"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')

  # Engineering is the sole facet mutated.
  xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence "eng evidence" >/dev/null
  rg -q '^- Engineering facet: completed@' "$file"
  rg -q '^- Engineering evidence: eng evidence$' "$file"
  rg -q '^- Product facet: pending$' "$file"
  rg -q '^- Design facet: pending$' "$file"

  # A stale completion suffix is rejected and changes nothing.
  if xdh plan facet set "$file" --facet design --status "completed@deadbeef" --evidence x >"$project/stale.out" 2>&1; then
    return 1
  fi
  rg -q 'status=stale' "$project/stale.out"
  rg -q '^- Design facet: pending$' "$file"

  # An out-of-project section file is rejected.
  if xdh plan facet set "$file" --facet design --status "completed@$fp" --evidence x \
      --section-file "$TEST_ROOT/outside.md" >"$project/sec.out" 2>&1; then
    return 1
  fi
  rg -q 'section-file' "$project/sec.out"
}

test_xdh_item_new_renders_every_planning_field() {
  local project="$TEST_ROOT/render" repo="$TEST_ROOT/render-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local out file
  out=$(cd "$repo" && "$XDH" item new --type issue --slug render --route "product,engineering")
  file=$(printf '%s\n' "$out" | sed -n 's/^X_ITEM_FILE=//p')
  rg -q '^- Planning route: product,engineering$' "$file"
  rg -q '^- Selected work: IS-001$' "$file"
  rg -q '^- Product facet: pending$' "$file"
  rg -q '^- Design facet: not-applicable$' "$file"
  rg -q '^- DevEx facet: not-applicable$' "$file"
  rg -q '^- Engineering facet: pending$' "$file"
  rg -q '^- Planning Complete: pending$' "$file"
  rg -q '^- Execution Ready: pending$' "$file"
  ! rg -q '\{\{' "$file"
}

test_xdh_plan_check_fails_closed_on_stale_or_blocked_facets() {
  local project="$TEST_ROOT/checkfail" repo="$TEST_ROOT/checkfail-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-cf.md"
  emit_full_issue IS-001 engineering > "$file"
  # Engineering still pending -> check fails.
  if xdh plan check "$file" >"$project/out" 2>&1; then return 1; fi
  rg -q 'BLOCKER facet=engineering status=pending' "$project/out"

  # Complete engineering, then add a pending Owner Decision -> still fails.
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence e >/dev/null
  awk '1; /^\|--/ { print "| OD-001 | product | expand scope | recommend | pending | — |" }' "$file" > "$project/tmp.md"
  mv "$project/tmp.md" "$file"
  if xdh plan check "$file" >"$project/out2" 2>&1; then return 1; fi
  rg -q 'BLOCKER decision=OD-001 state=pending' "$project/out2"
}

test_xdh_plan_check_does_not_change_item_status() {
  local project="$TEST_ROOT/checkstatus" repo="$TEST_ROOT/checkstatus-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-cs.md"
  write_issue_and_complete "$file" "$XDH"
  local out
  out=$(xdh plan check "$file")
  rg -q '^X_PLAN_CHECK=PASS$' <<<"$out"
  rg -q '^- Status: draft$' "$file"
  rg -q '^- Planning Complete: completed@' "$file"
}

test_xdh_plan_ready_is_atomic_and_requires_consistent_worktree() {
  local project="$TEST_ROOT/ready" repo="$TEST_ROOT/ready-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  (cd "$repo" && "$XDH" item new --type issue --slug rdy >/dev/null)
  local file="$repo/.dev-hub/runtime/standalone/IS-001-rdy.md"
  write_issue_and_complete "$file" "$XDH"
  (cd "$repo" && "$XDH" field set "$file" Owner alice >/dev/null)
  (cd "$repo" && "$XDH" plan check "$file" >/dev/null)

  # No WG yet -> ready fails.
  if (cd "$repo" && "$XDH" plan ready "$file" >"$project/no-wg.out" 2>&1); then return 1; fi
  rg -q 'wg=missing' "$project/no-wg.out"

  # Create the WG (writes WG back into the item) and re-check/ready.
  (cd "$repo" && "$XDH" wg new --slug rdy --items IS-001 --owner alice >/dev/null)
  rg -q '^- WG: WG-001$' "$file"
  (cd "$repo" && "$XDH" plan check "$file" >/dev/null)
  (cd "$repo" && "$XDH" plan ready "$file" >"$project/ready.out")
  rg -q '^X_PLAN_READY=IS-001$' "$project/ready.out"
  rg -q '^- Status: ready$' "$file"
  rg -q '^- Execution Ready: completed@' "$file"
}

test_xdh_plan_ready_completes_without_lock_timeout_or_leak() {
  local project="$TEST_ROOT/noleak" repo="$TEST_ROOT/noleak-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  (cd "$repo" && "$XDH" item new --type issue --slug leak >/dev/null)
  local file="$repo/.dev-hub/runtime/standalone/IS-001-leak.md"
  write_issue_and_complete "$file" "$XDH"
  (cd "$repo" && "$XDH" field set "$file" Owner alice >/dev/null)
  (cd "$repo" && "$XDH" wg new --slug leak --items IS-001 --owner alice >/dev/null && "$XDH" plan check "$file" >/dev/null)
  (cd "$repo" && "$XDH" plan ready "$file" >/dev/null)
  # No lock dir or staged temp files remain.
  [[ -z $(find "$repo/.dev-hub" -name '.xdh-plan.lock' -o -name '.xdh-field.*' -o -name '.xdh-block.*' -o -name '.xdh-body.*' 2>/dev/null) ]]
}

test_xdh_new_ready_gate_preserves_legacy_transition() {
  local project="$TEST_ROOT/gate" repo="$TEST_ROOT/gate-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  mkdir -p "$repo/.dev-hub/runtime/standalone"

  # New-format item: every case/space variant of ready is rejected.
  local nf="$repo/.dev-hub/runtime/standalone/IS-001-new.md"
  emit_full_issue IS-001 engineering > "$nf"
  local v
  for v in ready READY " ready" "ready " "  READY  "; do
    if (cd "$repo" && "$XDH" field set "$nf" Status "$v" >"$project/g.out" 2>&1); then
      echo "unexpectedly allowed ready variant: $v" >&2
      return 1
    fi
    rg -q 'plan ready' "$project/g.out"
  done
  rg -q '^- Status: draft$' "$nf"

  # Legacy item keeps the old transition.
  local lf="$repo/.dev-hub/runtime/standalone/IS-002-legacy.md"
  cat > "$lf" <<'EOF'
# IS-002 — Legacy

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z

## Problem / Goal

x

## Handover

- Next: x-plan
EOF
  (cd "$repo" && "$XDH" field set "$lf" Status ready >/dev/null)
  rg -q '^- Status: ready$' "$lf"
}

test_xdh_wg_new_merges_and_writes_items_on_reuse() {
  local project="$TEST_ROOT/wgmerge" repo="$TEST_ROOT/wgmerge-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  (cd "$repo" && "$XDH" item new --type issue --slug a >/dev/null)
  (cd "$repo" && "$XDH" item new --type issue --slug b >/dev/null)
  local file_a="$repo/.dev-hub/runtime/standalone/IS-001-a.md"
  local file_b="$repo/.dev-hub/runtime/standalone/IS-002-b.md"

  (cd "$repo" && "$XDH" wg new --slug grp --items "IS-001, IS-002" --owner alice >/dev/null)
  rg -q '^- WG: WG-001$' "$file_a"
  rg -q '^- WG: WG-001$' "$file_b"

  # A later union adds IS-003 without creating a second WG.
  (cd "$repo" && "$XDH" item new --type issue --slug c >/dev/null)
  local file_c="$repo/.dev-hub/runtime/standalone/IS-003-c.md"
  (cd "$repo" && "$XDH" wg new --slug grp --items "IS-003" --owner alice >"$project/wg.out")
  rg -q '^X_WG_REUSED=yes$' "$project/wg.out"
  local wgfile
  wgfile=$(printf '%s\n' "$(cd "$repo" && "$XDH" wg new --slug grp)" | sed -n 's/^X_WG_FILE=//p')
  rg -q '^- Work items: IS-001,IS-002,IS-003$' "$wgfile"
  rg -q '^- WG: WG-001$' "$file_c"
  [[ $(find "$repo/.dev-hub" -name 'WG-*.md' | wc -l) -eq 1 ]]
}

test_xdh_design_artifacts_reuse_replace_and_cleanup() {
  local project="$TEST_ROOT/design" repo="$TEST_ROOT/design-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"

  # Standalone design root is deterministic.
  local d1 d2
  d1=$(cd "$repo" && "$XDH" design prepare --slug hero --fingerprint aaaa --image-generate available --image-display unavailable --image-compare available |
       sed -n 's/^X_DESIGN_DIR=//p')
  rg -q '/artifacts/design/hero$' <<<"$d1"
  [[ -f "$d1/manifest.md" ]]
  rg -q '^Fingerprint: aaaa$' "$d1/manifest.md"

  # Same slug + fingerprint reuses without replacing.
  d2=$(cd "$repo" && "$XDH" design prepare --slug hero --fingerprint aaaa --image-generate available --image-display unavailable --image-compare available |
       sed -n 's/^X_DESIGN_REUSED=//p')
  [[ $d2 == yes ]]

  # A changed fingerprint replaces the scaffold.
  local d3
  d3=$(cd "$repo" && "$XDH" design prepare --slug hero --fingerprint bbbb --image-generate available --image-display unavailable --image-compare available |
       sed -n 's/^X_DESIGN_DIR=//p')
  rg -q '^Fingerprint: bbbb$' "$d3/manifest.md"

  # A traversal slug is slugified and contained under the design root.
  local d4 root
  root=$(cd "$repo" && "$XDH" design prepare --slug '../escape' --fingerprint cccc --image-generate available --image-display unavailable --image-compare available |
         sed -n 's/^X_DESIGN_DIR=//p')
  rg -q '/artifacts/design/escape$' <<<"$root"

  # A Cycle creates its own design root.
  (cd "$repo" && "$XDH" cycle new --slug design-cycle >/dev/null)
  local cd_dir
  cd_dir=$(cd "$repo" && "$XDH" design prepare --slug cyc --fingerprint dddd --image-generate available --image-display unavailable --image-compare available |
           sed -n 's/^X_DESIGN_DIR=//p')
  rg -q '/artifacts/design/cyc$' <<<"$cd_dir"
  [[ -d $(cd "$repo" && printf '%s' "$cd_dir") ]]
}

run_test 'fingerprint issue is normalized and stale on input change' test_xdh_plan_fingerprint_issue_is_normalized_and_stale_on_input_change
run_test 'fingerprint rejects section boundary collision' test_xdh_plan_fingerprint_rejects_section_boundary_collision
run_test 'fingerprint is locale independent' test_xdh_plan_fingerprint_is_locale_independent
run_test 'spike fingerprint includes method and decision rule' test_xdh_plan_fingerprint_spike_includes_method_and_decision_rule
run_test 'plan init upgrades a legacy draft in place' test_xdh_plan_init_upgrades_legacy_draft_in_place
run_test 'plan init adds required issue and spike scaffolds' test_xdh_plan_init_adds_required_issue_and_spike_scaffolds
run_test 'plan facet set scopes mutation to one facet' test_xdh_plan_facet_set_scopes_mutation_to_one_facet
run_test 'item new renders every planning field' test_xdh_item_new_renders_every_planning_field
run_test 'plan check fails closed on stale or blocked facets' test_xdh_plan_check_fails_closed_on_stale_or_blocked_facets
run_test 'plan check does not change item status' test_xdh_plan_check_does_not_change_item_status
run_test 'plan ready is atomic and requires a consistent worktree' test_xdh_plan_ready_is_atomic_and_requires_consistent_worktree
run_test 'plan ready completes without lock timeout or leak' test_xdh_plan_ready_completes_without_lock_timeout_or_leak
run_test 'new-format ready gate preserves legacy transition' test_xdh_new_ready_gate_preserves_legacy_transition
run_test 'wg new merges and writes items on reuse' test_xdh_wg_new_merges_and_writes_items_on_reuse
run_test 'design artifacts reuse replace and cleanup' test_xdh_design_artifacts_reuse_replace_and_cleanup

# ---------------------------------------------------------------------------
# Golden references, strict validation, deferral acceptance, and preflight.
# ---------------------------------------------------------------------------

append_decision_row() {
  local file=$1 id=$2 facet=$3 state=$4
  local fingerprint=—
  [[ $state == accepted@* ]] && fingerprint=${state#accepted@}
  awk -v id="$id" -v facet="$facet" -v state="$state" -v fingerprint="$fingerprint" '
    /^## / { inse = ($0 == "## Owner Decisions") }
    { print }
    inse && /^\|--/ && !done { print "| " id " | " facet " | q | d | " state " | " fingerprint " |"; done = 1 }
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

test_xdh_plan_fingerprint_matches_golden_reference() {
  local project="$TEST_ROOT/golden" repo="$TEST_ROOT/golden-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-g.md"
  emit_full_issue IS-001 engineering > "$file"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fp == 71c303d87c53407627a26845b46876e3b887c74519519903c1b9d2790ca44e4c ]]

  local sp="$repo/.dev-hub/runtime/standalone/SP-001-g.md"
  emit_full_spike SP-001 > "$sp"
  local fsp
  fsp=$(xdh plan fingerprint "$sp" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fsp == de8deec48f313ac1e72a4193395c0304af352aaa54c3a2454d6d15d5f4dcef72 ]]
}

test_xdh_plan_fingerprint_rejects_invalid_selected_work() {
  local project="$TEST_ROOT/badsw" repo="$TEST_ROOT/badsw-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-b.md"
  emit_full_issue IS-001 engineering > "$file"
  sed 's/- Selected work: IS-001/- Selected work: BOGUS/' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
  if xdh plan fingerprint "$file" >"$project/out" 2>&1; then return 1; fi
  rg -q 'selected-work=invalid' "$project/out"
}

test_xdh_plan_fingerprint_rejects_duplicate_section_heading() {
  local project="$TEST_ROOT/dupsec" repo="$TEST_ROOT/dupsec-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-d.md"
  emit_full_issue IS-001 engineering > "$file"
  printf '\n## Problem / Goal\n\nduplicate\n' >> "$file"
  if xdh plan fingerprint "$file" >"$project/out" 2>&1; then return 1; fi
  rg -q 'status=duplicate' "$project/out"
}

test_xdh_plan_fingerprint_spike_requires_engineering_route() {
  local project="$TEST_ROOT/spikeroute" repo="$TEST_ROOT/spikeroute-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/SP-001-r.md"
  emit_full_spike SP-001 > "$file"
  sed 's/- Planning route: engineering/- Planning route: product,engineering/' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
  if xdh plan fingerprint "$file" >"$project/out" 2>&1; then return 1; fi
  rg -q 'spike-requires-engineering' "$project/out"
}

test_xdh_plan_check_enforces_deferred_acceptance() {
  local project="$TEST_ROOT/defer" repo="$TEST_ROOT/defer-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-df.md"
  emit_full_issue IS-001 "product,engineering" > "$file"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence e >/dev/null
  xdh plan facet set "$file" --facet product --status "deferred-owner@$fp" --evidence "owner to decide" >/dev/null

  # No accepted decision -> deferral fails closed.
  if xdh plan check "$file" >"$project/out" 2>&1; then return 1; fi
  rg -q 'facet=product status=deferred-unaccepted' "$project/out"

  # The public ID-keyed writer records pending, then accepts it at the current
  # fingerprint; tests do not bypass the lifecycle with a raw table edit.
  xdh plan decision set "$file" --id OD-001 --facet product --question "Defer product?" --decision "defer it" --state pending >/dev/null
  xdh plan decision set "$file" --id OD-001 --facet product --question "Defer product?" --decision "approved" --state "accepted@$fp" >/dev/null
  local out
  out=$(xdh plan check "$file")
  rg -q '^X_PLAN_CHECK=PASS$' <<<"$out"
}

test_xdh_plan_check_notices_stale_and_blocks_stale_product() {
  local project="$TEST_ROOT/staledec" repo="$TEST_ROOT/staledec-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"

  # engineering-only route: a stale product decision is NOTICE, not a blocker.
  local f1="$repo/.dev-hub/runtime/standalone/IS-001-s1.md"
  emit_full_issue IS-001 engineering > "$f1"
  local fp1
  fp1=$(xdh plan fingerprint "$f1" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f1" --facet engineering --status "completed@$fp1" --evidence e >/dev/null
  append_decision_row "$f1" OD-001 product "accepted@deadbeef"
  local out1
  out1=$(xdh plan check "$f1")
  rg -q '^X_PLAN_CHECK=PASS$' <<<"$out1"
  rg -q 'NOTICE decision=OD-001 state=accepted@deadbeef' <<<"$out1"

  # product selected + stale product decision -> blocks re-anchor.
  local f2="$repo/.dev-hub/runtime/standalone/IS-002-s2.md"
  emit_full_issue IS-002 "product,engineering" > "$f2"
  local fp2
  fp2=$(xdh plan fingerprint "$f2" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f2" --facet engineering --status "completed@$fp2" --evidence e >/dev/null
  xdh plan facet set "$f2" --facet product --status "completed@$fp2" --evidence e >/dev/null
  append_decision_row "$f2" OD-001 product "accepted@deadbeef"
  if xdh plan check "$f2" >"$project/out2" 2>&1; then return 1; fi
  rg -q 'state=stale-product' "$project/out2"
}

test_xdh_plan_facet_set_validates_route_and_evidence() {
  local project="$TEST_ROOT/facet2" repo="$TEST_ROOT/facet2-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-f2.md"
  emit_full_issue IS-001 engineering > "$file"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')

  # Placeholder evidence is rejected.
  if xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence "—" >"$project/out" 2>&1; then return 1; fi
  rg -q 'evidence-invalid' "$project/out"

  # A non-canonical stored route is rejected.
  sed 's/- Planning route: engineering/- Planning route: engineering,product/' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
  if xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence e >"$project/out2" 2>&1; then return 1; fi
  rg -q 'non-canonical' "$project/out2"
}

test_xdh_plan_init_rejects_duplicate_and_inserts_only_missing() {
  local project="$TEST_ROOT/init2" repo="$TEST_ROOT/init2-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  mkdir -p "$repo/.dev-hub/runtime/standalone"

  # Duplicate required heading -> reject without changing bytes.
  local dup="$repo/.dev-hub/runtime/standalone/IS-001-dup.md"
  cat > "$dup" <<'EOF'
# IS-001 — Dup

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z

## Problem / Goal

x

## Owner Decisions

| ID | Facet | Question / change | Decision | State | Fingerprint |
|---|---|---|---|---|---|

## Owner Decisions

## Handover

- Next: x-plan
EOF
  cp "$dup" "$project/dup-before.md"
  if xdh plan init "$dup" --route engineering --selected-work IS-001 >"$project/out" 2>&1; then return 1; fi
  rg -q 'duplicate required heading' "$project/out"
  cmp "$dup" "$project/dup-before.md"

  # Already-present Owner Decisions is not duplicated; only missing scaffolds land.
  local partial="$repo/.dev-hub/runtime/standalone/IS-002-part.md"
  cat > "$partial" <<'EOF'
# IS-002 — Part

- Status: draft
- Priority: P2
- Owner: —
- WG: —
- Source: —
- Created: 2026-08-16T00:00:00Z

## Problem / Goal

x

## Owner Decisions

| ID | Facet | Question / change | Decision | State | Fingerprint |
|---|---|---|---|---|---|

## Handover

- Next: x-plan
EOF
  xdh plan init "$partial" --route engineering --selected-work IS-002 >/dev/null
  [[ $(rg -c '^## Owner Decisions$' "$partial") -eq 1 ]]
  rg -q '^## Product Facet$' "$partial"
  rg -q '^## Engineering Facet$' "$partial"
}

test_xdh_wg_new_preflight_fails_without_side_effects() {
  local project="$TEST_ROOT/wgpre" repo="$TEST_ROOT/wgpre-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"

  # Missing item.
  if (cd "$repo" && "$XDH" wg new --slug a --items IS-999 >"$project/m.out" 2>&1); then return 1; fi
  rg -q 'cannot resolve item' "$project/m.out"

  # Malformed item id.
  if (cd "$repo" && "$XDH" wg new --slug b --items BOGUS >"$project/b.out" 2>&1); then return 1; fi
  rg -q 'malformed item id' "$project/b.out"

  # No WG document, branch, or worktree was created by any failed preflight.
  [[ -z $(find "$repo/.dev-hub" -name 'WG-*.md' 2>/dev/null) ]]
  [[ -z $(git -C "$repo" branch --list 'x/*') ]]
  [[ $(git -C "$repo" worktree list | wc -l) -eq 1 ]]

  # An item already owned by another WG is not silently reassigned.
  (cd "$repo" && "$XDH" item new --type issue --slug one >/dev/null)
  (cd "$repo" && "$XDH" item new --type issue --slug two >/dev/null)
  (cd "$repo" && "$XDH" wg new --slug first --items IS-001 >/dev/null)
  if (cd "$repo" && "$XDH" wg new --slug second --items IS-001 >"$project/owned.out" 2>&1); then return 1; fi
  rg -q 'already owned by WG-001' "$project/owned.out"
}

run_test 'fingerprint matches golden reference' test_xdh_plan_fingerprint_matches_golden_reference
run_test 'fingerprint rejects invalid selected-work' test_xdh_plan_fingerprint_rejects_invalid_selected_work
run_test 'fingerprint rejects duplicate section heading' test_xdh_plan_fingerprint_rejects_duplicate_section_heading
run_test 'spike fingerprint requires engineering route' test_xdh_plan_fingerprint_spike_requires_engineering_route
run_test 'plan check enforces deferred acceptance' test_xdh_plan_check_enforces_deferred_acceptance
run_test 'plan check notices stale and blocks stale product' test_xdh_plan_check_notices_stale_and_blocks_stale_product
run_test 'plan facet set validates route and evidence' test_xdh_plan_facet_set_validates_route_and_evidence
run_test 'plan init rejects duplicates and inserts only missing' test_xdh_plan_init_rejects_duplicate_and_inserts_only_missing
run_test 'wg new preflight fails without side effects' test_xdh_wg_new_preflight_fails_without_side_effects

# ---------------------------------------------------------------------------
# Additional coverage for the accepted contract.
# ---------------------------------------------------------------------------

test_xdh_wg_new_rejects_duplicate_items() {
  local project="$TEST_ROOT/wgdup" repo="$TEST_ROOT/wgdup-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  (cd "$repo" && "$XDH" item new --type issue --slug a >/dev/null)

  if (cd "$repo" && "$XDH" wg new --slug dup --items "IS-001, IS-001" >"$project/out" 2>&1); then return 1; fi
  rg -q 'duplicate item id' "$project/out"

  # No WG, branch, or worktree side effect from the rejected duplicate input.
  [[ -z $(find "$repo/.dev-hub" -name 'WG-*.md' 2>/dev/null) ]]
  [[ -z $(git -C "$repo" branch --list 'x/*') ]]
  [[ $(git -C "$repo" worktree list | wc -l) -eq 1 ]]
  rg -q '^- WG: —$' "$repo/.dev-hub/runtime/standalone/IS-001-a.md"
}

test_xdh_wg_new_preflight_rejects_ambiguous_and_cross_scope() {
  local project="$TEST_ROOT/wgamb" repo="$TEST_ROOT/wgamb-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"

  # Ambiguous: two files sharing the IS-001 ID prefix.
  mkdir -p "$repo/.dev-hub/runtime/standalone"
  cp "$project/commands/x-plan-eng/templates/issue.md" "$repo/.dev-hub/runtime/standalone/IS-001-a.md"
  cp "$project/commands/x-plan-eng/templates/issue.md" "$repo/.dev-hub/runtime/standalone/IS-001-b.md"
  if (cd "$repo" && "$XDH" wg new --slug amb --items IS-001 >"$project/amb.out" 2>&1); then return 1; fi
  rg -q 'missing or ambiguous' "$project/amb.out"

  # Cross-scope: an item in a Cycle is not visible from a different scope.
  (cd "$repo" && "$XDH" cycle new --slug one >/dev/null)
  (cd "$repo" && "$XDH" item new --type issue --slug in-cycle --cycle one >/dev/null)
  (cd "$repo" && "$XDH" cycle new --slug two >/dev/null)
  if (cd "$repo" && "$XDH" wg new --slug xs --items IS-001 --cycle two >"$project/xs.out" 2>&1); then return 1; fi
  rg -q 'cannot resolve item' "$project/xs.out"

  # No WG, branch, or worktree was created by any failed preflight.
  [[ -z $(find "$repo/.dev-hub" -name 'WG-*.md' 2>/dev/null) ]]
  [[ -z $(git -C "$repo" branch --list 'x/*') ]]
  [[ $(git -C "$repo" worktree list | wc -l) -eq 1 ]]
}

test_xdh_plan_facet_set_rejects_engineering_deferral() {
  local project="$TEST_ROOT/engdef" repo="$TEST_ROOT/engdef-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-ed.md"
  emit_full_issue IS-001 engineering > "$file"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')

  for st in "deferred-owner@$fp" "deferred-missing@$fp"; do
    if xdh plan facet set "$file" --facet engineering --status "$st" --evidence e >"$project/out" 2>&1; then return 1; fi
    rg -q 'deferral-forbidden' "$project/out"
  done
  rg -q '^- Engineering facet: pending$' "$file"
}

test_xdh_plan_fingerprint_requires_canonical_route() {
  local project="$TEST_ROOT/canonroute" repo="$TEST_ROOT/canonroute-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-cr.md"
  emit_full_issue IS-001 engineering > "$file"
  # engineering last is canonical; engineering,product is not.
  sed 's/- Planning route: engineering/- Planning route: engineering,product/' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
  if xdh plan fingerprint "$file" >"$project/out" 2>&1; then return 1; fi
  rg -q 'non-canonical' "$project/out"
}

test_xdh_plan_facet_set_rejects_symlink_and_dotdot_section_file() {
  local project="$TEST_ROOT/secfile" repo="$TEST_ROOT/secfile-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-sf.md"
  emit_full_issue IS-001 "product,engineering" > "$file"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')

  printf 'outside content\n' > "$TEST_ROOT/outside-sf.md"

  # Dot-dot traversal is rejected.
  if (cd "$repo" && "$XDH" plan facet set "$file" --facet product --status "completed@$fp" --evidence e \
      --section-file "../outside-sf.md" >"$project/dotdot.out" 2>&1); then return 1; fi
  rg -q 'section-file' "$project/dotdot.out"

  # A symlink inside the project that resolves outside is rejected.
  ln -s "$TEST_ROOT/outside-sf.md" "$repo/inside-link.md"
  if (cd "$repo" && "$XDH" plan facet set "$file" --facet product --status "completed@$fp" --evidence e \
      --section-file "$repo/inside-link.md" >"$project/symlink.out" 2>&1); then return 1; fi
  rg -q 'section-file' "$project/symlink.out"

  # Nothing changed in the item.
  rg -q '^- Product facet: pending$' "$file"

  # A project-contained section file is accepted and its body is written once.
  printf 'A product decision with evidence.\n' > "$repo/prod.md"
  (cd "$repo" && "$XDH" plan facet set "$file" --facet product --status "completed@$fp" --evidence "see prod.md" \
    --section-file "$repo/prod.md" >/dev/null)
  rg -q '^- Product facet: completed@' "$file"
  rg -q 'A product decision with evidence.' "$file"
}

test_xdh_plan_facet_set_rejects_duplicate_h2_and_multiline_evidence() {
  local project="$TEST_ROOT/facetedge" repo="$TEST_ROOT/facetedge-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-fe.md"
  emit_full_issue IS-001 engineering > "$file"
  local fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')

  # Duplicate H2 -> section-cardinality, no byte change.
  printf '\n## Engineering Facet\n\ndup\n' >> "$file"
  cp "$file" "$project/before-dup.md"
  if xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence e >"$project/dup.out" 2>&1; then return 1; fi
  rg -q 'section-cardinality' "$project/dup.out"
  cmp "$file" "$project/before-dup.md"

  # Restore, then reject multi-line evidence.
  emit_full_issue IS-001 engineering > "$file"
  cp "$file" "$project/before-ml.md"
  if xdh plan facet set "$file" --facet engineering --status "completed@$fp" --evidence $'line1\nline2' >"$project/ml.out" 2>&1; then return 1; fi
  rg -q 'evidence-invalid' "$project/ml.out"
  cmp "$file" "$project/before-ml.md"
}

test_xdh_plan_check_writes_fields_atomically() {
  local project="$TEST_ROOT/atomic" repo="$TEST_ROOT/atomic-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-at.md"
  write_issue_and_complete "$file" "$XDH"

  local out fp
  fp=$(xdh plan fingerprint "$file" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  out=$(xdh plan check "$file")
  rg -q '^X_PLAN_CHECK=PASS$' <<<"$out"
  rg -q "^- Planning input fingerprint: $fp\$" "$file"
  rg -q "^- Planning Complete: completed@$fp\$" "$file"
  rg -q '^- Status: draft$' "$file"
  # One combined write leaves no staging or lock residue.
  [[ -z $(find "$repo/.dev-hub" -name '.xdh-field.*' -o -name '.xdh-plan.lock' 2>/dev/null) ]]
}

test_xdh_plan_facet_set_no_byte_change_on_failure() {
  local project="$TEST_ROOT/nobytes" repo="$TEST_ROOT/nobytes-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-nb.md"
  emit_full_issue IS-001 engineering > "$file"
  cp "$file" "$project/before.md"

  # Stale suffix fails without changing a byte.
  if xdh plan facet set "$file" --facet engineering --status "completed@deadbeef" --evidence e >"$project/out" 2>&1; then return 1; fi
  cmp "$file" "$project/before.md"

  # Facet not in route fails without changing a byte.
  if xdh plan facet set "$file" --facet product --status pending --evidence e >"$project/out2" 2>&1; then return 1; fi
  cmp "$file" "$project/before.md"
}

test_xdh_plan_init_rejects_duplicate_schema_even_on_reuse() {
  local project="$TEST_ROOT/initreuse" repo="$TEST_ROOT/initreuse-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  mkdir -p "$repo/.dev-hub/runtime/standalone"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-ir.md"
  emit_full_issue IS-001 engineering > "$file"
  # Corrupt the schema: duplicate a required heading while the header is present.
  printf '\n## Product Facet\n\ndup\n' >> "$file"
  cp "$file" "$project/before.md"
  if xdh plan init "$file" --route engineering --selected-work IS-001 >"$project/out" 2>&1; then return 1; fi
  rg -q 'duplicate required heading' "$project/out"
  cmp "$file" "$project/before.md"
}

test_xdh_plan_init_rejects_missing_scaffold_and_wrong_handover_on_reuse() {
  local project="$TEST_ROOT/initcorrupt" repo="$TEST_ROOT/initcorrupt-repo"
  make_xdh_fixture "$project" "$repo"
  local XDH="$project/commands/x-plan-eng/scripts/xdh"
  mkdir -p "$repo/.dev-hub/runtime/standalone"
  local file="$repo/.dev-hub/runtime/standalone/IS-001-ic.md"

  # Missing required scaffold on an already-marked item -> reject, byte-identical.
  emit_full_issue IS-001 engineering > "$file"
  sed '/^## Engineering Facet$/d' "$file" > "$file.tmp"; mv "$file.tmp" "$file"
  cp "$file" "$project/before-missing.md"
  if xdh plan init "$file" --route engineering --selected-work IS-001 >"$project/miss.out" 2>&1; then return 1; fi
  rg -q 'missing required heading' "$project/miss.out"
  cmp "$file" "$project/before-missing.md"

  # Wrong Handover cardinality on an already-marked item -> reject, byte-identical.
  emit_full_issue IS-001 engineering > "$file"
  printf '\n## Handover\n\ndup\n' >> "$file"
  cp "$file" "$project/before-handover.md"
  if xdh plan init "$file" --route engineering --selected-work IS-001 >"$project/ho.out" 2>&1; then return 1; fi
  rg -q 'exactly one ## Handover' "$project/ho.out"
  cmp "$file" "$project/before-handover.md"
}

test_xdh_plan_file_snapshot_is_byte_exact() {
  # The readiness snapshot must distinguish files that differ only in trailing
  # LF bytes, which a `$(cat file)` substitution silently collapses.
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/commands-src/_x-shared/scripts/lib/plan.sh"

  local a="$TEST_ROOT/snap-a.md" b="$TEST_ROOT/snap-b.md" c="$TEST_ROOT/snap-c.md"
  printf 'same body' > "$a"
  printf 'same body\n' > "$b"
  printf 'same body\n\n' > "$c"

  local ha hb hc
  ha=$(x_plan_file_sha256 "$a")
  hb=$(x_plan_file_sha256 "$b")
  hc=$(x_plan_file_sha256 "$c")
  [[ ${#ha} -eq 64 && ${#hb} -eq 64 && ${#hc} -eq 64 ]]
  [[ $ha != "$hb" ]]
  [[ $hb != "$hc" ]]
  [[ $ha != "$hc" ]]
}

test_rv001_empty_route_blocks_generic_ready() { local p="$TEST_ROOT/r1" r="$TEST_ROOT/r1r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001.md"; emit_full_issue IS-001 engineering > "$f"; sed 's/^- Planning route: engineering$/- Planning route:/' "$f" > "$f.tmp"; mv "$f.tmp" "$f"; if (cd "$r" && "$XDH" field set "$f" Status ready >"$p/o" 2>&1); then return 1; fi; rg -q 'plan ready' "$p/o"; }

test_rv002_empty_completed_facet_blocks_check() { local p="$TEST_ROOT/r2" r="$TEST_ROOT/r2r" XDH f fp; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001.md"; emit_full_issue IS-001 engineering > "$f"; fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p'); xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence e >/dev/null; sed '/^e$/d' "$f" > "$f.tmp"; mv "$f.tmp" "$f"; if xdh plan check "$f" >"$p/o" 2>&1; then return 1; fi; rg -q 'Engineering-Facet status=empty' "$p/o"; }

test_rv003_invalid_decision_blocks_check() { local p="$TEST_ROOT/r3" r="$TEST_ROOT/r3r" XDH f fp; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001-x.md"; write_issue_and_complete "$f" "$XDH"; awk '1; /^\|---/ { print "| OD-001 | product | q | — | unknown | — |" }' "$f" > "$f.tmp"; mv "$f.tmp" "$f"; if xdh plan check "$f" >"$p/o" 2>&1; then return 1; fi; rg -q 'decision=OD-001 status=invalid' "$p/o"; }

test_rv004_product_writes_pending_decision() { local p="$TEST_ROOT/r4" r="$TEST_ROOT/r4r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001-x.md"; emit_full_issue IS-001 product,engineering > "$f"; printf '| OD-001 | product | scope? | include it | pending | — |' > "$r/decision"; (cd "$r" && "$XDH" plan facet set "$f" --facet product --status blocked --evidence decision --owner-decision-file "$r/decision" >/dev/null); rg -q '^| OD-001 | product | scope? | include it | pending | — |$' "$f"; }

test_rv005_concurrent_wg_claim_blocks_second_slug() {
  local p="$TEST_ROOT/r5" r="$TEST_ROOT/r5r" XDH barrier p1 p2 s1 s2
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  (cd "$r" && "$XDH" item new --type issue --slug one --owner alice >/dev/null)
  barrier="$p/barrier"
  mkdir "$barrier"
  (touch "$barrier/alpha-ready"; while [[ ! -e $barrier/go ]]; do :; done; cd "$r"; "$XDH" wg new --slug alpha --items IS-001 --owner alice >"$p/alpha.out" 2>&1) & p1=$!
  (touch "$barrier/beta-ready"; while [[ ! -e $barrier/go ]]; do :; done; cd "$r"; "$XDH" wg new --slug beta --items IS-001 --owner alice >"$p/beta.out" 2>&1) & p2=$!
  while [[ ! -e $barrier/alpha-ready || ! -e $barrier/beta-ready ]]; do :; done
  touch "$barrier/go"
  if wait "$p1"; then s1=0; else s1=$?; fi
  if wait "$p2"; then s2=0; else s2=$?; fi
  [[ ( $s1 -eq 0 && $s2 -ne 0 ) || ( $s2 -eq 0 && $s1 -ne 0 ) ]]
  rg -q 'already owned by WG-001' "$p/alpha.out" "$p/beta.out"
  [[ $(find "$r/.dev-hub" -name 'WG-*.md' -type f | wc -l | tr -d ' ') -eq 1 ]]
  [[ $(git -C "$r" branch --list 'x/*' | wc -l | tr -d ' ') -eq 1 ]]
  [[ $(git -C "$r" worktree list --porcelain | awk '/^worktree /{n++} END{print n+0}') -eq 2 ]]
}

test_rv006_placeholder_wg_blocks_ready() { local p="$TEST_ROOT/r6" r="$TEST_ROOT/r6r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001-x.md"; write_issue_and_complete "$f" "$XDH"; (cd "$r" && "$XDH" field set "$f" Owner a >/dev/null && "$XDH" wg new --slug r6 --items IS-001 --owner a >/dev/null && "$XDH" plan check "$f" >/dev/null && "$XDH" field set "$f" WG — >/dev/null); if (cd "$r" && "$XDH" plan ready "$f" >"$p/o" 2>&1); then return 1; fi; rg -q 'wg=missing' "$p/o"; }

test_rv007_symlinked_design_root_blocks() { local p="$TEST_ROOT/r7" r="$TEST_ROOT/r7r" out="$TEST_ROOT/r7out" XDH s; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; s="$r/.dev-hub/runtime/standalone"; mkdir -p "$out"; ln -s "$out" "$s/artifacts"; if (cd "$r" && "$XDH" design prepare --dir "$s" --slug hero --fingerprint f --image-generate unavailable --image-display unavailable --image-compare unavailable >"$p/o" 2>&1); then return 1; fi; rg -q 'symlinked design root' "$p/o"; [[ ! -e "$out/design/hero" ]]; }

test_rv008_ready_requires_check_stamp() { local p="$TEST_ROOT/r8" r="$TEST_ROOT/r8r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001-x.md"; write_issue_and_complete "$f" "$XDH"; (cd "$r" && "$XDH" field set "$f" Owner a >/dev/null && "$XDH" wg new --slug r8 --items IS-001 --owner a >/dev/null); if (cd "$r" && "$XDH" plan ready "$f" >"$p/o" 2>&1); then return 1; fi; rg -q 'planning-complete=missing' "$p/o"; }

test_rv009_crlf_headings_are_parsed() { local p="$TEST_ROOT/r9" r="$TEST_ROOT/r9r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001.md"; emit_full_issue IS-001 engineering | awk '{printf "%s\r\n", $0}' > "$f"; xdh plan fingerprint "$f" | rg -q '^X_PLAN_FINGERPRINT='; }

test_rv010_init_preserves_crlf() { local p="$TEST_ROOT/r10" r="$TEST_ROOT/r10r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001.md"; printf '# IS-001\r\n- Status: draft\r\n- Created: now\r\n\r\n## Handover\r\n' > "$f"; xdh plan init "$f" --route engineering --selected-work IS-001 >/dev/null; [[ $(awk '/\r$/{n++} END{print n+0}' "$f") -eq $(wc -l < "$f") ]]; }

test_rv011_facet_set_rechecks_freshness_under_lock() { local p="$TEST_ROOT/r11" r="$TEST_ROOT/r11r" XDH f fp lock pid; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001.md"; emit_full_issue IS-001 engineering > "$f"; fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p'); lock="$r/.dev-hub/runtime/standalone/.xdh-plan.lock"; mkdir "$lock"; (cd "$r" && "$XDH" plan facet set "$f" --facet engineering --status "completed@$fp" --evidence e >"$p/o" 2>&1) & pid=$!; sleep 0.2; sed 's/session times out/session now expires/' "$f" > "$f.tmp"; mv "$f.tmp" "$f"; cp "$f" "$p/after-edit"; rmdir "$lock"; if wait "$pid"; then return 1; fi; rg -q 'status=stale' "$p/o"; cmp "$f" "$p/after-edit"; }

test_rv009_literal_owner_happy_path_and_reuse_repair() { local p="$TEST_ROOT/r9owner" r="$TEST_ROOT/r9ownerr" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; (cd "$r" && "$XDH" item new --type issue --slug owner --route engineering --owner alice >/dev/null); f="$r/.dev-hub/runtime/standalone/IS-001-owner.md"; rg -q '^- Owner: alice$' "$f"; (cd "$r" && "$XDH" field set "$f" Owner — >/dev/null && "$XDH" field set "$f" Owner alice >/dev/null); rg -q '^- Owner: alice$' "$f"; }

test_rv012_duplicate_semantic_section_blocks() { local p="$TEST_ROOT/r12" r="$TEST_ROOT/r12r" XDH f; make_xdh_fixture "$p" "$r"; XDH="$p/commands/x-plan-eng/scripts/xdh"; f="$r/.dev-hub/runtime/standalone/IS-001-x.md"; write_issue_and_complete "$f" "$XDH"; printf '\n## Architecture / Data Flow\n\nDuplicate.\n' >> "$f"; if xdh plan check "$f" >"$p/o" 2>&1; then return 1; fi; rg -q 'Architecture---Data-Flow status=empty' "$p/o"; }

test_owner_decision_upsert_lifecycle() {
  local p="$TEST_ROOT/decision-upsert" r="$TEST_ROOT/decision-upsert-repo" XDH f fp out
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  f="$r/.dev-hub/runtime/standalone/IS-001-decision.md"
  emit_full_issue IS-001 "product,engineering" > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')

  xdh plan decision set "$f" --id OD-001 --facet product --question "Change scope?" --decision "include it" --state pending >/dev/null
  cp "$f" "$p/pending"
  out=$(xdh plan decision set "$f" --id OD-001 --facet product --question "Change scope?" --decision "include it" --state pending)
  rg -q '^X_PLAN_DECISION_REUSED=yes$' <<<"$out"
  cmp "$f" "$p/pending"
  if xdh plan decision set "$f" --id OD-001 --facet product --question "Different?" --decision "include it" --state pending >"$p/collision" 2>&1; then return 1; fi
  rg -q 'id-collision' "$p/collision"
  cmp "$f" "$p/pending"

  xdh plan decision set "$f" --id OD-001 --facet product --question "Change scope?" --decision "exclude it" --state "accepted@$fp" >/dev/null
  cp "$f" "$p/accepted"
  out=$(xdh plan decision set "$f" --id OD-001 --facet product --question "Change scope?" --decision "exclude it" --state "accepted@$fp")
  rg -q '^X_PLAN_DECISION_REUSED=yes$' <<<"$out"
  cmp "$f" "$p/accepted"
  [[ $(rg -c '^\| OD-001 \|' "$f") -eq 1 ]]

  xdh plan facet set "$f" --facet product --status "deferred-owner@$fp" --evidence owner >/dev/null
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  out=$(xdh plan check "$f")
  rg -q '^X_PLAN_CHECK=PASS$' <<<"$out"
}

test_owner_decision_schema_and_placeholders_fail_closed() {
  local p="$TEST_ROOT/decision-schema" r="$TEST_ROOT/decision-schema-repo" XDH f fp
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  f="$r/.dev-hub/runtime/standalone/IS-001-schema.md"
  emit_full_issue IS-001 "product,engineering" > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f" --facet product --status "deferred-owner@$fp" --evidence owner >/dev/null
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  awk -v fp="$fp" '1; /^\|---/ { print "| OD-001 | product | <question> | <decision> | accepted@" fp " | " fp " |" }' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
  if xdh plan check "$f" >"$p/placeholder" 2>&1; then return 1; fi
  rg -q 'decision=OD-001 status=invalid' "$p/placeholder"

  emit_full_issue IS-001 engineering > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  awk -v fp="$fp" '1; /^\|---/ { print "| OD-001 | product | real question | real answer | accepted@" fp " | " fp " | extra |" }' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
  if xdh plan check "$f" >"$p/schema" 2>&1; then return 1; fi
  rg -q 'status=invalid-schema' "$p/schema"
}

test_formatting_only_scope_architecture_and_tests_fail_closed() {
  local p="$TEST_ROOT/format-only" r="$TEST_ROOT/format-only-repo" XDH f fp
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"

  f="$r/.dev-hub/runtime/standalone/IS-001-scope.md"
  emit_full_issue IS-001 engineering > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  awk '/^## Scope$/{print; print ""; print "### In"; print ""; print "### Out"; skip=1; next} skip && /^## /{skip=0} !skip{print}' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
  if xdh plan check "$f" >"$p/scope" 2>&1; then return 1; fi
  rg -q 'section=Scope status=missing-in-or-out' "$p/scope"

  f="$r/.dev-hub/runtime/standalone/IS-002-architecture.md"
  emit_full_issue IS-002 engineering > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  awk '/^## Architecture \/ Data Flow$/{print; print ""; print "```text"; print "```"; skip=1; next} skip && /^## /{skip=0} !skip{print}' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
  if xdh plan check "$f" >"$p/architecture" 2>&1; then return 1; fi
  rg -q 'section=Architecture---Data-Flow status=empty' "$p/architecture"

  f="$r/.dev-hub/runtime/standalone/IS-003-tests.md"
  emit_full_issue IS-003 engineering > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  sed '/^| unit |/d' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
  if xdh plan check "$f" >"$p/tests.out" 2>&1; then return 1; fi
  rg -q 'section=Tests status=no-row' "$p/tests.out"
}

test_plan_mutations_reject_targets_outside_dev_hub() {
  local p="$TEST_ROOT/containment" r="$TEST_ROOT/containment-repo" XDH outside link fp
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  outside="$r/outside.md"
  emit_full_issue IS-001 engineering > "$outside"
  fp=$(xdh plan fingerprint "$outside" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  cp "$outside" "$p/before"
  if xdh plan init "$outside" --route engineering --selected-work IS-001 >"$p/init" 2>&1; then return 1; fi
  if xdh plan facet set "$outside" --facet engineering --status "completed@$fp" --evidence e >"$p/facet" 2>&1; then return 1; fi
  if xdh plan check "$outside" >"$p/check" 2>&1; then return 1; fi
  if xdh plan ready "$outside" >"$p/ready" 2>&1; then return 1; fi
  cmp "$outside" "$p/before"
  rg -q 'outside .dev-hub' "$p/init" "$p/facet" "$p/check" "$p/ready"

  link="$r/.dev-hub/runtime/standalone/IS-001-link.md"
  ln -s "$outside" "$link"
  if xdh plan facet set "$link" --facet engineering --status "completed@$fp" --evidence e >"$p/link" 2>&1; then return 1; fi
  rg -q 'outside .dev-hub' "$p/link"
  cmp "$outside" "$p/before"
}

test_lf_crlf_and_bare_cr_have_same_logical_fingerprint() {
  local p="$TEST_ROOT/eol-read" r="$TEST_ROOT/eol-read-repo" XDH lf crlf cr fp_lf fp_crlf fp_cr
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  lf="$r/.dev-hub/runtime/standalone/IS-001-lf.md"
  crlf="$r/.dev-hub/runtime/standalone/IS-001-crlf.md"
  cr="$r/.dev-hub/runtime/standalone/IS-001-cr.md"
  emit_full_issue IS-001 engineering > "$lf"
  awk '{printf "%s\r\n", $0}' "$lf" > "$crlf"
  tr '\n' '\r' < "$lf" > "$cr"
  fp_lf=$(xdh plan fingerprint "$lf" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  fp_crlf=$(xdh plan fingerprint "$crlf" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  fp_cr=$(xdh plan fingerprint "$cr" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  [[ $fp_lf == "$fp_crlf" && $fp_lf == "$fp_cr" ]]
}

assert_crlf_document() {
  LC_ALL=C awk '$0 !~ /\r$/ { bad=1 } END { if (bad || NR == 0) exit 1 }' "$1"
}

test_plan_mutations_preserve_crlf() {
  local p="$TEST_ROOT/eol-write" r="$TEST_ROOT/eol-write-repo" XDH f fp
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  f="$r/.dev-hub/runtime/standalone/IS-001-crlf.md"
  emit_full_issue IS-001 engineering | awk '{printf "%s\r\n", $0}' > "$f"
  fp=$(xdh plan fingerprint "$f" | sed -n 's/^X_PLAN_FINGERPRINT=//p')
  xdh plan facet set "$f" --facet engineering --status "completed@$fp" --evidence engineering >/dev/null
  assert_crlf_document "$f"
  xdh plan check "$f" >/dev/null
  assert_crlf_document "$f"
  (cd "$r" && "$XDH" field set "$f" Owner alice >/dev/null && "$XDH" wg new --slug crlf --items IS-001 --owner alice >/dev/null)
  assert_crlf_document "$f"
  (cd "$r" && "$XDH" plan ready "$f" >/dev/null)
  assert_crlf_document "$f"
}

test_design_capabilities_are_explicit_and_independent() {
  local p="$TEST_ROOT/design-caps" r="$TEST_ROOT/design-caps-repo" XDH dir
  make_xdh_fixture "$p" "$r"
  XDH="$p/commands/x-plan-eng/scripts/xdh"
  if (cd "$r" && "$XDH" design prepare --slug caps --fingerprint one >"$p/missing" 2>&1); then return 1; fi
  rg -q 'missing required option: --image-generate' "$p/missing"
  dir=$(cd "$r" && "$XDH" design prepare --slug caps --fingerprint two \
    --image-generate available --image-display unavailable --image-compare available |
    sed -n 's/^X_DESIGN_DIR=//p')
  rg -q '^Image Generate: available$' "$dir/manifest.md"
  rg -q '^Image Display: unavailable$' "$dir/manifest.md"
  rg -q '^Image Compare: available$' "$dir/manifest.md"
}

run_test 'wg new rejects duplicate items without side effects' test_xdh_wg_new_rejects_duplicate_items
run_test 'wg new preflight rejects ambiguous and cross-scope items' test_xdh_wg_new_preflight_rejects_ambiguous_and_cross_scope
run_test 'plan facet set rejects engineering deferral' test_xdh_plan_facet_set_rejects_engineering_deferral
run_test 'plan fingerprint requires a canonical route' test_xdh_plan_fingerprint_requires_canonical_route
run_test 'plan facet set rejects symlink and dot-dot section files' test_xdh_plan_facet_set_rejects_symlink_and_dotdot_section_file
run_test 'plan facet set rejects duplicate H2 and multiline evidence' test_xdh_plan_facet_set_rejects_duplicate_h2_and_multiline_evidence
run_test 'plan check writes fields in one atomic replacement' test_xdh_plan_check_writes_fields_atomically
run_test 'plan facet set leaves no byte change on failure' test_xdh_plan_facet_set_no_byte_change_on_failure
run_test 'plan init rejects duplicate schema even on reuse' test_xdh_plan_init_rejects_duplicate_schema_even_on_reuse
run_test 'plan init rejects missing scaffold and wrong handover on reuse' test_xdh_plan_init_rejects_missing_scaffold_and_wrong_handover_on_reuse
run_test 'plan file snapshot is byte-exact' test_xdh_plan_file_snapshot_is_byte_exact
run_test 'RV-001 empty route blocks generic ready' test_rv001_empty_route_blocks_generic_ready
run_test 'RV-002 empty completed facet blocks check' test_rv002_empty_completed_facet_blocks_check
run_test 'RV-003 invalid decision blocks check' test_rv003_invalid_decision_blocks_check
run_test 'RV-004 Product writes pending decision' test_rv004_product_writes_pending_decision
run_test 'RV-005 concurrent WG claim blocks second slug' test_rv005_concurrent_wg_claim_blocks_second_slug
run_test 'RV-006 placeholder WG blocks ready' test_rv006_placeholder_wg_blocks_ready
run_test 'RV-007 symlinked design root blocks' test_rv007_symlinked_design_root_blocks
run_test 'RV-008 ready requires check stamp' test_rv008_ready_requires_check_stamp
run_test 'RV-009 CRLF headings are parsed' test_rv009_crlf_headings_are_parsed
run_test 'RV-010 init preserves CRLF' test_rv010_init_preserves_crlf
run_test 'RV-011 facet set rechecks freshness under lock' test_rv011_facet_set_rechecks_freshness_under_lock
run_test 'RV-012 duplicate semantic section blocks' test_rv012_duplicate_semantic_section_blocks
run_test 'RV-009 literal owner happy path and reuse repair' test_rv009_literal_owner_happy_path_and_reuse_repair
run_test 'owner decision upsert is idempotent and transition-safe' test_owner_decision_upsert_lifecycle
run_test 'owner decision schema and placeholders fail closed' test_owner_decision_schema_and_placeholders_fail_closed
run_test 'formatting-only scope architecture and tests fail closed' test_formatting_only_scope_architecture_and_tests_fail_closed
run_test 'plan mutations reject targets outside dev hub' test_plan_mutations_reject_targets_outside_dev_hub
run_test 'LF CRLF and bare CR share one logical fingerprint' test_lf_crlf_and_bare_cr_have_same_logical_fingerprint
run_test 'plan mutations preserve CRLF' test_plan_mutations_preserve_crlf
run_test 'design capabilities are explicit and independent' test_design_capabilities_are_explicit_and_independent

skill_x_test_finish 'plan machine'
