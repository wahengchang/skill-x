---
name: x-ship
description: Deliver a finished branch or Work Group with risk-adaptive gates — always run the repository's full standard test suite once, then scale review, documentation, fingerprint, and final-content checks to the actual blast radius before committing, pushing, and creating or updating exactly one PR.
---

# x-ship

Deliver finished work without turning every tiny PR into a release ceremony.

Run straight through. The request to ship is permission to make the normal
shipping decisions; stop only at the gates below. The key rule is **match the
verification cost to the change risk**. A small safe change should be quick. A
small dangerous change should still be guarded.

## When to use

Implementation is complete on a feature branch or Work Group and the user wants
the change committed, pushed, and opened or updated as a PR. Never ship feature
work from the base branch.

Standalone branch/PR work is valid. Cycle/WG artifacts improve traceability but
are not required just to open a PR.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-ship/scripts/xdh" ] && XDH="$d/x-ship/scripts/xdh" && break
done
"$XDH" paths
```

## 1. Preflight and classify before expensive gates

Identify the base, branch, diff, uncommitted work, repository shipping rules,
and any existing PR/WG.

```bash
"$XDH" pr status
```

If the current branch is the base branch, abort. Uncommitted changes are part of
the delivery unless the user explicitly excluded them.

Classify the ship as `light`, `standard`, or `guarded` from **blast radius and
failure cost, never line count alone**:

| Class | Use when | Extra gates beyond the common path |
| --- | --- | --- |
| `light` | Narrow, local, reversible change with no sensitive/public contract surface | None |
| `standard` | Ordinary behavioral code change with a bounded blast radius | One focused independent review |
| `guarded` | Security/data/public-contract/release/concurrency/architecture risk, uncertain blast radius, or policy requires strict review | Full docs audit + fingerprint-bound independent review + freeze/re-review |

Guard triggers include auth/permissions/secrets, payments, destructive or
persistent-data changes, schema/migrations/serialization compatibility, public
API/CLI/config contracts, concurrency/idempotency, install/update/release flows,
runtime-sensitive dependencies, broad architecture/refactors, or anything whose
blast radius cannot be bounded confidently.

A one-line permission or migration change can be `guarded`; a larger mechanical
cleanup can still be `light`. If classification is ambiguous, promote one level.
Read `risk-checklist.md` only when the classification is not obvious, a guard
trigger appears, or stricter policy is requested.

Record the class and one sentence of evidence for the PR/handover.

## 2. Sync the base only as needed

Fetch the base and determine whether the branch actually needs integration.
When it is already current, do not manufacture a merge commit.

```bash
git fetch origin <base>
# if behind and integration is required:
git merge origin/<base> --no-edit
```

Resolve only unambiguous conflicts. Otherwise stop and show the conflict to the
Owner.

## 3. Common verification — every class

Every ship class runs the repository's documented **full standard test suite
once** against the code that will ship. Use the project's normal full command;
if there is no single command, run the broadest documented suite. Paste real
results.

Also:

- check the work item's acceptance criteria when they exist;
- do a quick documentation-impact check: if the change makes docs/examples
  factually wrong, fix them; `no docs impact` is a valid result with a reason;
- do not perform a repository-wide documentation rewrite for a local change;
- if code or tests change after the full suite, run the full suite again for the
  new code/test tree. Documentation-only edits do not automatically invalidate
  unrelated code tests.

Within one x-ship invocation, do not repeat an unchanged expensive check merely
because another step completed. Across a fresh invocation, run the full suite
again.

## 4. Apply only the gates for the selected class

### `light`

Proceed directly after the common verification. No mandatory independent
review, fingerprint ceremony, final-content freeze, or full documentation audit.

Before continuing, re-check that no guarded trigger was discovered while
running tests or inspecting docs. If one appears, promote and continue at the
higher class.

### `standard`

Run one focused independent `x-review` against the current diff. The reviewer
must still be independent, but standard shipping does not require a separate
full documentation blast-radius audit or a fingerprint freeze ceremony.

If the review requests code changes, fix them, re-run the full suite for the new
code/test tree, and re-review the changed content. If the review reveals a guard
trigger, promote to `guarded`.

### `guarded`

Use the strict final-content path:

1. audit documentation across the real blast radius and finish factual docs
   before review;
2. fingerprint the complete working state;
3. require a fresh independent `x-review` approval bound to that fingerprint;
4. freeze reviewed content after approval;
5. run only non-modifying final checks;
6. if reviewed content changes, the approval is stale — re-run the required
   verification and independent review.

```bash
"$XDH" fingerprint --base <base>
```

If no fresh independent reviewer can be obtained, guarded shipping is
`BLOCKED`. Never downgrade a guarded change merely to get the PR open.

## 5. Commit

Group changes into coherent commits following repository conventions. Do not
invent a versioning policy the repository does not use.

For `guarded`, re-run the fingerprint after commit and verify that the committed
tree is the reviewed tree. `light` and `standard` do not pay this cost unless
repository policy explicitly requires it.

## 6. Push and upsert exactly one PR

```bash
git push -u origin <branch>
"$XDH" pr upsert --base <base> --title "<type>: <summary>" --body-file <file>
```

Update an existing open PR for the branch instead of creating a duplicate. Build
the body from this run's actual evidence.

Keep the PR body proportional too. Include at least:

- Summary
- Ship class + classification reason
- Tests
- Documentation impact
- Review (`not required for light`, reviewer result for standard/guarded)
- Remaining risks, if any

If no PR provider is available, push the branch and report the exact branch and
remote so the Owner can open it manually.

## 7. Write back when artifacts exist

If this work belongs to a WG/Cycle, update its status, PR URL, work-item progress,
and `hub.md` row. If there is no WG/Cycle, skip this step; missing planning
artifacts are not a blocker for standalone branch shipping.

```bash
"$XDH" field set <WG file> Status pr-open
"$XDH" field set <WG file> PR "<url>"
```

## Stop gates

- current branch is the base branch;
- merge conflict cannot be resolved unambiguously;
- full standard test suite fails because of this branch;
- required acceptance criteria fail;
- `standard` or `guarded` independent review returns `CHANGES_REQUESTED` and the
  fix is non-mechanical or unresolved;
- `guarded` has no fresh independent reviewer;
- destructive or irreversible decision needs Owner input;
- required credential or remote is missing.

Do **not** stop merely because a light change lacks a WG artifact, a fingerprint,
a full documentation audit, or an independent reviewer. Those are not light
requirements.

## Re-run behavior

Each new x-ship invocation redoes preflight, classification, base freshness, and
the full standard test suite. Then it reruns only the gates required by the
current class. Actions remain idempotent: reuse the branch, update the existing
PR, and do not duplicate already-published state.

Risk can only stay the same or increase during a run. If new evidence promotes a
change, continue with the higher-class gates rather than restarting from zero;
reuse results only while the relevant tree/content is unchanged.

## Handover

```markdown
## Handover

- Current state: pr-open | blocked
- Ship class: light | standard | guarded — <reason>
- Completed: <tests, review if required, commits, push, PR URL, docs impact>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: await merge, then x-housekeeping
- Target: <WG-XXX / PR / branch>
```

## Continuing

Handover is a protocol carried by the artifacts, not a runtime. The stage order
is:

```text
Discovery → Planning → Implementation / Spike Execution
  → Review when risk requires it → Debug (when needed) → Re-review when needed
  → Ship → Housekeeping (after merge)
```

When the user says `continue`, resolve the target in this order:

1. a Cycle, work item, WG, PR, or branch named explicitly in the conversation;
2. the `Next` line of the handover that was just written;
3. the stage and status recorded on the current WG document;
4. the only active WG, when there is exactly one;
5. otherwise the highest-priority `ready` WG that has not started.

Ask only when several targets remain plausible after all five, and ask once.

## Provenance

Keeps the automated final-mile and PR create-or-update behavior adapted from
gstack `ship`, while changing the local policy from one mandatory release-grade
path to risk-adaptive gates. The guarded path preserves final-content review and
documentation discipline; light and standard paths use progressive disclosure
so small safe changes do not pay for every expensive gate.
