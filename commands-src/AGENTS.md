# Skill Source Instructions

These instructions apply to every skill under `commands-src/`.

## Handoff convention

Keep skills independent. Do not invent a mandatory pipeline between skills unless the skill's job genuinely requires one.

For a skill that **changes repository content** (implementation, fix, maintenance, or similar), once its work is complete and its own relevant verification passes, the normal handoff is:

```text
completed + verified work → q-ship
```

`q-ship` owns delivery. A preceding skill should not duplicate shipping ceremony, PR creation policy, or final delivery checks unless that behavior is explicitly part of the skill.

Exceptions are intentional:

- Planning skills (`q-plan`, `q-plan-*`) hand off to implementation, not directly to `q-ship`.
- `q-review` is optional and read-only. A clean second opinion may hand off to `q-ship`; findings return to the implementer or `q-debug`.
- A skill must not hand off unfinished or unverified work to `q-ship`.

When authoring or revising a skill, make the expected next step explicit near the end when a handoff exists. Keep the handoff short; do not create a separate artifact merely to record it.
