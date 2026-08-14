---
name: issue-codex
description: Create or reuse a precise GitHub engineering issue, dispatch exactly one Codex Cloud implementation task, and verify the handoff; use when the user asks to delegate repository work to Codex through a GitHub issue.
---

# Issue Codex

Turn an engineering request into an executable GitHub issue and hand it to Codex Cloud using this workflow:

```text
Scope -> Materialize -> Verify -> Dispatch -> Confirm
```

Creating an issue and dispatching Codex are separate operations. Do not implement the engineering task locally, and do not present delegated work as completed.

## Invariants

- Keep one coherent implementation task per issue. Split independent objectives into separate issues unless the user explicitly asks to keep them together.
- Create no duplicate issue when an equivalent open issue exists, and send no duplicate Codex trigger when the same task is already active or completed.
- Put no `@codex` mention in the initial issue title or body. Dispatch only with a separate, top-level issue comment beginning with `@codex`.
- Send at most one intentional Codex dispatch per task. Never retry a trigger merely because acknowledgment is delayed.
- Never claim Codex accepted or started the task without observable evidence in the issue conversation.
- Never use `@codex review`; this workflow delegates issue implementation, not pull-request review.
- Do not fabricate repository details, commands, errors, constraints, or acceptance criteria, and do not expand the requested scope.
- Follow applicable repository `AGENTS.md` instructions over generic implementation preferences.

## 1. Scope

Resolve the exact GitHub repository, engineering objective, relevant context, constraints, and expected outcome from the conversation, connected GitHub data, and current working repository context.

- Do not guess between multiple plausible repositories. Ask the user when the target remains ambiguous after inspecting available context.
- Separate independent engineering objectives before continuing, unless the user explicitly wants one combined task.
- Inspect relevant repository documentation, implementation, tests, and applicable `AGENTS.md` files when that can resolve material unknowns. Preserve established behavior unless the request explicitly changes it.

When GitHub issue search is supported by the available tooling, search open issues in the target repository for the objective. Reuse an issue only when it represents substantially the same engineering outcome; similar components or keywords alone are insufficient. Before creating or dispatching, inspect the candidate issue and its comments for evidence of an active or completed Codex delegation for this request. If an equivalent issue is already being handled, reuse it and do not dispatch again.

If the available tooling cannot search issues or comments, do not claim that a duplicate check was performed. Continue only when doing so does not risk a known duplicate, and disclose the tooling limitation in the receipt.

## 2. Materialize

Draft a concise, action-oriented issue title and an executable issue body. Use the following sections when applicable; omit an empty section rather than inventing content.

### Goal

State the concrete outcome in one or two sentences.

### Context

Describe the current behavior, problem, motivation, and established repository context. Include known errors, reproduction details, relevant files or modules, linked behavior, and prior implementation constraints when available.

### Scope

Use **In scope** and **Out of scope** when boundaries matter.

### Requirements

State functional behavior and engineering constraints. Prefer observable outcomes over unnecessary implementation prescriptions.

### Acceptance criteria

Use specific, verifiable completion conditions, including important behavior that must remain unchanged.

### Verification

Name established tests and checks when known. If exact commands are unknown, instruct Codex to discover them from repository documentation and applicable `AGENTS.md` files; never invent commands.

Before creating anything, apply this quality gate. Another engineer or coding agent must be able to answer:

1. What outcome is required?
2. Why is the change needed?
3. What is inside the scope?
4. What important behavior must remain unchanged?
5. How can completion be verified?

Inspect the repository first if doing so can fill a material gap. Otherwise ask the user for blocking information. Prefer a smaller, precise issue over a large, vague one.

## 3. Verify

Create the issue only after the target and task pass the quality gate. The initial title and body must contain no `@codex` mention.

Immediately read the created issue back from GitHub. Treat that response—not the local draft or creation response—as the source of truth. Verify its repository, issue number, title, body, and state. If any field is wrong or the issue is not open and usable, repair it and read it back again before dispatch. If creation fails, stop and report the GitHub failure; do not attempt a dispatch.

For a reused issue, likewise read its current title, body, state, and comments. Ensure it still describes the same objective and is suitable for dispatch. Do not silently rewrite an unrelated issue.

## 4. Dispatch

Immediately before dispatch, inspect the current issue comments again. Treat any equivalent Codex implementation trigger, reaction, reply, progress message, or task link showing active or completed delegation for the same request as a reason not to trigger again.

If no equivalent trigger exists, add exactly one top-level issue comment. Use this default prompt, adapting it only when task-specific instructions materially improve execution. Do not duplicate the complete issue body in the comment.

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

If comment creation fails, keep the issue and classify the dispatch as `not-submitted`. Do not compensate with a second issue or another kind of mention.

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
Issue action: created | reused
Codex dispatch: confirmed | submitted-unconfirmed | not-submitted
```

Then briefly state what Codex was asked to do, whether the handoff was confirmed, and any blocker or tooling limitation that still requires attention. Do not imply that the delegated implementation is complete.
