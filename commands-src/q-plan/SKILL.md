---
name: q-plan
description: Clarify an engineering request only as much as needed to reach shared understanding, classify it as micro, scoped, or complex, record the agreed understanding in one local build-plan.md, and route to the matching q-plan-* skill.
---

# q-plan

Understand the work, choose the right planning depth, and hand it off. Do not produce the implementation plan yourself.

## Core flow

```text
request
  ↓
understand the work
  ↓
interview only if needed
  ↓
shared understanding
  ↓
classify complexity
  ↓
q-plan-micro | q-plan-scoped | q-plan-complex
```

## 1. Understand before asking

Use the conversation, repository docs, source, tests, Git state, and existing project patterns first. If a question can be answered by inspecting the project, inspect it instead of asking the user.

Assume CodeGraph is available when relationship or blast-radius information would materially help. Ask relationships first, then open only the files needed to make the judgement.

The user may be a product person, designer, engineer, or none of those. Do not force professional vocabulary onto them. The goal of the interview is simply to understand what they want to accomplish.

## 2. Interview only until aligned

Interview when the request still has more than one materially different reasonable interpretation.

- Ask one focused question at a time.
- Prefer the host's structured user-input capability (`askUserQuestion`, `requireUserInput`, or equivalent) when available.
- For every question, include your recommended answer and a short reason.
- Keep asking only while the answer could change what work the user actually wants.
- Do not ask for implementation details the repository can answer.
- Do not ask questions merely to fill a template.

Stop when you can restate the work in plain language and the user agrees that the understanding is correct enough to proceed.

## 3. Persist one active source of truth

Active planning state is local execution state, not repository history.

Use:

```text
.dev-hub/active/<slug>/build-plan.md
```

Rules:

- one active work scope per directory;
- exactly one `build-plan.md` is the source of truth for that scope;
- multiple active scopes may coexist;
- ensure `.dev-hub/active/` is ignored by the target repository's `.gitignore`;
- do not create Cycle, WG, Issue, Spike, facet, fingerprint, or runtime artifact files;
- reuse an existing active plan for the same scope instead of creating a duplicate.

Create or update only this minimal header before routing:

```markdown
# Build Plan — <title>

- Status: planning
- Complexity: <micro|scoped|complex>
- Route: <q-plan-micro|q-plan-scoped|q-plan-complex>

## Understanding

<plain-language statement of what the user wants, important boundaries, and what success means>
```

Do not pre-fill implementation details here.

## 4. Classify by uncertainty and failure cost

The default is automatic classification. An explicit user override (`micro`, `scoped`, `complex`, `direct`, `quick`, or `deep`) wins unless it would create an obvious safety/correctness problem; in that case explain the concern and promote the planning depth.

Use these signals:

### micro

Choose `micro` when the desired behavior is clear, an existing pattern makes the implementation nearly obvious, the blast radius is local, rollback is easy, and no important architectural or high-risk boundary is involved.

Typical examples: copy change, small validation, local styling/config change, straightforward use of an existing pattern.

### scoped

Choose `scoped` when the work needs bounded investigation or a short implementation plan, but the relevant area and blast radius can be identified confidently and there is no major unresolved design decision.

Typical examples: a new endpoint following an existing pattern, a small feature spanning a few known layers, or a bounded refactor.

### complex

Choose `complex` when important decisions are unresolved, there are multiple plausible approaches, the blast radius is broad or uncertain, rollback is costly, or the work touches a high-risk boundary such as auth/permissions, persistent data/schema/migrations, payments, public contracts, concurrency/idempotency, storage, or architecture.

A one-line change can be complex. File count and line count are evidence, not the classifier.

## 5. Route and stop

After classification:

- `micro` → invoke `q-plan-micro`
- `scoped` → invoke `q-plan-scoped`
- `complex` → invoke `q-plan-complex`

Pass the path to `build-plan.md` and the original request. The routed skill owns the actual plan.

If later repository evidence proves the lane wrong, the routed skill may promote or demote once, update `Complexity` and `Route`, and continue under the correct q-plan skill. Do not keep bouncing between lanes.
