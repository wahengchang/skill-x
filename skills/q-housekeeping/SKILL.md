---
name: q-housekeeping
description: Inspect and safely clean local Git branches, finished worktrees, and stale worktree metadata while preserving dirty, unmerged, active, protected, remote, or uncertain state; use when a repository needs local Git housekeeping after merged work has finished or when the user asks what can be safely removed.
---

# q-housekeeping

Reduce local Git clutter without risking unfinished work. Run it directly or as the optional post-merge handoff from `q-ship`; never make it a mandatory shipping stage.

## Instructions

1. Inspect before changing anything:
   - repository root, current branch, and worktree status;
   - the repository's default or documented base branch;
   - local branches and their upstreams;
   - all registered worktrees, including locked or prunable entries;
   - merge state relative to the verified base branch.

   Do not fetch, prune, delete, remove, reset, stash, or rewrite anything during inspection. If the base branch cannot be identified reliably, classify merge-dependent candidates as `UNKNOWN`.

2. Classify every possible cleanup target using exactly one state:

   | State | Meaning | Action |
   | --- | --- | --- |
   | `SAFE` | Finished and removable from local evidence | Offer for cleanup |
   | `DIRTY` | Contains modified, staged, or untracked work | Keep |
   | `UNMERGED` | Contains commits not merged into the verified base | Keep |
   | `ACTIVE` | Current, locked, explicitly in use, or tied to ongoing work | Keep |
   | `PROTECTED` | Base, default, release, or repository-protected branch | Keep |
   | `UNKNOWN` | Safety cannot be proved | Keep |

   Absence of recent commits, a familiar name, or a merged pull request alone does not prove that a target is safe.

3. Mark a local branch `SAFE` only when all of these are true:
   - it is not current, protected, or checked out in any worktree;
   - its tip is fully merged into the verified local base branch;
   - deleting it with normal Git safety rules would not require force;
   - repository evidence does not show that it remains active.

   Never classify a remote branch as a cleanup target. If the local base may be stale and that uncertainty changes the result, leave the branch `UNKNOWN` rather than fetching automatically.

4. Mark a worktree `SAFE` only when all of these are true:
   - it is not the main or current worktree and is not locked;
   - its tracked and untracked state is clean;
   - its branch satisfies the safe-branch conditions, or it is detached at a commit already reachable from the verified base;
   - its path still exists and repository evidence shows no ongoing use.

   Treat a missing worktree path separately as stale metadata. Confirm it with Git's worktree prune dry run; never infer it only from a missing directory listing.

5. Present one short preview before cleanup:
   - exact `SAFE` worktrees;
   - exact `SAFE` local branches;
   - exact stale metadata entries;
   - kept items grouped by state and reason.

   Ask for confirmation before the first destructive action unless the user already approved this exact target list. A general request to inspect or tidy the repository is not approval to delete an unseen list.

6. After approval, clean only the listed targets:
   - remove a safe worktree with Git's normal non-force worktree removal;
   - delete a safe local branch with Git's merged-branch deletion, never force deletion;
   - prune only stale worktree metadata confirmed by the dry run;
   - use explicit resolved paths and branch names, never broad globs.

   If normal Git safety checks reject an item, keep it and report the rejection. Do not escalate to force.

7. Reinspect the repository and confirm:
   - all kept work remains unchanged;
   - only approved targets were removed;
   - remaining worktrees are registered and valid;
   - the current worktree and branch are unchanged.

## Boundaries

- Never delete remote branches, tags, stashes, commits, files, or working-tree changes.
- Never use force deletion, hard reset, checkout-based discard, clean commands, or automatic stashing.
- Do not create cleanup commits, logs, Cycle/WG state, runtime directories, temporary repository artifacts, or `.dev-hub` content.
- Do not call `q-ship`; housekeeping changes local Git administration, not repository content.
- If any target is `DIRTY`, `UNMERGED`, `ACTIVE`, `PROTECTED`, or `UNKNOWN`, preserve it and state why.

## Output

Return only the useful result:

```text
Removed: <worktrees, local branches, stale metadata | none>
Kept: <item — state/reason>
Current: <branch and worktree>
Remaining uncertainty: none | <short note>
```
