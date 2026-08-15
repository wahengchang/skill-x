---
name: x-plan-eng
description: Turn registered work into fully defined Issues or Spikes with architecture, data flow, failure modes, tests and acceptance, then assign an Owner and prepare the branch and worktree so implementation can start immediately; use when work needs to be planned to executable depth, either from a discovery hub.md or as a single standalone requirement.
---

# x-plan-eng

Take work that is merely *named* and define it until an implementer who was not
part of the planning can start without asking a single question.

This skill does not write product code and does not perform the final review.

## When to use

- `x-discovery` produced a `hub.md` and its candidates must become executable work.
- A single complex requirement needs a full engineering plan, with or without a Dev Hub.

## Inputs

The universal contract — prompt, project background, repository documents,
source code and Git state.

- **Cycle mode:** additionally read `hub.md` and the named `WK-XXX` rows, or
  every row still marked `ready-for-planning`.
- **Standalone mode:** the user's requirement *is* the single work item. No
  existing `.dev-hub/active/cycle-*` is required.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-eng/scripts/xdh" ] && XDH="$d/x-plan-eng/scripts/xdh" && break
done
"$XDH" paths
```

`xdh` allocates IDs under a lock, creates documents from the shared templates,
and makes branch/worktree creation idempotent. Reuse is reported back as
`X_ITEM_REUSED` / `X_WG_REUSED` — re-running planning for the same work must
never produce `IS-002` beside an identical `IS-001`.

## Required workflow

### 1. Select the work

One item, several named items, or every `ready-for-planning` row. State the
selection before starting so the Owner can interrupt.

### 2. Read the repository first

Confirm the current state before proposing a change: existing patterns,
interfaces, schemas, migrations, configuration, and the tests that already
cover the area. Cite `file:line`. A question the code answers is never an
Owner question, and a plan that contradicts the code is worse than no plan.

Also challenge the scope before defining it:

- What already solves part of this? Can an existing flow be extended instead of
  duplicated?
- What is the minimum change that achieves the stated goal?
- If the plan touches more than ~8 files or adds more than ~2 new
  services/classes, treat that as a smell and say so, with a smaller
  alternative, before continuing.

### 3. Classify the work type

- **`IS-XXX` (Issue)** — enough is known to define the implementation and its
  acceptance criteria.
- **`SP-XXX` (Spike)** — a technical decision cannot be made without an
  experiment, prototype, or investigation first.

```bash
"$XDH" item new --type issue --slug "<slug>" --title "<title>" --source WK-003
"$XDH" item new --type spike --slug "<slug>" --title "<title>" --source WK-004
```

Standalone mode needs no extra flag: with no Cycle present, planning documents
land in a shared standalone scope under `.dev-hub/`, which stays put between
invocations so re-planning the same work reuses it. Pass `--dir <path>` only
when you deliberately want an isolated bundle — a scope that moves every run
cannot be reused, and its IDs restart from 001 each time.

### 4. Define an Issue to executable depth

Fill every section of the generated `IS-XXX` document:

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

### 5. Define a Spike to a decision

A Spike answers exactly **one** decisive question. If it has two, split it.

- State the question, and what decision it unblocks.
- State the method: what to inspect, what to prototype, what evidence to collect.
- State the **decision rule** in advance — which evidence produces which answer.
  Deciding the rule after seeing the result is how bias enters.
- Set a timebox.
- Require a single executable conclusion: `Do this: <one action>. Because:
  <evidence>.` Never a menu of options handed back to the executor.

### 6. Assign an Owner and a Work Group

Use the real agent or team roster available in this session. Never invent a
human name. Assigning an Owner creates or joins a Work Group; one work item
belongs to exactly one WG at a time, and may be reassigned.

Group into one WG only what is genuinely delivered together.

### 7. Prepare the execution environment

```bash
"$XDH" wg new --slug "<slug>" --title "<title>" --items "IS-001, SP-001" --owner "<owner>"
```

This enforces `1 WG = 1 branch = 1 worktree = 1 PR` and is safe to re-run.
Then set the status of each prepared item:

```bash
"$XDH" field set <IS file> Status ready
```

### 8. Write back and check consistency

Update the `hub.md` work table: formal item, Owner, WG, status. Preserve every
section you did not author.

Then verify: could an implementation agent that never saw this conversation
start each item immediately? If not, the plan is not finished.

## Owner questions

Product direction, scope, priority, and user-visible behavior go to the Owner —
batched, numbered, each with a recommended answer. Technical choices do not:
make the call and record the rationale. Ask about a technical decision only when
the alternatives are genuinely close *and* the consequences are hard to reverse.

## Handover

```markdown
## Handover

- Current state: planning-complete
- Completed: <IS/SP/WG files, branch, worktree>
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
Discovery → Engineering Planning → Implementation / Spike Execution
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
