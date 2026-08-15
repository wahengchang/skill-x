---
name: x-review
description: Run an independent pre-landing review of a final diff through a different agent than the one that implemented it, produce evidence-backed findings bound to a content fingerprint, and drive the review to fix to re-review loop; use when changes are ready to land, when a PR or branch needs checking, or before x-ship needs an approval.
---

<!-- 此區塊由 bin/build.sh 自動加入，請勿直接修改部署版本。 -->

## 執行前更新檢查

執行本技能前，先從目前 `SKILL.md` 的實體路徑向上尋找 skill-x-starter repository，並執行其 `bin/update-check`。

- 找不到 repository 或找不到 `bin/update-check`（例如雲端 / 容器部署只複製了技能檔案，沒有腳本）：直接執行技能，不要提及更新檢查。
- `UP_TO_DATE` 或沒有輸出：直接執行技能，不要向使用者提及更新檢查。
- `UPGRADE_AVAILABLE <local> <remote>`：先用目前工具的互動詢問能力詢問使用者是否更新，不可靜默更新。
- 使用者同意：執行同一 repository 的 `bin/apply-update.sh`，成功後繼續技能。
- 使用者拒絕：執行 `bin/snooze.sh`（預設延後 7 天），再繼續技能。
- 檢查或更新失敗：不要阻擋技能；只在失敗會影響本次任務時簡短告知。


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

## Required workflow

### 1. Record identity and target

```bash
"$XDH" fingerprint --base <base>
"$XDH" artifact new --kind RV --target "<WG-XXX / branch>" --base <base> \
  --implementer "<agent-id>" --reviewer "<agent-id>" --independent yes \
  --fingerprint "<X_FINGERPRINT>" --tree "<X_TREE>"
```

If implementer and reviewer identity are the same, stop here with
`BLOCKED_NO_INDEPENDENT_REVIEWER`. Standalone runs pass `--dir` from
`xdh runtime new --skill x-review`.

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
