---
name: q-review
description: Provide an optional read-only second opinion on completed repository work using a different model than the implementer; start from the task and diff, expand context only when evidence requires it, and return concrete findings without editing code.
---

# q-review

Give completed work an independent second opinion. This skill is optional: ordinary work may go directly from implementation or `q-debug` to `q-ship`.

## Core rule

**The reviewer model must be different from the implementer model.**

A fresh session of the same model is not enough. A different harness running the same underlying model is not enough.

Examples:

- Codex implementation → Claude or another different model reviews.
- Claude implementation → Codex or another different model reviews.
- OpenCode implementation → choose a reviewer whose underlying model is different from the one OpenCode used.

If the implementer model is known from the current session, handoff, or task context, use it. If it is genuinely unknown and cannot be established from available context, ask only for that missing fact.

If no different reviewer model is available, stop with `SECOND_MODEL_UNAVAILABLE`. Do not substitute self-review and do not present same-model review as a second opinion.

## Role boundary

`q-review` is read-only.

- Do not edit production code, tests, docs, configuration, or generated artifacts.
- Do not create review reports, IDs, fingerprints, `.dev-hub` state, or other persistent review artifacts.
- Do not act as a required shipping gate.
- Return findings to the implementation agent. If a finding requires root-cause work, hand it to `q-debug`.

## Input

Start with the smallest useful review packet:

1. the task / requirement or agreed outcome;
2. the actual Git diff or PR diff;
3. the base/head range when relevant;
4. automated checks already run and their results, when available.

Do not preload the whole repository into the reviewer context.

## Review workflow

### 1. Establish the reviewer

Identify the implementer model, then select an available different model. Use a fresh review context with no memory of implementing the change.

Give the reviewer a read-only instruction: find concrete correctness, regression, missing-case, compatibility, or unnecessary-complexity problems in the completed change. Prefer evidence over stylistic preference.

### 2. Review diff-first

Read the complete changed content first.

Check whether the implementation actually matches the requested outcome and whether changed interfaces, error paths, state transitions, or tests contain an obvious defect.

Do not begin with a repository-wide checklist or broad architecture audit.

### 3. Expand only on evidence

When a changed symbol, interface, schema, or behavior creates a concrete question, inspect only the surrounding context needed to answer it.

Use cheap relationship evidence first when useful, including CodeGraph callers / callees / impact, Git history, existing tests, or direct consumers. Open additional source files only after that evidence identifies where to look.

Expansion is demand-driven:

```text
diff
  ↓
concrete question
  ↓
direct dependency / consumer
  ↓
only then broader context if still necessary
```

Do not sweep unrelated security, performance, concurrency, architecture, or documentation categories unless the change provides a reason to inspect them.

### 4. Verify findings

A finding must be specific enough that the implementation agent can act on it.

For each finding, establish:

- what is wrong;
- where it is;
- what behavior can fail or regress;
- the evidence supporting the claim;
- the smallest useful recommendation.

Run a targeted existing test or machine check when it can cheaply prove or disprove a finding. Do not rerun large suites merely for ceremony; `q-ship` owns final shipping verification.

Do not report speculative concerns as defects. If evidence is insufficient, label it as a question rather than a finding.

## Output

Keep the second opinion concise.

If no actionable problem is found:

```text
Second opinion: clean
Reviewer model: <model>
Reviewed: <diff/range>
Notes: <optional short observation>
Next: q-ship
```

If problems are found:

```text
Second opinion: findings
Reviewer model: <model>

1. <finding>
   Evidence: <file/symbol/test/result>
   Impact: <what can go wrong>
   Recommendation: <smallest useful correction>

Next: return to implementer; use q-debug when root cause is not yet established
```

Prioritize correctness and meaningful regressions. Do not fill the response with formatting, naming, or style comments unless they violate an explicit repository rule or materially affect maintainability.

## Handoff

- Clean second opinion → `q-ship`.
- Concrete finding with obvious correction → return to the implementation agent, then review again only if the user wants another second opinion.
- Finding whose cause is unclear → `q-debug`.

`q-review` never ships and never fixes the work itself.
