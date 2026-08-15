---
name: x-review
description: Run an independent pre-landing review of a final diff through a different agent than the one that implemented it, produce evidence-backed findings bound to a content fingerprint, and drive the review to fix to re-review loop; use when changes are ready to land, when a PR or branch needs checking, or before x-ship needs an approval.
---

# x-review

Find the real risks in the final content, using an agent that did not write it.

## Hard rule: maker / checker separation

The final reviewer **must** be a different agent from the implementer, running
in a fresh session with no memory of writing the code. Self-review is not an
approval. If this host cannot start an independent agent, the verdict is
`BLOCKED_NO_INDEPENDENT_REVIEWER` — never a downgraded self-review presented as
a pass.

The reviewer is **read-only**. The moment a reviewer edits any content under
review, that agent is disqualified from approving it, and a further new agent
must perform the final review. Findings go back to the implementer; the
implementer fixes them.

## Inputs

The universal contract, plus the target branch and base, the final diff, the
`IS`/`SP`/`WG` documents, the tests, and any repository review rules.
Standalone mode accepts just a PR, a diff, and a prompt.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-review/scripts/xdh" ] && XDH="$d/x-review/scripts/xdh" && break
done
"$XDH" fingerprint --base main
```

`xdh fingerprint` snapshots the *entire* working state — committed and
uncommitted — into a throwaway Git index and reports the resulting tree. That
tree is the review target: an approval is bound to content, not to a timestamp,
and `xdh fingerprint verify --expect <fp>` answers `FRESH` or `STALE` for free.

## Reviewer selection and dispatch

Two independent reviewer paths exist, in strict preference order. Both are
fresh, read-only, and never the implementer. The orchestrator (this skill)
obtains the reviewer, feeds it the real repository and the full diff, and folds
the result into the RV artifact below. It never pastes the whole codebase into a
prompt, and it never lets a reviewer edit the content under review.

### Path 1 — preferred: a fresh read-only Codex CLI child

A new `codex` process reviews the repository itself. It is cross-model by
construction, and its session has no memory of writing the code.

The commands below use shared variables the orchestrator resolves first:
`X_MAIN_ROOT` is the repository root, `X_BASE_BRANCH` the base branch from
step 2, `X_REVIEW_TIMEOUT_SECONDS` a bounded timeout in seconds, and
`X_REVIEW_PROMPT`, `X_FINDINGS`, `X_DIAGNOSTICS` temp files for the review
prompt, findings, and diagnostics respectively.

**Preflight.** Every check must pass, or the CLI reviewer is unavailable. The
checks print no secrets.

```bash
command -v codex >/dev/null 2>&1 || { echo 'no codex executable' >&2; }

# A usable authentication signal, reported as yes/no only. Supports both the
# environment-key path and Codex's own auth file (under $CODEX_HOME, else ~/.codex).
auth_ok=no
[[ -n ${OPENAI_API_KEY:-} ]] && auth_ok=yes
auth_file="${CODEX_HOME:-$HOME/.codex}/auth.json"
if [[ $auth_ok == no && -f $auth_file ]]; then
  python3 - "$auth_file" <<'PY' && auth_ok=yes
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    ok = bool(d.get("OPENAI_API_KEY")
              or (d.get("tokens") or {}).get("access_token")
              or (d.get("tokens") or {}).get("id_token"))
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PY
fi
[[ $auth_ok == yes ]] || { echo 'no codex auth signal' >&2; }

# A bounded timeout is a hard requirement: prefer GNU timeout, then coreutils'
# gtimeout (macOS). Without either, the CLI path is unavailable.
X_TIMEOUT=
for t in timeout gtimeout; do
  command -v "$t" >/dev/null 2>&1 && { X_TIMEOUT=$t; break; }
done
[[ -n $X_TIMEOUT ]] || { echo 'no timeout utility' >&2; }
```

**Default mode — branch diff (review-oriented).** Fetch the base first (step 2
below), then run inside the repository root and keep findings separate from
diagnostics:

```bash
cd "$X_MAIN_ROOT"
"$X_TIMEOUT" "$X_REVIEW_TIMEOUT_SECONDS" codex review --base "$X_BASE_BRANCH" - \
  < "$X_REVIEW_PROMPT" > "$X_FINDINGS" 2> "$X_DIAGNOSTICS"
X_STATUS=$?
```

`codex review --base` reviews only *committed* changes against the base. When
the review target includes uncommitted changes — the fingerprint always
snapshots them, and step 2's `git diff "$DIFF_BASE"` shows them — pass
`--uncommitted` so the CLI reviewer sees the same content the orchestrator does.

**Focused mode — adversarial, security, design, or plan review (general
execution, read-only sandbox).** Same shape, but `codex exec` with an explicit
read-only sandbox and a non-persisting session:

```bash
"$X_TIMEOUT" "$X_REVIEW_TIMEOUT_SECONDS" codex exec --sandbox read-only --ephemeral \
  -C "$X_MAIN_ROOT" - < "$X_REVIEW_PROMPT" > "$X_FINDINGS" 2> "$X_DIAGNOSTICS"
X_STATUS=$?
```

The review prompt is the same in both modes: review the diff against the base,
cover every category in step 3 below, write findings as `severity`, `file:line`,
a concrete failure scenario, evidence, and a recommended resolution, and never
edit any file. `codex review` is read-only by design — the subcommand exposes no
sandbox or approval-bypass flag, so nothing in the invocation can grant write
authority. On the `exec` path the only permitted sandbox value is `read-only`.

**Failure means fall back, not retry.** Any of these marks the CLI reviewer
unavailable: `codex` missing, no auth signal, no timeout utility, a non-zero
exit (rejected/unsupported invocation or runtime auth failure), a timeout
(`X_STATUS` 124), or empty stdout (`! -s "$X_FINDINGS"`). Do not retry the CLI;
move to Path 2.

### Path 2 — fallback: a fresh independent host subagent

Dispatch one fresh, independent subagent through the host runtime running this
skill, in a session with no memory of implementation. It reviews the same real
repository and full diff, read-only, and reports in the same findings format.

If the host cannot start a fresh independent subagent either, do not silently
downgrade to self-review: record `BLOCKED_NO_INDEPENDENT_REVIEWER` and stop.

### Normalizing findings and recording provenance

Both paths produce findings the orchestrator normalizes into the RV structure
(step 4): severity, `file:line`, concrete failure scenario, evidence, and a
recommended resolution. Record reviewer provenance on the RV artifact —
reviewer type (`codex-cli` or `host-subagent`), model, and review mode — so the
report identifies who reviewed how. A missing severity token such as `[P1]`
never implies approval: apply the existing verdict contract to every verified
actionable finding.

### Re-review

After the implementer fixes findings, recompute the fingerprint. The prior
approval is stale, and an independent review runs again through the same
CLI-first dispatch — never a self-review.

## Required workflow

### 1. Record identity and target

```bash
"$XDH" fingerprint --base <base>
"$XDH" artifact new --kind RV --target "<WG-XXX / branch>" --base <base> \
  --implementer "<agent-id>" --reviewer "<reviewer-id>" \
  --reviewer-type "<codex-cli|host-subagent>" --reviewer-model "<model>" \
  --review-mode "<branch-diff|focused>" --independent yes \
  --fingerprint "<X_FINGERPRINT>" --tree "<X_TREE>"
```

The reviewer identity, type, model, and mode come from the dispatch step above.
If implementer and reviewer identity are the same, or no reviewer path is
available, stop here with `BLOCKED_NO_INDEPENDENT_REVIEWER`. Standalone runs
pass `--dir` from `xdh runtime new --skill x-review`.

### 2. Read the whole diff, then read outside it

```bash
git fetch origin <base> --quiet
DIFF_BASE=$(git merge-base origin/<base> HEAD)
git diff "$DIFF_BASE"
```

Reading the full diff first is not optional — the most common false finding is
flagging something the diff already fixes three hunks later. Then read the
consumer code the diff does not touch; several categories below cannot be
judged from inside the diff.

### 3. Cover at least these categories

- **Correctness and data safety** — string-interpolated queries, writes that
  bypass validation, check-then-write races that should be one atomic
  conditional update, N+1 access in loops.
- **Concurrency** — read-check-write without a uniqueness constraint,
  find-or-create with no unique index, status transitions that can double-apply.
- **Security and trust boundaries** — untrusted or model-generated values
  reaching a database, a mailer, a shell, an interpreter, or an outbound
  request without validation or an allowlist; unescaped rendering of
  user-controlled data.
- **API, schema and enum completeness** — a new enum value, status, tier or
  constant must be traced through *every* consumer. Grep for its siblings, then
  read each match. This is the category that requires reading outside the diff.
- **Error paths** — what the failure branch actually does, including partial
  failure, retry, and timeout.
- **Performance** — only where the change makes it materially worse.
- **Test gaps** — missing negative paths and edge cases that mirror an existing
  happy path.
- **Plan completeness** — does the diff deliver the `IS`/`SP` scope, and only it?
- **Documentation staleness** — code changed here that a repository document
  still describes the old way.

### 4. Write findings that can be acted on

Every finding carries: severity, `file:line`, a concrete failure scenario
(inputs or state → wrong outcome), the evidence, and a recommended resolution.

Verify your claims before writing them:

- "This is safe" → cite the line that makes it safe.
- "Handled elsewhere" → read that code and cite it.
- "Tests cover this" → name the test.
- Never "probably" or "likely". Verify, or record it as unverified.

"Looks fine" is not a finding. Nothing is flagged unless it is a real problem.

### 5. Close the loop

- `CHANGES_REQUESTED` → hand the findings to the original implementer. If the
  cause of a defect is unclear, that is `x-debug`, not guesswork.
- After any fix, recompute the fingerprint. The previous approval is stale by
  definition, and an independent agent re-reviews.
- `APPROVED` is recorded against the final fingerprint and nothing else.

## Verdicts

- `APPROVED` — bound to a stated fingerprint.
- `CHANGES_REQUESTED`
- `BLOCKED_NO_INDEPENDENT_REVIEWER`
- `BLOCKED_INSUFFICIENT_EVIDENCE`

## Outputs

- Cycle mode: `artifacts/reviews/RV-XXX.md`, plus the WG and `hub.md` status.
  Record the approved fingerprint on the WG document:
  `"$XDH" field set <WG file> "Reviewed fingerprint" "<fp>"`
- Standalone: the structured report, written where the user asked or under
  `.dev-hub/runtime/`.

## Handover

```markdown
## Handover

- Current state: review-complete | changes-requested | blocked
- Completed: <RV file, verdict, fingerprint>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: fix findings | x-debug | x-ship
- Target: <WG-XXX / branch>
```

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

Follows gstack `review` and its checklist for the finding categories and the
outside-voice pattern, and the cross-model reviewer orchestration in gstack
`scripts/resolvers/review.ts` (snapshot `d078622`, MIT). One behavior is
deliberately reversed: gstack lets the reviewer auto-fix. Here the reviewer
never edits — an approval is only worth what the separation behind it is worth.
