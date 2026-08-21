---
name: q-debug
description: Reproduce a reported software problem as cheaply as possible, confirm the real cause with evidence, fix it, rerun the original failure and relevant automated checks, then hand the verified change to q-ship; use for bugs, failing tests, regressions, errors, and production symptoms.
---

# q-debug

Find the problem, prove it, fix it, verify it, then hand off to `q-ship`.

Do not create debug plans, reports, IDs, artifacts, or `.dev-hub` state.

## Core loop

```text
problem
  ↓
find the cheapest reliable reproduction
  ↓
reproduce
  ↓
confirm root cause
  ↓
fix
  ↓
rerun the original failure
  ↓
run relevant automated checks
  ↓
q-ship
```

## 1. Start with machine evidence

Before reading large parts of the repository or doing broad reasoning, look for the cheapest existing way to make the problem visible.

Prefer, in roughly this order:

1. an already failing automated test;
2. the repository's documented test command for the affected area;
3. an existing reproduction script or fixture;
4. build, typecheck, lint, or other machine checks that expose the symptom;
5. the smallest direct reproduction command or scenario.

Use the repository's own documented commands and conventions. Do not invent a new validation workflow when the project already has one.

If a command gives a useful failure, work from that output. Spend tokens reading code only where the machine evidence points.

## 2. Reproduce first whenever possible

If the problem is reproducible, reproduce it before editing anything and keep the exact failing command or scenario as the primary verification target.

If it is not yet reproducible:

- inspect the actual error, logs, stack trace, inputs, environment, and recent relevant changes;
- compare working and failing states when available;
- add temporary logging or assertions only when they materially help expose the failure;
- reduce the case until the failure becomes deterministic if practical.

Do not guess-fix an unconfirmed problem merely because one explanation sounds plausible.

A full reproduction is preferred, but a fix may proceed without one when independent evidence is strong enough to confirm the cause. State what evidence established it.

If neither reproduction nor sufficient evidence can be obtained, stop and report what is known and what remains unknown rather than making speculative edits.

## 3. Confirm the cause before fixing

Trace from the observed failure to the smallest cause that explains it.

Use targeted repository inspection, Git history, and CodeGraph when callers, callees, or blast radius would reduce unnecessary file reading.

Form a concrete hypothesis only when needed, then test it against evidence. The goal is not to write a debugging essay; it is to know why the failure occurs before changing behavior.

Prefer the smallest fix that removes the confirmed cause. Avoid unrelated refactors while debugging.

## 4. Verify cheaply and mechanically

After the fix:

1. rerun the exact test, command, or scenario that reproduced the failure;
2. confirm the original symptom is gone;
3. run the repository's relevant automated tests/checks for the affected area;
4. run broader checks only when the blast radius or repository policy requires them.

If the repository already has a regression test that failed, fixing it is enough. If a durable automated regression test is easy and appropriate, add one. Do not manufacture a meaningless unit test for failures that are better verified by an existing integration, browser, environment, or system-level check.

If verification fails, stay in `q-debug`; do not hand off unfinished work.

## 5. Keep token cost proportional to uncertainty

Default to low-token evidence before high-token exploration:

```text
test / command output
  → targeted search or CodeGraph
  → necessary source files
  → deeper reasoning only if still unresolved
```

Do not scan the whole repository, restate obvious logs, or produce long analysis when a failing command and a few relevant files are enough.

## Handoff

When the original failure is fixed and the relevant automated checks pass, summarize only what `q-ship` needs:

- root cause;
- fix made;
- original reproduction now passing;
- relevant automated checks run and their result;
- any remaining risk or limitation.

Then hand off to `q-ship`.
