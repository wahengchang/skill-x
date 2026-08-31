---
name: q-plan-scoped
description: Produce a concise, bounded implementation plan for work already classified as scoped by q-plan; inspect the affected area, reuse established patterns, and define ordered changes plus verification without deep-planning ceremony.
---

# q-plan-scoped

Plan a bounded change to executable depth without expanding into a full design process.

## Inputs

Receive the original request and the active hub path from `q-plan`:

```text
.dev-hub/active/<slug>/hub.md
```

`## Understanding` is the agreed scope.

## Workflow

1. Inspect the relevant area of the repository: entry points, existing patterns, interfaces, and tests that actually constrain this work.
2. Use CodeGraph when callers, callees, or blast radius would materially reduce file reading.
3. Confirm that the blast radius is bounded and that no major unresolved design decision or high-risk boundary has appeared.
4. If evidence shows the lane is wrong, promote once to `q-plan-complex` (or demote to `q-plan-micro` when truly obvious), update `Complexity` and `Route`, and hand off.
5. Write a short implementation plan another agent can execute without reopening basic scope questions.

Do not interview the user. If repository investigation reveals that the agreed requirement itself is ambiguous, hand back to `q-plan` with the smallest question needed to restore shared understanding.

## Output

Update the same `hub.md`; create no other planning artifact.

Use this shape only as far as useful:

```markdown
## Current State

<the existing pattern or behavior this change builds on>

## Plan

1. <ordered implementation step>
2. <ordered implementation step>
3. <ordered implementation step>

## Affected Areas

- <file/module/symbol and why it matters>

## Verification

- <tests/checks that prove the requested behavior>
- <important unchanged behavior to re-check>

## Handoff

- Ready: yes
- Next: implement
```

Prefer 3–7 ordered steps. Name concrete files or symbols only when evidence established them. Avoid implementation pseudocode, copied function bodies, exhaustive task decomposition, architecture essays, milestone ceremony, fingerprints, and work-group state.
