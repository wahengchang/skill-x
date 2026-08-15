---
description: 'Run an independent pre-landing review of a final diff through a different agent than the one that implemented it, produce evidence-backed findings bound to a content fingerprint, and drive the review to fix to re-review loop; use when changes are ready to land, when a PR or branch needs checking, or before x-ship needs an approval.'
---

<!-- skill-x-managed-command: x-review -->
<!-- 由 bin/build.sh 產生，請改 commands-src/x-review/SKILL.md 後重新 build。 -->

Use the `skill` tool to load the `x-review` skill, then follow its instructions exactly.
The skill itself is the single source of truth; do not act on any summary of it.

Arguments from the user: $ARGUMENTS

If those arguments are empty, ask the user what they want the skill to work on before continuing.
