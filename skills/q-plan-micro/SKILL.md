---
name: q-plan-micro
description: Produce the smallest useful implementation plan for a clear, local, low-risk change already classified as micro by q-plan; keep planning brief and avoid ceremony.
---

# q-plan-micro

Plan a micro change quickly. Do not turn an obvious local change into a design exercise.

## Inputs

Receive the original request and the active hub path from `q-plan`:

```text
.dev-hub/active/<slug>/hub.md
```

The `## Understanding` section is the agreed scope. Treat it as authoritative unless repository evidence proves the classification wrong.

## Workflow

1. Read the agreed understanding.
2. Inspect only the directly relevant code, existing pattern, and nearest tests.
3. Confirm the change is still local, obvious, reversible, and low risk.
4. If not, promote once to `q-plan-scoped` or `q-plan-complex`, update `Complexity` and `Route`, and hand off.
5. Otherwise write the minimum plan needed for another agent to implement correctly.

Do not interview the user. If the requirement itself is no longer understood, hand back to `q-plan` with the exact unresolved question.

## Output

Update the same `hub.md`; create no other planning artifact.

Keep it compact:

```markdown
## Plan

- Change: <what to change and where>
- Keep: <behavior that must remain unchanged, if relevant>
- Verify: <smallest reliable check>

## Handoff

- Ready: yes
- Next: implement
```

Use file/symbol names when repository inspection established them. Do not invent exact files just to make the plan look concrete.

A micro plan should normally fit on one screen. No milestones, architecture essay, risk matrix, owner fields, fingerprints, work groups, or task IDs.
