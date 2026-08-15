---
description: 'Debug a known failure by confirming a root-cause hypothesis with evidence before editing anything, then fix the cause, add a regression test that fails without the fix, and re-verify; use when there is an error, a failing test, a production symptom, or a review finding whose cause is not yet established.'
---

<!-- skill-x-managed-command: x-debug -->
<!-- 由 bin/build.sh 產生，請改 commands-src/x-debug/SKILL.md 後重新 build。 -->

Use the `skill` tool to load the `x-debug` skill, then follow its instructions exactly.
The skill itself is the single source of truth; do not act on any summary of it.

Arguments from the user: $ARGUMENTS

If those arguments are empty, ask the user what they want the skill to work on before continuing.
