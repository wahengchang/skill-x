---
name: x-ship
description: Run the final delivery gates for a branch or Work Group — sync the base, run tests and acceptance, sync documentation, obtain a fresh independent review bound to the final content, commit, push, and create or update exactly one PR; use when implementation is finished and the work is ready to be delivered.
---

# x-ship

Get finished work delivered, in one pass, without shipping anything that has not
been verified against its final content.

Run straight through. Do not ask for permission at each step — the request to
ship *is* the permission. Stop only at the gates listed below.

## When to use

Implementation is complete on a feature branch or Work Group. Never ship feature
work from the base branch.

## Inputs

The universal contract, plus the current branch and worktree, the final work
item and WG, tests and acceptance criteria, the current review status, and the
remote/PR context.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-ship/scripts/xdh" ] && XDH="$d/x-ship/scripts/xdh" && break
done
"$XDH" paths
```

## Required order

The order is the point. Documentation is finished *before* the review gate, and
nothing changes *after* it.

### 1. Preflight

Identify the base, the branch, the diff, any uncommitted work, and which WG and
PR this belongs to. If the current branch is the base branch, abort and say so.
Uncommitted changes are part of the delivery — include them, do not ask.

```bash
"$XDH" pr status
```

### 2. Sync the base

```bash
git fetch origin <base> && git merge origin/<base> --no-edit
```

Resolve only conflicts whose resolution is unambiguous. Anything else stops the
ship and is shown to the Owner.

### 3. Finish the content

- Run the tests and check the acceptance criteria of the work item. Paste real
  output.
- Sync the documentation to what actually shipped: assess the blast radius
  first, then correct README, architecture notes, API docs, examples, and
  changelog per the repository's own conventions. Factual corrections that
  follow from the diff are made directly. Narrative rewrites, philosophy, or
  removals are Owner decisions.
- Flag, but never silently auto-generate, missing documentation for new public
  surface.

### 4. Independent review gate

```bash
"$XDH" fingerprint --base <base>
```

Compare `X_FINGERPRINT` with the fingerprint recorded on the WG document. If
there is no fresh approval for *this* fingerprint, dispatch `x-review` and wait
for it. If no independent agent can be started, the result is `BLOCKED` — a
self-review is not an approval, and neither is an approval for older content.

### 5. Final verification

After approval, the content is frozen. Run the checks that do not modify files.
If anything changed after the reviewed fingerprint, the approval is stale and
step 4 runs again. "It's a trivial change" is exactly how this fails.

### 6. Commit

Group the changes into commits that each express one coherent change and each
stand on their own, so the history bisects. Follow the repository's existing
commit conventions; do not import a versioning policy this repository does not
use.

### 7. Fingerprint check

Re-run `xdh fingerprint`. The committed tree must equal the reviewed tree. If it
does not, something was changed after review — go back to step 4 rather than
pushing it.

### 8. Push and upsert exactly one PR

```bash
git push -u origin <branch>
"$XDH" pr upsert --base <base> --title "<type>: <summary>" --body-file <file>
```

`X_PR_ACTION` reports `created` or `updated`. An existing open PR for this
branch is updated — never a second PR for the same Work Group. Regenerate the
body from this run's real results rather than reusing stale text. If no PR
provider is available (`X_PR_PROVIDER=none`), print the branch and remote and
tell the Owner to open it manually; the code is pushed and safe either way.

Suggested body sections: Summary (every substantive commit appears in one of
them), Tests, Review, Documentation, Acceptance, Remaining risks.

### 9. Write back

```bash
"$XDH" field set <WG file> Status pr-open
"$XDH" field set <WG file> PR "<url>"
```

Update the work item progress and the `hub.md` row to match.

## Stop gates

- Merge conflict that cannot be resolved unambiguously.
- Test failure introduced by this branch.
- Review returned `CHANGES_REQUESTED`.
- No fresh independent reviewer available.
- A destructive or irreversible release decision.
- A required credential or remote is missing.

Everything else — commit splitting, message wording, whether to include
uncommitted work, re-running an already-successful step — is decided here, not
asked.

## Re-run behavior

Re-running means running every *verification* again: tests, acceptance,
documentation sync, fingerprint, review freshness. Only the *actions* are
idempotent — an existing push is not repeated, and an existing PR is updated
instead of duplicated. Never skip a check because an earlier run passed it.

## Handover

```markdown
## Handover

- Current state: pr-open | blocked
- Completed: <commits, push, PR URL, docs synced, reviewed fingerprint>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: await merge, then x-housekeeping
- Target: <WG-XXX / PR>
```

## Continuing

Handover is a protocol carried by the artifacts, not a runtime. The stage order is:

```text
Discovery → Planning → Implementation / Spike Execution
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

Adapts the automated final-mile, idempotent re-run, and PR create-or-update
behavior of gstack `ship`, the documentation blast-radius audit of gstack
`document-release`, and the PR body structure of `ship/sections/pr-body.md`
(snapshot `d078622`, MIT). Documentation sync is merged into this skill instead
of being separate, and upstream's VERSION/CHANGELOG queue policy, telemetry, and
credential-hook installation are not carried over.
