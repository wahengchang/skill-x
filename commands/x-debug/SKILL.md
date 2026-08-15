---
name: x-debug
description: Debug a known failure by confirming a root-cause hypothesis with evidence before editing anything, then fix the cause, add a regression test that fails without the fix, and re-verify; use when there is an error, a failing test, a production symptom, or a review finding whose cause is not yet established.
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


# x-debug

## Iron law

**No fix before the root cause is confirmed by evidence.**

Fixing a symptom creates whack-a-mole debugging: every unexplained fix makes the
next bug harder to find. Find the cause, then fix the cause.

## When to use

- An error, failing test, production symptom, or review finding exists, and the
  reason is not yet established.
- Not for feature planning, and not as cover for opportunistic refactoring.

## Inputs

The universal contract, plus the symptom, reproduction steps, logs or stack
trace, the review finding if one triggered this, and the affected branch or
work item.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-debug/scripts/xdh" ] && XDH="$d/x-debug/scripts/xdh" && break
done
"$XDH" artifact new --kind DBG --target "<WG-XXX / branch / symptom>"
```

Standalone runs pass `--dir` from `xdh runtime new --skill x-debug`.

## Required workflow

### 1. Gather evidence

Read the actual error, the actual stack trace, and the actual reproduction. Trace
the code path from the symptom backwards toward the possible causes. Then ask
what changed:

```bash
git log --oneline -20 -- <affected-files>
```

If it worked before, the cause is inside that diff. Reproduce it deterministically
if you can; if you cannot, gather more evidence before forming a hypothesis.

### 2. State one testable hypothesis

Write it out: **"Root cause hypothesis: …"** — a specific claim about what is
wrong and why, that some observation could falsify.

Check the common shapes first:

| Pattern | Signature | Where to look |
|---|---|---|
| Race condition | Intermittent, timing-dependent | Concurrent access to shared state |
| Null propagation | Type errors on optional values | Missing guards at a boundary |
| State corruption | Partial or inconsistent updates | Transactions, callbacks, hooks |
| Integration failure | Timeout, unexpected response | External calls, service boundaries |
| Configuration drift | Works locally, fails deployed | Env vars, flags, database state |
| Stale cache | Old data, fixed by clearing | Caches, CDN, client-side stores |

### 3. Test the hypothesis before editing

Add a temporary log line, an assertion, or a minimal experiment at the suspected
cause. Run the reproduction. Does the evidence match the prediction?

If it does not, return to step 1 and gather more evidence. **Do not guess.**

**Three-strike rule:** after three failed hypotheses, stop. Report what was
tested and what was ruled out, and escalate. Three misses usually mean the
problem is structural, not local.

Red flags that mean slow down: proposing a fix before tracing the data flow;
"quick fix for now"; each fix revealing a new problem somewhere else — that is
the wrong layer, not the wrong line.

### 4. Fix the cause

The smallest change that eliminates the confirmed cause. Fewest files, fewest
lines, no adjacent refactoring. If the fix touches more than five files, stop
and report the blast radius before continuing — a bug fix that large usually
means the root cause was mis-identified or the scope is really a redesign.

### 5. Add a regression test

The test must **fail without the fix** and **pass with it**. Prove both, and
paste the output. A regression test that passes on the unfixed code proves
nothing.

### 6. Verify

Reproduce the original scenario and confirm it is gone. Run the related tests,
and the full suite when the blast radius warrants it. Paste real output — not a
claim that it should work.

### 7. Report

Complete the `DBG-XXX` document: symptom, reproduction, hypothesis, the evidence
that confirmed it, the confirmed root cause, the fix, the regression test, the
verification output, and any remaining concern.

Status is one of:

- `DONE` — cause found, fixed, regression test added, tests pass.
- `DONE_WITH_CONCERNS` — fixed, but full verification is not possible here
  (intermittent, needs a deployed environment). Say exactly what is unverified.
- `BLOCKED` — cause not established. Escalate with what was ruled out.

## Handover

Any fix invalidates a previous approval. In a WG context the next step is
always `x-review`, never `x-ship` directly.

```markdown
## Handover

- Current state: fix-complete-review-stale | blocked
- Completed: <DBG file, root cause, regression test, verification>
- Blockers: none | <items>
- Owner decision: none | <question>
- Next: x-review
- Target: <WG-XXX / IS-XXX / branch>
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

Adapts the root-cause-first workflow, hypothesis testing, three-strike rule, and
regression-test requirement of gstack `investigate` (snapshot `d078622`, MIT),
and borrows the evidence-to-one-conclusion discipline of the Owner's Spike
prompt. The global learnings store and editor-specific scope-freeze hooks of the
upstream skill are not carried over.
