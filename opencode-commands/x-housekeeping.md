---
description: 'Remove finished worktrees, integrated local branches and stale runtime scratch after proving each is safe, and compact a completed Cycle into one short committed log; use after a PR merges, when a Cycle is finished, or when the repository has accumulated leftover .dev-hub execution state.'
---

<!-- skill-x-managed-command: x-housekeeping -->
<!-- 由 bin/build.sh 產生，請改 commands-src/x-housekeeping/SKILL.md 後重新 build。 -->

Use the `skill` tool to load the `x-housekeeping` skill, then follow its instructions exactly.
The skill itself is the single source of truth; do not act on any summary of it.

Arguments from the user: $ARGUMENTS

If those arguments are empty, ask the user what they want the skill to work on before continuing.
