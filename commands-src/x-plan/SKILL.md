---
name: x-plan
description: Orchestrate the planning lifecycle for registered work — resolve one scope and target, select the applicable Product / Design / DevEx facets, always finish with Engineering, and produce execution-ready Issues and Spikes bound to a deterministic planning fingerprint; use when work needs to be planned to executable depth, either from a discovery hub.md or as a single standalone requirement.
---

# x-plan

Turn work that is merely *named* into execution-ready Issues and Spikes. Select
only the planning facets that actually apply, run them in the fixed order
Product → Design → DevEx → Engineering, and gate the result behind a
deterministic planning fingerprint. Engineering is always last and always
mandatory.

`x-plan` orchestrates. It does not itself perform specialist reasoning: it
resolves scope and target, selects the route, dispatches specialists, applies
Owner-approved changes to canonical planning inputs, and runs the machine gates.
This skill does not write product code and does not perform the final review.

## When to use

- `x-discovery` produced a `hub.md` and its candidates must become executable work.
- A single complex requirement needs a full plan, with or without a Dev Hub.

## Inputs

The universal contract — prompt, project background, repository documents,
source code and Git state — plus the discovery `hub.md` when one exists.

Before asking the Owner anything, inspect the prompt, repository guidance,
existing plan, `hub.md`, existing Owner Decisions, and relevant code/config/test
evidence. Ask only when the answer cannot be established from evidence and would
change the route, scope, user-visible behavior, priority, or an irreversible
choice. For dependent questions, ask one at a time and include a recommended
answer.

## Target resolution

Resolve **exactly one scope** first, then resolve the target item(s) with this
precedence ladder (highest wins):

```text
explicit target
→ handover Target
→ items of the only active WG
→ only draft item in the only active Cycle
→ only standalone draft item
→ structured user-input capability
→ conversational question and stop
→ BLOCKED_NO_USER_INPUT_CAPABILITY
```

Scope resolution: an explicit scope or Cycle wins; if exactly one Cycle is
active, it is selected; if several Cycles are active, stop for input; otherwise
the standalone scope applies. Only `Status: draft` items are planning
candidates. Never consult mtime or global state to disambiguate, and if several
candidates remain at one rung of the ladder, ask rather than falling through to
the next rung.

An "active WG" is one whose `Status` is not terminal — the terminal WG statuses
(`merged`, `closed`, `cancelled`, `done`) are those `xdh` reports through
`x_status_is_terminal` / `X_TERMINAL_WG_STATUSES`. Never union WGs across the
Cycle and standalone scopes.

Input-capability fallback: if the host offers a structured input facility, use
it; otherwise ask a single conversational question and stop. Emit
`BLOCKED_NO_USER_INPUT_CAPABILITY` only when no later response can be obtained.

## Route selection

Route selection belongs to `x-plan`; do not dispatch every optional specialist
by default.

- **Product** applies to a new capability, a user-visible behavior change,
  unclear product scope/priority, or an external developer-facing product
  surface such as API / CLI / SDK behavior.
- **Design** applies to new or changed UI, interaction flow/state, information
  architecture, or design-system behavior.
- **DevEx** applies to the internal engineering-team journey: setup, build,
  first change, test, debug, CI/release, contributor docs, or maintainer
  workflow. Do not use DevEx as a substitute for Product on external API / CLI /
  SDK semantics.
- **Engineering** always applies and is always last.

For a batch, evaluate applicability before dispatch and use the ordered union of
the required facets. Do not invent work merely to justify a selected facet, and
do not silently drop a facet whose concern is present.

The canonical route string is lowercase, comma-separated, and ordered
`product,design,devex,engineering`, dropping facets that do not apply and never
dropping Engineering.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan/scripts/xdh" ] && XDH="$d/x-plan/scripts/xdh" && break
done
"$XDH" paths
```

`xdh` allocates IDs under a lock, creates documents from the shared templates,
and makes branch/worktree creation idempotent. Every command answers in
`KEY=value` lines. Reuse is reported back as `X_ITEM_REUSED` — re-planning the
same work must never produce `IS-002` beside an identical `IS-001`.

## Facet contracts

`x-plan` reads each facet contract **only** from its own bundled references, and
never from a sibling skill path or a specialist's Direct workflow:

- `references/product-facet-contract.md`
- `references/design-facet-contract.md`
- `references/devex-facet-contract.md`
- `references/engineering-facet-contract.md`

When dispatching a specialist, hand it the contract that belongs to its facet,
the exact item target, and the current planning fingerprint. The running
specialist then reads its own `references/facet-contract.md` — the same
canonical contract, bundled separately.

## Fingerprint discipline

The planning fingerprint is a content boundary, not a timestamp. Recompute it
before each specialist dispatch and after every edit to a fingerprinted input.
Never relabel a stale `completed@<old-fp>` status as current without rerunning
the affected reasoning.

Owner Decisions need special care. In Facet mode, specialists do not rewrite
canonical fingerprint inputs. If the Owner accepts a decision that changes
`Planning route`, `Selected work`, `## Problem / Goal`, `## Scope`, or
`## Current → Desired Behavior`, `x-plan` must:

1. apply the accepted change to the canonical item first using the host's normal
   file-editing capability;
2. recompute the fingerprint;
3. accept the existing Owner Decision at that **new** fingerprint with
   `xdh plan decision set`;
4. rerun the affected selected facets from the earliest changed concern through
   Engineering.

This prevents an accepted scope or behavior change from remaining bound to the
old planning input. A decision that does not change a fingerprinted input may be
accepted at the current fingerprint.

## Specialist availability

A missing capability inside a specialist follows that specialist's downgrade
rules; it is not the same as a missing specialist. If a selected optional
specialist (Product, Design, or DevEx) cannot run on the host, never silently
skip it. Record an Owner Decision about proceeding without that facet; after the
Owner explicitly accepts, the orchestrator may use the scoped facet writer only
to record `deferred-missing@<current-fp>` with evidence that the specialist was
unavailable. Do not synthesize the missing specialist's reasoning. Missing
Engineering is always blocking.

## Required workflow

### 1. Resolve scope, target, and route

Resolve the scope and target with the ladder above. Apply the route-selection
rules before creating or updating any planning item.

### 2. Create or reuse the item

```bash
"$XDH" item new --type issue --slug "<slug>" --route "<route>" --selected-work "<ids>" --owner "<owner>"
```

`X_ITEM_REUSED` means the item already exists. If a reused item is an old-format
draft (no `Planning route:` field), upgrade it explicitly and idempotently:

```bash
"$XDH" plan init <item> --route "<route>" --selected-work "<ids>"
```

Before continuing, repair a reused draft's Owner explicitly when it is blank or
placeholder. The orchestrator owns this header mutation; facet mode does not.

```bash
"$XDH" field set <item> Owner "<owner>"
```

### 3. Compute the current fingerprint

```bash
"$XDH" plan fingerprint <item>
```

Use `X_PLAN_FINGERPRINT` as the dispatch fingerprint and keep `X_PLAN_FORMAT`
(`x-plan-input-v1` for Issues, `x-plan-input-spike-v1` for Spikes) for
diagnostics. Do **not** manually stamp the `Planning input fingerprint` field;
`xdh plan check` refreshes that advisory field only after the plan validates.
Every completed facet records `completed@<current fingerprint>`.

### 4. Dispatch the facets in order

Invoke only the selected specialists, sequentially:

```text
Product? → Design? → DevEx? → Engineering (required)
```

Before each dispatch, recompute the fingerprint. After each return, verify that
the specialist wrote only its own facet state/evidence/section and that any
completion is bound to the current fingerprint. If canonical planning inputs
changed, treat earlier completion as stale and rerun from the earliest affected
facet; never carry a stale completion forward because the text still "looks
right".

`x-plan` itself performs no specialist reasoning. Each specialist records its
own status through the scoped Facet-mode writer. Batch homogeneous Owner
decisions into one brief; split genuinely different questions into separate
groups. A question limit must never silently apply a default to a facet
decision.

When the Owner answers a pending row, keep the same OD ID. If the answer changes
a fingerprinted input, follow **Fingerprint discipline** first; otherwise record
the transition directly through `xdh plan decision set` at the current
fingerprint. The command is retry-safe and rejects ID collisions; never edit the
decision table with a generic text rewrite.

### 5. Check the plan

```bash
"$XDH" plan check <item>
```

`X_PLAN_CHECK=PASS` (with `X_PLAN_FINGERPRINT`) means every required facet is
complete and the advisory planning fingerprint has been refreshed. A
`BLOCKER...` line with a non-zero exit means the plan is not ready; resolve the
blocker and re-check, do not force past it.

### 6. Assign the Work Group

```bash
"$XDH" wg new --slug "<slug>" --items "IS-001, SP-001" --owner "<owner>"
```

One work item belongs to exactly one WG at a time; group only what is genuinely
delivered together. The command writes the WG id back into each item; it does
not assign or repair the item's Owner.

### 7. Mark the plan ready

```bash
"$XDH" plan ready <item>
```

This is the only way a new-format item reaches `ready`. Do not use the generic
`field set` to set `Status ready` on a new-format item — the machine layer
rejects it and directs you back to `xdh plan ready`.

### 8. Verify handoff

Could an implementation agent that never saw this conversation start each item
immediately? If not, the plan is not finished. Update the `hub.md` work table
with the formal item, Owner, WG, and status.

## Owner questions

Product direction, scope, priority, and user-visible behavior go to the Owner —
batched when independent, numbered, each with a recommended answer. Technical
choices do not: make the call and record the rationale. Never ask for facts that
repository evidence can answer.

## Direct engineering entry point

`x-plan-eng` remains a second entry point for engineering-only planning. It runs
the same machine sequence with route `engineering` (Product, Design, and DevEx
are `not-applicable`, Engineering is `completed@<fp>`), the two-phase gate
`xdh plan check` → `xdh wg new --items` → `xdh plan ready`, and no facet
dispatch.

## Handover

```markdown
## Handover

- Current state: planning-complete
- Completed: <IS/SP/WG files, branch, worktree, fingerprint>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: implement IS-XXX | execute SP-XXX
- Target: <WG-XXX / branch>
```

A finished Spike writes its conclusion and evidence back into the `SP-XXX`
document and `hub.md`; any follow-up work it reveals is registered as new work.

## Continuing

Handover is a protocol carried by the artifacts, not a runtime. The stage order is:

```text
Discovery → Planning → Implementation / Spike Execution
  → Independent Review → Debug (when needed) → Independent Re-review
  → Ship → Housekeeping (after merge)
```

When the user says `continue`, resolve the target in this order:

1. a Cycle, work item, or WG named explicitly in the conversation;
2. the `Next` line of the handover that was just written;
3. the stage and status recorded on the current WG document;
4. the only active WG, when there is exactly one;
5. otherwise the highest-priority `ready` WG that has not started.

Ask only when several targets remain plausible after all five, and ask once.

Automatic continuation stops for exactly these reasons: an Owner-only scope,
product, or priority call; a destructive or irreversible action that cannot be
judged safe; a merge conflict or test failure; a review needing non-mechanical
fixes; a root cause that evidence cannot confirm; a target that the artifacts
cannot disambiguate.

## Provenance

Merges the Owner's Kickoff/Backlog-Refinement, Spike, and Spec-Finalization
prompts with the executable-specification standards of gstack `spec` and the
architecture / data-flow / failure-mode / test discipline of gstack
`plan-eng-review` (snapshot `d078622`, MIT). The facet orchestration — Product →
Design → DevEx → Engineering, each with its own contract and sole writer — is
new to this framework; there is no separate backlog or spike skill.
