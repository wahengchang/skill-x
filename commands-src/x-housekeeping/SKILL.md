---
name: x-housekeeping
description: Remove finished worktrees, integrated local branches and stale runtime scratch after proving each is safe, and compact a completed Cycle into one short committed log; use after a PR merges, when a Cycle is finished, or when the repository has accumulated leftover .dev-hub execution state.
---

# x-housekeeping

Delete only what is provably finished. Everything else is reported, not touched.

## When to use

- A PR merged and its Work Group branch and worktree are no longer needed.
- Every work item in a Cycle has reached a terminal state and the Cycle should
  be closed with a permanent log.
- `.dev-hub/runtime/` scratch, orphaned worktree metadata, or finished Cycle
  `tmp/` has accumulated.

## Inputs

The universal contract, plus Git worktree/branch/PR state and the Cycle and WG
documents. `--dry-run` is always available; without it, items proven safe are
removed automatically.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-housekeeping/scripts/xdh" ] && XDH="$d/x-housekeeping/scripts/xdh" && break
done
"$XDH" clean scan
```

Classification and deletion are separate commands so the reasoning is always
inspectable before anything is destroyed.

## Safety gates

Never remove:

- a worktree with uncommitted changes;
- commits that are not pushed or not integrated into the base branch;
- an active or unmerged branch;
- anything belonging to a work item or WG whose state is uncertain;
- a remote branch, unless the Owner explicitly asks.

`xdh clean apply` re-checks each item immediately before deleting it, deletes
local branches with `git branch -d` only, and never uses `-D` or
`worktree remove --force`. If a check cannot be made, the item is not safe.

## Required workflow

### 1. Scan and classify

```bash
"$XDH" clean scan
```

Each line is `ITEM<TAB><class><TAB><kind><TAB><path><TAB><detail>`. The fields are
tab-separated because a repository path may contain spaces; split these records
on tabs, never on whitespace.

- `SAFE` — clean worktree on an integrated branch, integrated local branch,
  expired runtime scratch, finished Cycle `tmp/`.
- `DIRTY` — uncommitted changes present.
- `UNMERGED` — commits that do not exist on the base branch.
- `ACTIVE` — still in use, too recent, or `holds-live-work`: a runtime
  directory containing a work item or Work Group that has not reached a
  terminal status is live planning state, whatever its age.
- `ORPHAN` — Git metadata pointing at a path that no longer exists.

Report the classification before acting. If any `UNMERGED` item exists, say what
it is: an unmerged branch is usually work in progress, not garbage.

### 2. Apply

```bash
"$XDH" clean apply --dry-run   # show the plan
"$XDH" clean apply             # act on SAFE items only
```

Worktrees go through `git worktree remove`; `git worktree prune` runs afterwards
to clear leftover metadata, never as a substitute for a proper removal. A branch
that was checked out by a worktree becomes removable only on the next pass — run
`apply` a second time after removing worktrees.

### 3. Cycle closure gate

```bash
"$XDH" cycle check --cycle <cycle>
```

A Cycle may close only when every work item is `done`, `cancelled` or
`deferred`, every WG is merged or closed, and no worktree remains. Blockers are
printed as `BLOCKER` lines — resolve them or report them; do not force past
them. `--force` exists for the case where the Owner has explicitly accepted the
blockers, and its use must be stated.

### 4. Compact the Cycle

```bash
"$XDH" cycle close --cycle <cycle> \
  --summary "<one sentence describing what this Cycle produced>" \
  --status completed \
  --decisions "<only the decisions worth keeping>"
```

This writes `.dev-hub/logs/<cycle>.md` and removes the active Cycle directory.
The log is short on purpose: one sentence of summary, the terminal state of each
item and WG, the branches and PRs, and only durable decisions or learnings. It
is the part that survives, so it is the only part that has to be readable in six
months.

### 5. Commit the log

`.dev-hub/logs/` is tracked; `active/`, `worktrees/` and `runtime/` are not.
Commit the new log together with any cleanup metadata, and nothing else.

## Handover

Report three lists — removed, kept, blocked — and why each blocked item was
kept.

```markdown
## Handover

- Current state: housekeeping-complete | cycle-closed | blocked
- Completed: <removed items, cycle log path, commit>
- Blockers: none | <unmerged branches, dirty worktrees, open PRs>
- Owner decision: none | <question>
- Next: <wait for PR #N to merge | x-discovery for the next cycle>
- Target: <Cycle / WG>
```

If an unmerged PR is still open, the recommended next step is finishing that PR
— never forcing the cleanup through.

## Continuing

Handover is a protocol carried by the artifacts, not a runtime. The stage order is:

```text
Discovery → Engineering Planning → Implementation / Spike Execution
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

## Provenance

Implements the Owner's Cycle-compaction and lifecycle decisions, with safe Git
worktree removal semantics and the project-local path awareness of gstack
`bin/gstack-paths` (snapshot `d078622`, MIT). No global state directory is used:
everything this skill can delete lives inside the repository.
