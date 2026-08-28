---
name: issue-codex
description: Create or reuse a GitHub engineering issue in the right mode (precise change, open implementation, or exploration), dispatch exactly one Codex Cloud task, and verify the handoff; use when the user asks to delegate repository work to Codex through a GitHub issue.
---

# Issue Codex

Turn an engineering request into an executable GitHub issue and hand it to Codex Cloud using this workflow:

```text
Scope -> Materialize -> Verify -> Dispatch -> Confirm
```

Creating an issue and dispatching Codex are separate operations. Do not implement the engineering task locally, and do not present delegated work as completed.

## Modes

Every request resolves to exactly one of three modes. The mode decides the issue skeleton, the quality gate, and the dispatch prompt. Pick the mode in Scope (step 1), before writing anything.

| Mode | When | Skeleton |
|---|---|---|
| `precise` | Deliverable is a code change **and** the request specifies the implementation (explicit spec, known fix) | Goal, Context, Scope, Requirements, Acceptance criteria, Verification |
| `open-implementation` | Deliverable is a code change; outcome is clear **but** the *how* is left to Codex | Same six headings; Requirements/Acceptance state observable results and unchanged behavior, never implementation |
| `exploration` | Deliverable is an answer, decision, or report — **not** a code change (investigation, option comparison, feasibility) | Goal, Context, Scope, Questions, Expected output |

- `precise` and `open-implementation` both produce a code change; they differ only in how much the *how* is pre-decided.
- `exploration` produces a conclusion/report, not a fix. A request to *fix* a problem whose root cause is unknown is still a code change (`open-implementation`); only a request to *diagnose and report* is `exploration`.

## Invariants

- Keep one coherent task per issue. Split independent objectives into separate issues unless the user explicitly asks to keep them together.
- Create no duplicate issue when an equivalent open issue exists, and send no duplicate Codex trigger when the same task is already active or completed.
- Put no `@codex` mention in the initial issue title or body. Dispatch only with a separate, top-level issue comment beginning with `@codex`.
- Send at most one intentional Codex dispatch per task. Never retry a trigger merely because acknowledgment is delayed.
- Never claim Codex accepted or started the task without observable evidence in the issue conversation.
- Never use `@codex review`; this workflow delegates issue implementation, not pull-request review.
- Prescribe outcomes, not implementation. In `open-implementation` and `exploration` modes, do not pre-decide files, functions, algorithms, or steps unless the request explicitly names them. In `precise` mode, still prefer observable outcomes over implementation prescriptions.
- Do not fabricate repository details, commands, errors, constraints, or acceptance criteria, and do not expand the requested scope.
- Follow applicable repository `AGENTS.md` instructions over generic implementation preferences.

## 1. Scope

Resolve the exact GitHub repository, engineering objective, relevant context, constraints, and expected outcome from the conversation, connected GitHub data, and current working repository context.

- Do not guess between multiple plausible repositories. Ask the user when the target remains ambiguous after inspecting available context.
- Separate independent engineering objectives before continuing, unless the user explicitly wants one combined task.
- Inspect relevant repository documentation, implementation, tests, and applicable `AGENTS.md` files when that can resolve material unknowns. Preserve established behavior unless the request explicitly changes it.

### Resolve the mode

Classify by the requested deliverable first, then by how much implementation is prescribed:

1. Is the deliverable a code change, or an answer/decision/report? An answer, decision, comparison, feasibility finding, or report with no code change → `exploration`.
2. If it is a code change, does the request specify the implementation, or is the *how* left to Codex? Specified → `precise`; left open (including only partially specified) → `open-implementation`.

A request to *fix* a problem whose root cause is unknown is a code change (`open-implementation`), not `exploration`. If either question cannot be answered from available context, ask the user which mode they want. Never guess a mode, and never default an ambiguous request to `precise` merely to avoid asking.

### Workflow patterns

Five implementation-workflow patterns are documented under `references/` — `direct`, `exploratory`, `divergent`, `parallel`, `planner-executor`. They guide how to prepare the ticket, not how to dispatch it; the mode classifier above remains the only dispatch decision.

| Pattern | Typical mode | Dispatch note |
|---|---|---|
| direct | `precise` | — |
| exploratory | `open-implementation` (or `precise` if the user already selected an approach) | — |
| divergent | `precise` | compare-then-synthesize stays one issue; do not split alternatives into duplicate issues |
| parallel | `precise` / `open-implementation` | split into separate issues only when subgoals are independently deliverable, honoring the keep-together exception |
| planner-executor | — | role separation (planner / executor / reviewer) is not performed by this skill; do not promise it in the ticket |

If the user explicitly requires planner–executor role separation, do not silently drop it and draft a generic ticket. Stop and ask whether the user accepts a single-task Codex dispatch instead; if not, report the workflow as unsupported and do not dispatch.

Consult the matching reference while drafting the ticket.

When GitHub issue search is supported by the available tooling, search open issues in the target repository for the objective. Reuse an issue only when it represents substantially the same engineering outcome; similar components or keywords alone are insufficient. Before creating or dispatching, inspect the candidate issue and its comments for evidence of an active or completed Codex delegation for this request. If an equivalent issue is already being handled, reuse it and do not dispatch again.

Issue and comment search/read-back are prerequisites for exact-once dispatch. If the available tooling cannot search open issues and inspect their comments, stop before creating or dispatching anything. State that duplicate safety could not be established and ask the user to provide tooling that can perform those checks. Never weaken the duplicate check merely to complete the handoff.

## 2. Materialize

Draft a concise, action-oriented issue title and an executable issue body. Use the skeleton for the resolved mode, in the order shown. Keep a heading concise when little detail is available, but do not omit it or invent content; use an explicit statement such as `No additional constraints identified` when the repository and request establish that there is nothing further to add.

### `precise` and `open-implementation`

Both modes use the same six headings. The difference is the discipline applied to Requirements and Acceptance criteria:

- `precise`: describe functional behavior and engineering constraints; prefer observable outcomes over unnecessary implementation prescriptions.
- `open-implementation`: state only observable results and behavior that must remain unchanged. Do not name files, functions, algorithms, or steps — leave the *how* to Codex.

#### Goal

State the concrete outcome in one or two sentences.

#### Context

Describe the current behavior, problem, motivation, and established repository context. Include known errors, reproduction details, relevant files or modules, linked behavior, and prior implementation constraints when available.

#### Scope

State what is in scope. Also state what is out of scope when the request or repository context establishes a meaningful boundary; otherwise say that no additional out-of-scope work was identified.

#### Requirements

State functional behavior and constraints as observable outcomes. In `open-implementation` mode, do not prescribe implementation; in `precise` mode, prescribe only when the request explicitly specifies it.

#### Acceptance criteria

Use specific, verifiable completion conditions — stated as observable results, including important behavior that must remain unchanged. Do not phrase criteria as implementation steps.

#### Verification

Name established tests and checks when known. If exact commands are unknown, instruct Codex to discover them from repository documentation and applicable `AGENTS.md` files; never invent commands.

### `exploration`

Use this skeleton instead of the six headings. It describes a question to answer, not a change to build.

#### Goal

State the question to answer or the decision to make, in one or two sentences.

#### Context

Describe the current state, the motivation, and what is already known. Include relevant files, modules, data, or prior constraints when available.

#### Scope

State the boundary of the investigation. Also state what is out of scope when the request or repository context establishes a meaningful boundary.

#### Questions

List the specific questions the investigation must answer. These replace acceptance criteria; each should be answerable from evidence, not left as an open-ended wish.

#### Expected output

State what the result must be — a conclusion, a decision with options and tradeoffs, or a report. Exploration produces no code changes. If the request combines an investigation with a code change, split them into separate issues (or ask the user which deliverable to delegate); never let code ride on the exploration skeleton.

### Quality gate

Before creating anything, apply the quality gate for the resolved mode. Another engineer or coding agent must be able to answer every question.

For `precise` and `open-implementation`:

1. What outcome is required?
2. Why is the change needed?
3. What is inside the scope?
4. What important behavior must remain unchanged?
5. How will the outcome be judged achieved?

For `exploration`:

1. What question or decision does this investigation resolve?
2. Why is it needed?
3. What is inside the investigation boundary?
4. What questions must the result answer?
5. What output is expected?

Inspect the repository first if doing so can fill a material gap. Otherwise ask the user for blocking information. Prefer a smaller, precise issue over a large, vague one.

## 3. Verify

Create the issue only after the target and task pass the quality gate. The initial title and body must contain no `@codex` mention.

Immediately read the created issue back from GitHub. Treat that response—not the local draft or creation response—as the source of truth. Verify its repository, issue number, title, body, and state. If any field is wrong or the issue is not open and usable, repair it and read it back again before dispatch. If creation fails, stop and report the GitHub failure; do not attempt a dispatch.

For a reused issue, likewise read its current title, body, state, and comments. Ensure it still describes the same objective and is suitable for dispatch. Do not silently rewrite an unrelated issue.

## 4. Dispatch

Immediately before dispatch, inspect the current issue comments again. Treat any equivalent Codex implementation trigger, reaction, reply, progress message, or task link showing active or completed delegation for the same request as a reason not to trigger again.

If no equivalent trigger exists, add exactly one top-level issue comment. Use the prompt for the resolved mode, adapting it only when task-specific instructions materially improve execution. Do not duplicate the complete issue body in the comment.

For `precise` and `open-implementation`:

```text
@codex Implement this issue in this repository.

Before editing:
- Read the root AGENTS.md and any applicable nested AGENTS.md instructions.
- Inspect the existing implementation and relevant tests before deciding on the change.
- Understand the root cause or intended behavior rather than applying an unrelated workaround.

While implementing:
- Keep the diff scoped to this issue.
- Preserve existing public behavior unless the issue explicitly requires changing it.
- Reuse existing repository patterns where appropriate.
- Avoid unrelated cleanup or refactoring.

Before finishing:
- Satisfy every acceptance criterion.
- Add or update regression coverage when appropriate.
- Run the relevant tests and repository checks.
- Review the final diff for regressions and unnecessary changes.

In the final result, summarize the implementation, verification performed, and any remaining risks or blockers.
```

For `exploration`:

```text
@codex Investigate this issue in this repository.

Before investigating:
- Read the root AGENTS.md and any applicable nested AGENTS.md instructions.
- Inspect the existing implementation, data, and relevant tests to ground the findings.

While investigating:
- Keep the investigation scoped to this issue.
- Answer every question in the issue body with evidence.
- Prefer evidence from the repository over assumptions.

Before finishing:
- Produce the expected output described in the issue (conclusion, decision with options and tradeoffs, or report).
- Make no code changes. Code changes belong in a separate issue, not in an exploration.

In the final result, summarize the findings, the decision or conclusion, the evidence, and any remaining unknowns.
```

If comment creation fails, keep the issue and classify the dispatch as `not-submitted`. Do not compensate with a second issue, another kind of mention, or a retry. A later invocation must inspect the issue and comments afresh before deciding whether a new dispatch attempt is safe.

## 5. Confirm

After submitting the trigger, inspect the issue conversation for visible evidence that Codex received it, such as a Codex reaction, reply, progress message, or task link. Perform a reasonable immediate read-back, but do not repeatedly poll or submit another trigger.

Classify the handoff strictly:

- `confirmed` — visible evidence shows that Codex accepted or started the task.
- `submitted-unconfirmed` — the `@codex` trigger exists, but no acknowledgment is visible.
- `not-submitted` — the issue exists, but the trigger could not be created.

An existing equivalent dispatch with observable acknowledgment may be reported as `confirmed`; an existing trigger without acknowledgment is `submitted-unconfirmed`. Never infer confirmation from a successful comment API response alone, and never invent a reason for missing acknowledgment.

## Failure handling

- If issue creation fails, stop and report the GitHub failure.
- If read-back verification fails or reveals a mismatch, repair and re-verify the issue before dispatch; if it cannot be verified, stop without dispatching.
- If trigger creation fails, retain the verified issue and report `not-submitted`.
- If acknowledgment is absent, report `submitted-unconfirmed` without retrying or speculating.

## Output

Return this compact dispatch receipt:

```text
Repository: <owner/repo>
Issue: #<number> — <title>
Issue URL: <url>
Mode: precise | open-implementation | exploration
Issue action: created | reused
Codex dispatch: confirmed | submitted-unconfirmed | not-submitted
```

Then briefly state what Codex was asked to do, whether the handoff was confirmed, and any blocker or tooling limitation that still requires attention. Do not imply that the delegated implementation is complete.
