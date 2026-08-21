---
name: q-plan-complex
description: Produce a deep but lean implementation plan for work already classified as complex by q-plan; resolve architecture and risk through repository evidence, compare real options when needed, and express execution as milestones and increments in the single hub.md.
---

# q-plan-complex

Plan complex work deeply enough to reduce implementation risk, while keeping one source of truth and avoiding framework ceremony.

## Inputs

Receive the original request and the active hub path from `q-plan`:

```text
.dev-hub/active/<slug>/hub.md
```

`## Understanding` is the agreed work. Do not reopen settled product questions without new evidence.

## Workflow

### 1. Build the system picture

Inspect only evidence relevant to this change: architecture docs, entry points, schemas, interfaces, tests, Git history, and existing patterns. Use CodeGraph first for relationship and blast-radius questions when useful, then open the few files needed to verify conclusions.

Establish:

- what already exists;
- the important boundaries and dependencies;
- what can be extended instead of duplicated;
- where failure would be expensive;
- what must remain compatible.

### 2. Resolve implementation decisions

When several approaches are genuinely plausible, compare only the realistic options. Record the selected approach and why it wins for this repository.

Make technical decisions from evidence. Do not ask the user to choose libraries, file layouts, patterns, or algorithms that the repository can decide.

If investigation reveals a missing user-level decision that changes what should be built, stop planning and hand back to `q-plan` with one focused question and a recommended answer. After alignment, resume against the same `hub.md`.

### 3. Re-check complexity

If evidence proves the work is actually bounded and low-risk, demote once to `q-plan-scoped` and update `Complexity` and `Route`. Otherwise continue. Do not bounce repeatedly between lanes.

### 4. Plan by milestones and increments

Use milestones for coherent outcomes and increments for small implementation slices. The purpose is to let a later implementation agent work on one bounded piece without loading the entire planning history.

Prefer vertical, testable increments when the system allows them. Order work by dependency, not by file type.

## Output

Update the same `hub.md`; create no additional planning documents.

A useful complex plan normally contains:

```markdown
## Current System

<only the system facts that constrain this work>

## Decisions

### <decision>
- Choice: <selected approach>
- Why: <evidence-based reason>
- Alternatives considered: <only material alternatives>

## Milestones

### M1 — <outcome>

Goal: <observable outcome>

#### Increment 1 — <bounded slice>
- Change: <what this slice adds/changes>
- Touches: <known files/modules/symbols>
- Verify: <test/check>

#### Increment 2 — <bounded slice>
...

### M2 — <outcome>
...

## Risks / Compatibility

- <only material risks, migrations, rollback, public contracts, or compatibility concerns>

## Final Verification

- <end-to-end checks proving the complete requested outcome>

## Handoff

- Ready: yes
- Next: implement one increment at a time
```

Do not pre-write production code or full test bodies. Do not decompose every five-minute action. The plan should constrain correctness and sequencing while leaving ordinary engineering judgement to the implementer.

No Cycle, WG, Issue, Spike, facet, fingerprint, owner-state, or separate decision artifact is required. `hub.md` is the planning state.
