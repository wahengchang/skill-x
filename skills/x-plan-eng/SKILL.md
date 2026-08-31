---
name: x-plan-eng
description: Define the engineering facet of a planning item — architecture, data flow, interfaces, failure modes, tests and acceptance — to executable depth and run the planning gate; use as the engineering specialist inside x-plan orchestration, or standalone (Direct) when the work needs no product, design, or DevEx decision and only its engineering plan is missing. Work that does need those facets goes to x-plan, which routes and dispatches instead.
---

# x-plan-eng

Own the **engineering** facet: take work that is merely named and define the
implementation until an implementer who was not part of the planning can start
without asking a single question.

This skill has two modes. **Direct mode** is the engineering-only planning path
(route `engineering`); **Engineering Facet mode** runs as the engineering
specialist inside `x-plan`. Neither mode writes product code, and neither
performs the final review.

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

Every `<item>` below is the **path** the creating command reported as
`X_ITEM_FILE`, never the bare `IS-001`. The planning commands take a file inside
`.dev-hub/` and reject anything else.

## Direct mode (engineering-only planning)

Direct Engineering uses exactly route `engineering`: Product, Design, and DevEx
are `not-applicable`; Engineering is `completed@<fp>`. It runs the same machine
gates as the orchestrator but performs no facet dispatch — it is itself the
engineering facet.

### 1. Select the work

One item, several named items, or every `ready-for-planning` row. State the
selection before starting so the Owner can interrupt.

### 2. Read the repository first

Start from the shared survey, not from a fresh scan:

```bash
"$XDH" survey ensure
```

`X_SURVEY_FILE` is the same bounded snapshot `x-discovery` uses — layout, entry
points, docs, tests, DevEx commands, change hotspots. When discovery already ran
in this repository the file is still valid (`X_SURVEY_STATE=fresh`) and costs one
read; the command rebuilds only when the commit or the working tree moved.

Then confirm the current state **of the area this item touches** — existing
patterns, interfaces, schemas, migrations, configuration, and the tests that
already cover it. Cite `file:line`. A question the code answers is never an
Owner question, and a plan that contradicts the code is worse than no plan.

When `X_SURVEY_NAV=graph`, ask the index for relationships instead of reading
files to infer them — the survey's `## Code graph` section carries the commands.
Those answers tell you which few files are worth opening; they do not replace
reading the code you are about to change.

Read the area, not the project. The survey is what tells you where the area is;
re-walking the whole tree here is duplicated work, because discovery already did
it and its conclusions are in `hub.md`.

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

### 4. Write the fingerprinted sections, then fingerprint

The fingerprint covers the route, the selected work, and the item's shared
narrative: for an Issue `## Problem / Goal`, `## Scope` (both `### In` and
`### Out`) and `## Current → Desired Behavior`; for a Spike `## Core Question`,
`## Scope / Timebox`, `## Method` and `## Decision Rule`. Write those first.

```bash
"$XDH" plan fingerprint <item>
```

`X_PLAN_FINGERPRINT` is the value every facet status and Owner Decision anchors
to; `X_PLAN_FORMAT` (`x-plan-input-v1` for Issues, `x-plan-input-spike-v1` for
Spikes) only names the serialization behind it. Carry both in the session —
there is no format field on the item, and `xdh plan check` stamps
`Planning input fingerprint` itself. Editing any of those sections afterwards
rotates the fingerprint and stales the recorded facet, so finish them before
step 6.

A Spike is always route `engineering` alone; any other route on an `SP` document
fails with `route status=spike-requires-engineering`.

### 5. Define the plan to executable depth

Fill the body of the generated `IS`/`SP` document — each of these is its own
`##` section and the gate checks them one by one. The first three are the
fingerprinted sections from step 4:

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
  "session handling works". Numbered is not a style preference: the gate reads
  numbered items or checked boxes, and an unchecked `- [ ]` counts as nothing.
- **Definition of Ready** — every box ticked before `plan check`, except
  `Owner/WG/branch/worktree`, which the WG step satisfies.

On the `graph` route, three of those have a mechanical source. Use it — a
guessed blast radius is the most expensive kind of wrong:

| Section | Ask |
|---|---|
| Interfaces / dependencies | `codegraph callees <symbol>`, `codegraph node <symbol>` for the exact signature |
| Failure modes / risks | `codegraph impact <symbol> -d 2` — the real reachable set |
| Tests | `codegraph affected <changed files> -f "<glob>"`, glob from the survey |

`affected` is a **positive signal only**. It follows import edges, so it finds
tests that import the code and returns nothing for suites that exercise it
through a browser or a subprocess — and it returns that emptiness silently,
reading exactly like "no tests are affected". Never let an empty result stand as
evidence that no test is needed.

The reasoning itself — why this architecture, what was rejected, which
`file:line` the current behavior came from — goes in `## Engineering Facet`,
which step 6 records as the facet's evidence.

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

`plan ready` also verifies the delivery target: the item's Owner matches the
WG's, the WG names this item exactly once, and the WG's worktree is registered
with its branch checked out. `status=worktree-unregistered` or
`status=branch-mismatch` means the worktree moved or was removed after `wg new`
— repair the worktree, do not edit the WG document to match.

If the fingerprint rotated between step 4 and here, `plan check` reports
`facet=engineering status=stale`. Re-read the fingerprint and re-record the
facet at the new value. When the edit that rotated it does not change the
engineering conclusion — confirm that by re-reading `## Engineering Facet`, not
by assuming it — re-stamp in one command instead of re-deriving:

```bash
"$XDH" plan facet set <item> --facet engineering --status completed --reaffirm
```

Carry any accepted Owner Decision forward under a fresh OD ID — an accepted row
cannot be moved to a new fingerprint (`decision=<id> status=id-collision`).

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
