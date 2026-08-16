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

## Facet contracts

`x-plan` reads each facet contract **only** from its own bundled references, and
never from a sibling skill path or a specialist's Direct workflow:

- `references/product-facet-contract.md`
- `references/design-facet-contract.md`
- `references/devex-facet-contract.md`
- `references/engineering-facet-contract.md`

When dispatching a specialist, hand it the contract that belongs to its facet.
The running specialist then reads its own `references/facet-contract.md` — the
same canonical file, bundled separately.

## Write boundary

Every field of an `IS` / `SP` document has exactly one writer. The orchestrator
owns the lifecycle; a facet owns its own two fields and its own section, and
nothing else:

```text
IS-XXX / SP-XXX
  header ─ Owner ────────────── x-plan        field set <item> Owner
         ─ Planning route ───── x-plan        item new | plan init
         ─ Selected work ────── x-plan        item new | plan init
         ─ WG ───────────────── x-plan        wg new --items
         ─ Planning input fingerprint ─ xdh   plan check
         ─ Planning Complete ── xdh           plan check
         ─ Execution Ready ──── xdh           plan ready
         ─ Status ───────────── xdh           plan ready   (never field set)
         ─ <Facet> facet ─────┐ specialist    plan facet set --facet <facet>
         ─ <Facet> evidence ──┘
  body   ─ ## <Facet> Facet ─── specialist    plan facet set [--section-file]
         ─ ## Owner Decisions ─ x-plan        plan decision set
                                product facet may add one pending row,
                                atomically with its own blocked status
```

A facet never creates an item, a Work Group, a branch, or a worktree, never runs
the generic `field set`, and never runs `plan ready`. If a facet needs one of
those, it stops and hands back to `x-plan`.

## Required workflow

The eight steps below are one gated pipeline. The order of the last three is
load-bearing: `wg new` must happen between `plan check` and `plan ready`,
because `plan ready` re-verifies the WG, its branch, and its worktree.

```text
draft item
   │ item new | plan init          route + Selected work
   ▼
plan fingerprint ──▶ <fp>          every facet records completed@<fp>
   │
   ▼
product? ─▶ design? ─▶ devex? ─▶ engineering (mandatory, always last)
   │                                    │
   │                                    ▼
   │  fix and re-check          plan check ──BLOCKER…──▶ not ready
   └────────────────────────────────┘   │ PASS
                                        ▼  stamps Planning Complete@<fp>
                                    wg new --items       branch + worktree + WG
                                        │
                                        ▼
                                    plan ready ──▶ Status: ready
```

Any edit to a fingerprint input between `plan check` and `plan ready` changes
`<fp>`, so every `completed@<old fp>` goes stale and the gate re-opens. That is
the intended behavior, not a failure.

### 1. Resolve scope, target, and route

Resolve the scope and target with the ladder above. Then determine the route:
the ordered union of the applicable facets plus Engineering. The canonical form
is lowercase, comma-separated, with Engineering mandatory and last, in the order
`product,design,devex,engineering` (drop the facets that do not apply, never
Engineering). Record per-item not-applicable facets so the plan is honest about
what was skipped.

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

### 3. Fingerprint and store the input

```bash
"$XDH" plan fingerprint <item>
```

Store `X_PLAN_FINGERPRINT` and `X_PLAN_FORMAT` (`x-plan-input-v1` for Issues,
`x-plan-input-spike-v1` for Spikes) in the item's planning input fingerprint
field. Every facet records `completed@<this fingerprint>` so the whole plan is
bound to the same content.

The fingerprint covers the *planning input* only — what the facets were asked
to solve — never their answers:

```text
          ┌──────────────────── hashed ────────────────────┐
          │ format · route · selected-work                 │
IS-XXX ──▶│ ## Problem / Goal                              │──▶ sha256 ──▶ <fp>
          │ ## Scope                                       │
          │ ## Current → Desired Behavior                  │
          └───────────────────────────────────────────────┘
SP-XXX ──▶  same three head lines, then ## Core Question ·
            ## Scope / Timebox · ## Method · ## Decision Rule
            (a Spike's route is always exactly `engineering`)

not hashed:  <Facet> facet · <Facet> evidence · ## <Facet> Facet ·
             Owner · WG · Status
```

So one facet writing its own section never invalidates another facet's
`completed@<fp>`, while re-scoping the work invalidates all of them at once.

### 4. Dispatch the facets in order

Invoke the specialist skills sequentially, one facet at a time:

```text
Product? → Design? → DevEx? → Engineering (required)
```

`x-plan` itself performs no facet work. Each specialist records its own status
through its sole Facet-mode writer. Batch homogeneous Owner decisions into one
brief; split genuinely different questions into separate groups. A question
limit must never silently apply a default to a facet decision.

When the Owner answers a pending row, record the transition through
`xdh plan decision set` using the same OD ID and the current fingerprint.
The command is retry-safe and rejects ID collisions; never edit the table with
a generic text rewrite.

### 5. Check the plan

```bash
"$XDH" plan check <item>
```

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

### 8. Verify handoff

Could an implementation agent that never saw this conversation start each item
immediately? If not, the plan is not finished. Update the `hub.md` work table
with the formal item, Owner, WG, and status.

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

## Provenance

Merges the Owner's Kickoff/Backlog-Refinement, Spike, and Spec-Finalization
prompts with the executable-specification standards of gstack `spec` and the
architecture / data-flow / failure-mode / test discipline of gstack
`plan-eng-review` (snapshot `d078622`, MIT). The facet orchestration — Product →
Design → DevEx → Engineering, each with its own contract and sole writer — is
new to this framework; there is no separate backlog or spike skill.
