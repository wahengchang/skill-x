---
name: x-review
description: Run an independent read-only review through a different agent than the implementer, with `quick` depth for bounded ordinary changes and `full` depth for guarded or uncertain changes; escalate review depth when risk cannot be bounded.
---

# x-review

Find real defects with an independent reviewer, without making every ordinary PR
pay for a repository-wide audit.

## Hard rule: maker / checker separation

The reviewer **must** be a different agent from the implementer, in a fresh
session with no memory of writing the code. The reviewer is read-only. If it
edits reviewed content, it cannot approve that content.

If no independent reviewer can be started, return
`BLOCKED_NO_INDEPENDENT_REVIEWER`; never present self-review as approval.

## Review depth

Resolve depth before expensive exploration:

| Depth | Use when | Scope |
| --- | --- | --- |
| `quick` | bounded ordinary behavior change; `x-ship` class `standard` | changed files/hunks + only direct consumers needed to validate the change |
| `full` | guarded/high-risk change, uncertain blast radius, explicit strict policy | complete diff + relevant outside-diff consumers + full checklist + fingerprint-bound approval |

`x-ship standard` dispatches `x-review --quick`.
`x-ship guarded` dispatches `x-review --full`.

For standalone review, honor an explicit depth. Otherwise start `quick` only
when the blast radius is clearly bounded; use `full` when a guard signal exists
or the scope is uncertain.

A quick review can only stay quick while its risk remains bounded. Read
`review-checklist.md` only for `full`, or when quick review finds an escalation
signal. Repository/user policy may raise the required depth, never lower it.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-review/scripts/xdh" ] && XDH="$d/x-review/scripts/xdh" && break
done
```

For `full` review, fingerprint the complete working state:

```bash
"$XDH" fingerprint --base <base>
```

Quick review does not require fingerprint ceremony unless repository policy does.
Record the base/head or equivalent reviewed range instead.

## Reviewer dispatch

Prefer a fresh read-only Codex CLI child; fall back once to a fresh independent
host subagent. Do not retry a failed reviewer path repeatedly.

### Dispatch invariants

Keep reviewer startup deterministic without making review scope broad:

- require a bounded timeout; use `timeout`, or `gtimeout` on macOS;
- check only whether Codex auth exists — `OPENAI_API_KEY` or Codex `auth.json` —
  and never print credentials;
- branch-diff review uses `codex review --base <base>`;
- when the target includes uncommitted changes, add `--uncommitted` so the
  reviewer sees the actual working content;
- constrained/focused review uses
  `codex exec --sandbox read-only --ephemeral`; never use a write-capable
  sandbox or approval bypass.

Review depth controls **exploration**, not target completeness: quick mode may
read less surrounding code, but it may not silently omit changed content.

Record reviewer provenance when creating an RV artifact:

```bash
"$XDH" artifact new --kind RV --target "<target>" --base <base> \
  --implementer "<agent-id>" --reviewer "<reviewer-id>" \
  --reviewer-type "<codex-cli|host-subagent>" \
  --reviewer-model "<model>" --review-mode "<quick|full>" \
  --independent yes
```

The review prompt must name the depth and enforce its scope.

### Quick prompt contract

Review the current change for concrete correctness/regression problems. Read all
changed hunks/files relevant to the change, then read **only direct consumers or
adjacent code needed to verify an interface, error path, or regression claim**.
Do not explore the repository broadly. Do not sweep unrelated security,
concurrency, schema, performance, or documentation categories unless the diff
contains a signal that makes one relevant.

If such a signal appears, stop broadening the quick review and report
`ESCALATE_FULL` with the reason. The orchestrator then runs `full` review instead
of letting quick mode slowly become a hidden full audit.

### Full prompt contract

Review the complete final diff, inspect relevant outside-diff consumers, and
apply `review-checklist.md`. Verify every actionable claim with evidence. Full
approval is bound to the final fingerprint.

## Workflow

### 1. Identify target and depth

Resolve base, branch/PR, implementer identity, reviewer identity, and depth.
Standalone review may operate without Cycle/WG artifacts.

If reviewer and implementer are the same identity, stop with
`BLOCKED_NO_INDEPENDENT_REVIEWER`.

### 2. Establish the review range

Fetch the base and compute the current change range.

```bash
git fetch origin <base> --quiet
DIFF_BASE=$(git merge-base origin/<base> HEAD)
git diff "$DIFF_BASE"
```

For `quick`, inspect the changed files/hunks needed to understand the change
end-to-end, then only direct consumers needed to verify concrete claims.

For `full`, read the complete diff first, then read outside it where the full
checklist requires consumer/invariant tracing.

### 3. Produce evidence-backed findings

Every finding carries:

- severity;
- `file:line`;
- concrete failure scenario (`input/state → wrong outcome`);
- evidence;
- recommended resolution.

Do not emit speculative findings. `Looks fine` is not a finding.

### 4. Escalate instead of expanding quick review

Quick review returns `ESCALATE_FULL` when it discovers security/data/public
contract/concurrency/release/architecture risk, contradictory evidence, or any
condition whose blast radius cannot be bounded with the direct review scope.

Do **not** continue reading more and more repository context under the label
`quick`. Escalation is the boundary that keeps the mode cheap and predictable.

### 5. Close the loop

`CHANGES_REQUESTED` goes back to the implementer. The reviewer remains read-only.

#### Quick re-review

After an ordinary quick-review fix, do **delta re-review**:

1. read the previous findings;
2. inspect the fix delta since that review;
3. inspect only the directly affected regression surface;
4. verify the named findings are resolved and no new local regression was added.

Do not restart from the entire PR merely because two local findings were fixed.
Promote to `full` only if the fix changes a public/sensitive contract, broadens
the architecture/blast radius, or creates uncertainty that quick scope cannot
resolve.

#### Full re-review

Any reviewed-content change invalidates a full fingerprint-bound approval. After
fixes, recompute the fingerprint and perform a fresh full independent review of
the final content.

## Verdicts

- `APPROVED` — always record `review-depth: quick|full` and the reviewed range;
  full approval also records the fingerprint.
- `CHANGES_REQUESTED`
- `ESCALATE_FULL` — quick mode only; rerun as full.
- `BLOCKED_NO_INDEPENDENT_REVIEWER`
- `BLOCKED_INSUFFICIENT_EVIDENCE`

A `quick` approval is sufficient for a standard ship but **cannot** satisfy a
`guarded` ship.

## Outputs

Record reviewer provenance (`codex-cli` or `host-subagent`), model, review depth,
reviewed range, verdict, and findings. In Cycle mode, write/update the RV artifact
and WG status. Standalone mode writes the report where requested or under the
runtime directory.

Only `full` review records the approved fingerprint on the WG document:

```bash
"$XDH" field set <WG file> "Reviewed fingerprint" "<fp>"
```

## Handover

```markdown
## Handover

- Current state: review-complete | changes-requested | escalate-full | blocked
- Review depth: quick | full
- Completed: <reviewed range, findings/verdict, fingerprint if full>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: fix findings | x-review --full | x-debug | x-ship
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

Automatic continuation stops for exactly these reasons: an Owner-only scope,
product, or priority call; a destructive or irreversible action that cannot be
judged safe; a merge conflict or test failure; a review needing non-mechanical
fixes; a root cause that evidence cannot confirm; a target that the artifacts
cannot disambiguate.
