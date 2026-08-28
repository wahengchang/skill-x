---
name: x-discovery
description: Survey a project or a bounded area, open a Dev Hub Cycle, and write a hub.md containing the module map, data flow, and a complete work table; use when the user wants everything in scope laid out and every candidate piece of work registered before any planning, implementation, review, or shipping begins.
---

# x-discovery

Open the scope, understand it, and register every piece of work that lives in it.
Discovery answers **"what work exists here?"** — never **"how do we build it?"**.

```text
Cycle                       one container for one round of inventory
├── hub.md                  the Owner-readable source of truth
├── Work Items              IS-XXX / SP-XXX     (created later by x-plan)
└── Work Groups             WG-XXX              (created later by x-plan)
```

## When to use

- A new project, an inherited system, a feature area, or a risk area has to be
  laid out completely before anyone commits to work.
- A durable, updatable pool of candidate work is needed.
- Examples: enumerate every front-end and back-end task in the login flow;
  find the components whose failure would be most expensive.

Do not use this for full engineering design of a single item (`x-plan`),
for implementation, for review, or for debugging.

## Inputs

The universal contract — a prompt, project background, repository documents,
source code and Git state. An existing Cycle may be named to update it.

## Toolkit

`scripts/xdh` sits next to this file and owns every repeatable filesystem and
Git operation, so this skill can spend its attention on judgement. Resolve it
once per session:

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-discovery/scripts/xdh" ] && XDH="$d/x-discovery/scripts/xdh" && break
done
"$XDH" paths
```

Every command answers in `KEY=value` lines. If `xdh` cannot be found (a pinned
image that copied only skill files, for instance), fall back to plain Git and
say so in the handover — never report state the helper would have produced.

## Required workflow

### 1. Open or reuse the Cycle

```bash
"$XDH" cycle new --slug "<scope-slug>" --title "<readable title>" \
  --scope "<what is being inspected>" --prompt "<one-line source of this run>"
```

`X_CYCLE_REUSED=yes` means an active Cycle for this scope already exists: update
it in place. Re-running discovery over the same scope must never fork a second
Cycle or re-register work that is already in the table.

### 2. Explore before asking

Take the mechanical survey first, then read narrowly:

```bash
"$XDH" survey ensure
```

`X_SURVEY_FILE` is a bounded, machine-derived snapshot of the project — layout,
entry points, docs, tests, DevEx commands, and the files history touches most.
Read it once. It is a cache keyed on the commit and the working tree, so
`X_SURVEY_STATE=fresh` means nothing changed since it was built and a later
stage will reuse the same file rather than re-deriving it.

`X_SURVEY_NAV` says how to answer relationship questions in this project:

- **`graph`** — a CodeGraph index is ready. Get the module map and the data flow
  from it: `codegraph callers <symbol>` and `codegraph impact <symbol>` name the
  real edges in a few hundred bytes, where reading the files that contain a
  symbol costs tens of kilobytes. The `## Code graph` section of the survey
  lists the commands.
- **`files`** — no usable index (shell/docs project, or CodeGraph absent or
  uninitialized). Read as below. This is an ordinary state, not a problem.

Then open individual files **only where a judgement actually depends on their
contents** — the entry point whose responsibility is unclear, the schema a
candidate would change, the test that proves current behavior. Cite what you
found: file paths, and line numbers when you refer to specific logic. Anything
answerable from code or docs is never an Owner question.

Scanning the tree yourself when the survey already answers the question is the
one habit this step exists to prevent. Store large intermediate evidence under
`artifacts/discovery/` in the Cycle — never paste it into the chat, and never
read a file into the conversation whole when an excerpt settles the point.

### 3. Write the four views into `hub.md`

1. **Main modules** — one line of responsibility each, with the evidence path.
2. **Relationships and data flow** — an ASCII diagram plus the parameters that
   actually cross each boundary.
3. **Submodule breakdown** — one level deeper, only where it changes decisions.
4. **Work table** — every candidate, related and scattered alike.

Pick the format that reads fastest for each block (table or ASCII), and separate
the blocks clearly. The Owner must understand the whole scope from `hub.md`
alone, without reading any runtime state.

### 4. Register candidates

One row per candidate, numbered `WK-001`, `WK-002`, …:

| Candidate | Work | Type hint | Why | Area | Risk | Priority | Status | Formal item | Owner | WG |
|---|---|---|---|---|---|---|---|---|---|---|

- **Why** is the evidence, not a restatement of the title.
- **Risk** is what breaks, and how expensively, if this is left alone.
- **Type hint** is `issue` or `spike` — a hint only; `x-plan` makes the
  formal classification.
- **Formal item / Owner / WG** stay `—` here. Discovery never creates IS/SP/WG
  documents, branches, or worktrees.

Ask for the next free number rather than guessing:

```bash
"$XDH" id next --kind WK
```

### 5. Triage every candidate

- `ready-for-planning` — enough is known to hand it to `x-plan`.
- `owner-decision` — only the Owner can settle it. Record it in the Owner
  Decisions table **with a recommended answer**.
- `no-action` — already done, duplicated, or out of scope. Say which.

### 6. Close out

Re-read `hub.md` as the Owner would. Every unknown is either evidenced,
triaged, or listed as an Owner decision — nothing is left implied.

## Question rule

Ask only about product direction, scope, priority, or an ambiguity that no
evidence can resolve. Batch the questions, number them, and attach your
recommended answer to each. Never ask about naming, ordinary engineering
choices, safe Git mechanics, or anything the repository already answers.

## Handover

End with this block, and mirror it at the end of `hub.md`:

```markdown
## Handover

- Current state: discovery-complete
- Completed: <cycle path, work table size, evidence written>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: x-plan
- Target: <Cycle name / WK IDs>
```

If nothing blocks, `continue` proceeds to `x-plan` for all
`ready-for-planning` rows.

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

