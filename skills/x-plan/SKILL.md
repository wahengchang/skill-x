---
name: x-plan
description: Orchestrate the planning lifecycle for registered work — resolve one scope and target, route each item through the Product → Design → DevEx → Engineering facets (Engineering mandatory, always last), and produce execution-ready Issues and Spikes bound to a deterministic planning fingerprint; use when work needs to be planned to executable depth, either from a discovery hub.md or as a single standalone requirement.
---

# x-plan

Turn work that is merely *named* into execution-ready Issues and Spikes by
routing each item through the four planning facets in order — Product, Design,
DevEx, and Engineering (Engineering always last, always mandatory) — and gating
the result behind a deterministic planning fingerprint.

`x-plan` orchestrates. It does not itself perform facet work: it resolves scope
and target, dispatches the specialist skills, and runs the machine gates. This
skill does not write product code and does not perform the final review.

## When to use

- `x-discovery` produced a `hub.md` and its candidates must become executable work.
- A single complex requirement needs a full plan, with or without a Dev Hub.

## Inputs

The universal contract — prompt, project background, repository documents,
source code and Git state — plus the discovery `hub.md` when one exists.

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

Every `<item>` below is the **path** the creating command reported as
`X_ITEM_FILE`, never the bare `IS-001`. The planning commands take a file inside
`.dev-hub/` and reject anything else.

## Facet dispatch

`references/facet-dispatch.md` is what the orchestrator reads: which skill owns
each facet, what it is allowed to write, what to hand it, and what to check when
it returns. Read it **only** from this skill's own bundled references, never
from a sibling skill path.

Do not read the facet contracts here. Each specialist bundles its own at
`references/facet-contract.md` and reads it when it runs; the orchestrator
reading them as well loaded the same content into context twice without
informing any decision the orchestrator makes.

## Required workflow

### 1. Resolve scope, target, and route

Resolve the scope and target with the ladder above. Then determine the route.

**The default route is `engineering` alone.** Product, Design, and DevEx enter
the route only when one of these is true:

- the user asked for that facet in this invocation; or
- the `hub.md` work row for this item marks that facet as needed.

Nothing else opens a facet — not the topic sounding product-shaped, not a
judgement that the work "would benefit from" design input. If you believe a
facet is genuinely required and neither trigger fired, say so and ask; do not
add it silently. The canonical form stays lowercase, comma-separated, with
Engineering mandatory and last, in the order `product,design,devex,engineering`.
Record per-item not-applicable facets so the plan is honest about what was
skipped.

When the resolved route is `engineering` alone — the ordinary case — **hand the
item to `x-plan-eng` Direct mode and stop orchestrating.** Direct mode runs the
identical machine sequence (`plan check` → `wg new --items` → `plan ready`) with
Product, Design, and DevEx `not-applicable`. Dispatching a single facet through
the orchestration layer adds a fingerprint hand-off and a second contract read
for no gain, so do not do it.

A Spike is always route `engineering` alone. The machine layer enforces it —
any other route on an `SP` document fails every planning command with
`route status=spike-requires-engineering` — so product or design questions that
surround a Spike belong on the Issue that the Spike unblocks, not on the Spike.

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

### 3. Write the shared sections, then fingerprint

The fingerprint covers the planning route, the selected work, and the item's
shared narrative: for an Issue `## Problem / Goal`, `## Scope` (both `### In`
and `### Out`) and `## Current → Desired Behavior`; for a Spike
`## Core Question`, `## Scope / Timebox`, `## Method` and `## Decision Rule`.

Those sections — and every other shared `##` section of the document — are the
orchestrator's to author. No facet can reach them: a specialist may write only
its own `## <Facet> Facet` section, and the field writer only rewrites
`- Field: value` bullets. Write them before dispatching anything, from the
material the discovery hub and the Owner have already settled.

```bash
"$XDH" plan fingerprint <item>
```

`X_PLAN_FINGERPRINT` is the anchor every facet status and every Owner Decision
is recorded at; `X_PLAN_FORMAT` (`x-plan-input-v1` for Issues,
`x-plan-input-spike-v1` for Spikes) only names the serialization that produced
it. Carry both in the session — there is no format field on the item, and
`xdh plan check` stamps `Planning input fingerprint` itself.

Once the first facet completes, treat those sections as frozen: editing one
rotates the fingerprint and stales everything anchored to the old value. See
*Re-anchoring* below for the way back.

### 4. Dispatch the facets in order

Only on a multi-facet route; the engineering-only route left for `x-plan-eng` at
step 1. Read `references/facet-dispatch.md` now and follow its dispatch section:
it carries the order, what to hand each specialist, what to verify on return,
and how Owner Decision rows are opened.

```text
Product? → Design? → DevEx? → Engineering (required)
```

`x-plan` itself performs no facet work. Re-read the fingerprint before each
dispatch — a specialist that has to guess it will guess a stale one.

### 5. Check the plan

```bash
"$XDH" plan check <item>
```

The gate reads the whole document, not just the facet fields. For an Issue it
also requires content in `## Architecture / Data Flow`,
`## Interfaces / Dependencies`, `## Failure Modes / Edge Cases / Risks`, a
numbered step in `## Implementation Order`, at least one row in `## Tests`,
**numbered** `## Acceptance Criteria` (an unchecked `- [ ]` does not count), and
every `## Definition of Ready` box ticked except `Owner/WG/branch/worktree`,
which step 6 satisfies.

`X_PLAN_CHECK=PASS` (with `X_PLAN_FINGERPRINT`) means every required facet is
complete. A `BLOCKER...` line with a non-zero exit means the plan is not ready;
resolve the blocker and re-check, do not force past it.

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

`plan ready` re-validates everything `plan check` did and then checks the
delivery target: the item's Owner matches the WG's, the WG names this item
exactly once, and the WG's branch and worktree exist, are registered, and have
that branch checked out. `wg=... status=worktree-unregistered` or
`status=branch-mismatch` means the worktree was moved or removed after `wg new`
created it — repair the worktree, do not edit the WG document to match. The item
must also not change between check and stamp: any concurrent edit aborts with
`item=changed-during-validation`.

### 8. Verify handoff

Could an implementation agent that never saw this conversation start each item
immediately? If not, the plan is not finished. Update the `hub.md` work table
with the formal item, Owner, WG, and status.

## Re-anchoring after a fingerprint change

A shared section edited after a facet completed shows up at the next check as
`BLOCKER facet=<f> status=stale expected=<new> actual=completed@<old>`. Never
force past it. `references/facet-dispatch.md` holds the re-anchoring procedure,
including `--reaffirm` for a conclusion the edit did not change, and the one
trap that has no cheap way back: an **already accepted** Owner Decision cannot
be moved to a new fingerprint.

The cheap avoidance is worth the discipline: settle the shared sections before
the first dispatch, and when an Owner decision changes one of them, edit first
and accept second.

## Owner questions

Product direction, scope, priority, and user-visible behavior go to the Owner —
batched, numbered, each with a recommended answer. Technical choices do not:
make the call and record the rationale.

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
