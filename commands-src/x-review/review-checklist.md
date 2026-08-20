# x-review full checklist

Read this only for `full` review, or when `quick` review finds a signal that may require escalation. Quick review must not sweep this checklist by default.

## Escalate from quick to full

Escalate immediately when the change touches or plausibly affects any of these:

- authentication, authorization, permissions, secrets, privacy, or trust boundaries;
- payments, billing, quotas, entitlements, or value movement;
- destructive operations, persistent data semantics, migrations, schemas, or serialization compatibility;
- public API, CLI, config, protocol, package, or externally consumed contracts;
- concurrency, locking, idempotency, retry semantics, distributed coordination, or race-prone transitions;
- install, update, bootstrap, deployment, release, dependency, or credential flows;
- broad architecture, shared runtime, cross-package behavior, or a blast radius that cannot be bounded confidently;
- contradictory evidence or a finding whose safety depends on repository-wide assumptions.

## Full review categories

For `full` review, cover every relevant category and read outside the diff when required to verify consumers and invariants.

- **Correctness and data safety** — validation bypasses, unsafe writes, atomicity, partial updates, N+1 behavior, invalid state transitions.
- **Concurrency** — check-then-write races, uniqueness assumptions, double-apply paths, locking and idempotency.
- **Security and trust boundaries** — untrusted values reaching databases, shells, interpreters, mailers, renderers, or outbound requests without validation or allowlists.
- **API/schema/enum completeness** — trace new states, values, fields, and contracts through all consumers.
- **Error paths** — failure, retry, timeout, rollback, and partial-failure behavior.
- **Performance** — only material regressions caused by the change.
- **Tests** — negative paths, edge cases, and regression coverage matching the changed behavior.
- **Plan/scope completeness** — requested scope is delivered without accidental unrelated work.
- **Documentation** — repository docs, examples, and operator guidance still match shipped behavior.

## Evidence standard

Every actionable finding includes severity, `file:line`, a concrete failure scenario, evidence, and a recommended resolution. Verify claims before writing them. Do not report speculation as a finding.
