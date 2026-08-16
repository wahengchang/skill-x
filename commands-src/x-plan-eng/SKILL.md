---
name: x-plan-eng
description: Define the engineering facet of a planning item — architecture, data flow, interfaces, failure modes, tests and acceptance — to executable depth and run the planning gate; use as the engineering specialist inside x-plan orchestration, or standalone (Direct) for engineering-only planning from a discovery hub.md or a single requirement.
---

# x-plan-eng

Own the **engineering** facet: take work that is merely named and define the
implementation until an implementer who was not part of the planning can start
without asking a single question.

This skill has two modes. **Direct mode** is the engineering-only planning path
(route `engineering`); **Engineering Facet mode** runs as the engineering
specialist inside `x-plan`. Neither mode writes product code, and neither
performs the final review.

The engineering *thinking* is identical in both; what differs is who owns the
lifecycle around it. Decide which mode you are in before the first write:

```text
user invokes this skill directly
   └─▶ Direct mode ── route `engineering`, P/D/DX = not-applicable
         item new → plan fingerprint → engineering facet → the two-phase gate
         (check → wg new → ready).  This skill owns every step.

x-plan dispatches this skill for one item
   └─▶ Engineering Facet mode ── route is whatever x-plan resolved
         read the item + the completed Product / Design / DevEx sections,
         then one single write:  plan facet set --facet engineering
         No item, no WG, no branch, no worktree, no gate — x-plan runs those.
```

Engineering is mandatory on every route and always last, so in Facet mode the
other facets' decisions are already fixed: they are constraints to satisfy, not
material to revisit.

## When to use

- `x-plan` dispatches this skill to resolve the engineering facet of one item.
- Standalone (Direct): a single complex requirement needs a full engineering
  plan, with or without a Dev Hub.

## Inputs

The universal contract — prompt, project background, repository documents,
source code and Git state.

- **Facet mode:** additionally the item's `Engineering facet` / `Engineering
  evidence` fields and the completed Product, Design, and DevEx facet sections.
- **Direct mode:** the user's requirement *is* the single work item. No
  existing `.dev-hub/active/cycle-*` is required.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-eng/scripts/xdh" ] && XDH="$d/x-plan-eng/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

## Direct mode (engineering-only planning)

Direct Engineering uses exactly route `engineering`: Product, Design, and DevEx
are `not-applicable`; Engineering is `completed@<fp>`. It runs the same machine
gates as the orchestrator but performs no facet dispatch — it is itself the
engineering facet.

### 1. Select the work

One item, several named items, or every `ready-for-planning` row. State the
selection before starting so the Owner can interrupt.

### 2. Read the repository first

Confirm the current state before proposing a change: existing patterns,
interfaces, schemas, migrations, configuration, and the tests that already
cover the area. Cite `file:line`. A question the code answers is never an Owner
question, and a plan that contradicts the code is worse than no plan.

Also challenge the scope before defining it:

- What already solves part of this? Can an existing flow be extended instead of
  duplicated?
- What is the minimum change that achieves the stated goal?
- If the plan touches more than ~8 files or adds more than ~2 new
  services/classes, treat that as a smell and say so, with a smaller
  alternative, before continuing.

### 3. Classify and create (or reuse) the item

- **`IS-XXX` (Issue)** — enough is known to define the implementation and its
  acceptance criteria.
- **`SP-XXX` (Spike)** — a technical decision cannot be made without an
  experiment, prototype, or investigation first.

```bash
"$XDH" item new --type issue --slug "<slug>" --route engineering --selected-work "WK-003" --owner "<owner>"
"$XDH" item new --type spike --slug "<slug>" --route engineering --selected-work "WK-004" --owner "<owner>"
```

Reuse is reported back as `X_ITEM_REUSED`. If a reused item is an old-format
draft (no `Planning route:` field), upgrade it explicitly and idempotently:

```bash
"$XDH" plan init <item> --route engineering --selected-work "<ids>"
```

For a reused draft with a blank or placeholder Owner, repair it before the
two-phase gate:

```bash
"$XDH" field set <item> Owner "<owner>"
```

Standalone mode needs no extra flag: with no Cycle present, planning documents
land in a shared standalone scope under `.dev-hub/`, which stays put between
invocations so re-planning the same work reuses it.

### 4. Fingerprint and store the input

```bash
"$XDH" plan fingerprint <item>
```

Store `X_PLAN_FINGERPRINT` and `X_PLAN_FORMAT` (`x-plan-input-v1` for Issues,
`x-plan-input-spike-v1` for Spikes) in the item's planning input fingerprint
field.

### 5. Define the plan to executable depth

Fill the `## Engineering Facet` section of the generated `IS`/`SP` document:

- **Problem / goal**, and who is hurt today by its absence.
- **Scope in / out** — the out list prevents the drift, so write it.
- **Current → desired behavior**, with the current side verified against code.
- **Architecture / data flow** — an ASCII diagram of boundaries, state
  transitions, and what crosses each edge.
- **Interfaces / dependencies** — real signatures, real schema, real
  request/response shapes. Close enough that the implementer makes no design
  decisions.
- **Failure modes, edge cases, security and data risks** — including what
  happens on partial failure and on retry.
- **Implementation order** — dependency-correct, each step independently valid.
- **Tests** — by layer (unit / integration / end-to-end), naming what each one
  proves, not just that tests exist.
- **Acceptance criteria** — numbered, pass/fail, no subjective language.
  "Sessions older than 30 minutes return 401 for all four roles", not
  "session handling works".
- **Definition of Ready** — every box checked before the status becomes `ready`.

A Spike answers exactly **one** decisive question. If it has two, split it:
state the question, what decision it unblocks, the method, the **decision rule**
in advance, a timebox, and require a single executable conclusion: `Do this:
<one action>. Because: <evidence>.` Never a menu of options handed back to the
executor.

### 6. Record the engineering facet

```bash
"$XDH" plan facet set <item> --facet engineering --status completed@<fp> --evidence <ref>
```

Product, Design, and DevEx stay `not-applicable` on the engineering-only route.

### 7. Run the two-phase gate

```bash
"$XDH" plan check <item>
"$XDH" wg new --slug "<slug>" --items "IS-001" --owner "<owner>"
"$XDH" plan ready <item>
```

`plan check` must report `X_PLAN_CHECK=PASS`; a `BLOCKER...` line with a
non-zero exit means the plan is not ready — resolve and re-check. `wg new`
writes the WG id back into the item; `item new --owner` or the explicit reuse
repair above assigns the item Owner. `plan ready` is the
only way a new-format item reaches `ready`: do not use the generic `field set`
to set `Status ready` on a new-format item — the machine layer rejects it and
directs you back to `xdh plan ready`.

### 8. Write back and check consistency

Update the `hub.md` work table: formal item, Owner, WG, status. Preserve every
section you did not author. Then verify: could an implementation agent that
never saw this conversation start each item immediately? If not, the plan is not
finished.

## Engineering Facet

This is the portion that runs when `x-plan` dispatches `x-plan-eng` as the
engineering specialist for one item. It must follow
`references/facet-contract.md`.

The facet reads the item's `Engineering facet` / `Engineering evidence` fields,
the completed Product / Design / DevEx facet sections (their decisions are its
constraints), and the repository, then records the engineering plan and writes
back via the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet engineering --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp>`; Engineering is never `not-applicable`, `deferred-owner`, or
`deferred-missing`. Completion records `completed@<current fingerprint>`; the
fingerprint is reported by the read-only `xdh plan fingerprint <item>`.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Owner questions

Product direction, scope, priority, and user-visible behavior go to the Owner —
batched, numbered, each with a recommended answer. Technical choices do not:
make the call and record the rationale. Ask about a technical decision only when
the alternatives are genuinely close *and* the consequences are hard to reverse.

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
`plan-eng-review` (snapshot `d078622`, MIT). There is no separate backlog or
spike skill: a Spike is the `SP-XXX` work type, defined here and executed by an
implementation agent.
