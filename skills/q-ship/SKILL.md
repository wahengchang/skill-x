---
name: q-ship
description: Deliver completed and verified repository work by checking the final diff and Git state, reusing or running the repository's normal machine verification, committing, pushing, and creating or updating exactly one pull request; use when implementation or debugging is finished and ready to ship.
---

# q-ship

Turn finished work into one clean pull request. `q-ship` owns delivery; it does not redo planning, debugging, or optional review.

## Instructions

1. Inspect the actual Git state before changing anything:
   - current branch and base branch;
   - staged, unstaged, and untracked changes;
   - the final diff to be shipped;
   - repository instructions for verification, commits, and pull requests;
   - whether this branch already has an open PR.

   If the worktree mixes unrelated changes and the intended ship set cannot be determined from context, ask one focused question. Never silently include unrelated work.

2. Ensure the work is on a feature branch.
   - If already on a non-base branch, keep it.
   - If the work is uncommitted on the base branch, create a descriptive feature branch and continue with the existing working tree.
   - If feature commits were already made directly on the base branch, stop and report the state instead of rewriting or moving published history without explicit instruction.

3. Establish valid machine verification for the final content.
   - Use the repository's documented normal verification for this kind of change.
   - Reuse a recent successful result from the current work/handoff when the verified code/test tree has not changed and repository policy does not require a fresh shipping run.
   - Otherwise run the relevant test, build, typecheck, lint, or documented suite now.
   - Prefer the normal scoped verification; do not automatically run the heaviest suite unless the repository rules or blast radius require it.

   If code or tests change after the verified result, the old result is stale; rerun the affected verification before shipping.

4. If verification fails, do not ship.
   - Fix only an obvious shipping mistake when the correction is mechanical and clearly inside the completed work.
   - Otherwise return the failure to the implementation agent.
   - If the cause is not established and needs debugging, hand off to `q-debug`.

5. Do a short final diff check after verification. Confirm the diff matches the requested work, contains no accidental generated files, secrets, debug leftovers, or unrelated edits, and does not make nearby documentation obviously false. Do not turn this into a second review or repository-wide audit. `q-review` remains optional and must never be invoked automatically by `q-ship`.

6. Commit the intended changes using the repository's conventions. Keep commits coherent and proportional to the work. Do not invent a release/versioning policy the repository does not use.

7. Push the branch to its configured remote. If credentials or the remote are unavailable, stop with the exact blocker; do not claim delivery succeeded.

8. Create or update exactly one pull request for the branch.
   - Reuse an existing open PR instead of creating a duplicate.
   - Use the repository's normal base branch unless the user specified another target.
   - Keep the title concise and outcome-focused.
   - Keep the body proportional to the change and include at least:
     - what changed;
     - verification run or reused, with result;
     - any meaningful remaining risk or limitation.

9. Confirm the PR exists and points at the branch/head that contains the final shipped commit. Do not wait for optional review to call shipping complete unless repository policy explicitly makes it required.

## Boundaries

- Do not call `q-review` automatically. It is an optional different-model second opinion chosen before or after shipping when the user wants it.
- Do not create Cycle, WG, fingerprint, ship artifact, or `.dev-hub` delivery state.
- Do not rerun expensive checks only for ceremony when a still-valid machine result already proves the same final content.
- Do not force-push, rewrite shared history, resolve ambiguous merge conflicts, or make destructive release decisions without explicit instruction.
- Do not merge the PR. Shipping ends when the branch is pushed and the PR is created or updated unless the user explicitly asks for merge as a separate action.
- Do not run `q-housekeeping` before the PR is merged. The shipped branch and its worktree remain active delivery state until merge.

## Handoff

On success, return a short delivery handoff:

```text
State: shipped
PR: <url>
Verification: <command/result or reused evidence>
Remaining risk: none | <short note>
Next: await merge, then q-housekeeping
```

Treat `q-housekeeping` as the optional post-merge handoff for removing finished local branches, worktrees, and stale worktree metadata. Mention the handoff; do not invoke it automatically or imply that cleanup is safe before merge.

If blocked, return:

```text
State: blocked
Blocker: <exact reason>
Verification: <last useful result>
Next: return to implementer | q-debug
```

Never hand off unfinished or unverified work as shipped.
