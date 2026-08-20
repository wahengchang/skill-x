# x-ship risk checklist

Use this only when the shipping class is not obvious from the diff, when a guard trigger appears, or when the repository/user asks for stricter delivery. The class is based on **blast radius and failure cost**, not line count.

## Classification rule

Start at `light`, then promote. Never demote a class required by repository policy or an explicit user request.

### `light`

Keep `light` only when all of these are true:

- the intent is narrow and the diff is easy to inspect end-to-end;
- failure is local and easy to reverse;
- no guarded trigger below applies;
- no public API, CLI, config, schema, serialization, permission, or data-semantics contract changes;
- no cross-cutting control-flow or architecture change;
- tests already exercise the affected behavior, or the change itself is documentation/tests/mechanical maintenance.

Typical examples: typo/docs fixes, comments, test-only changes, a local rename, a small internal bug fix with an existing contract, or mechanical cleanup with no behavior change.

A small diff is **not** automatically light. A one-line authorization, migration, billing, deletion, or release change is guarded.

### `standard`

Use `standard` for ordinary behavioral work that is not guarded: a normal bug fix, a contained feature, or a multi-file implementation with a known blast radius.

Standard shipping adds one focused independent review after the full test run. It does not require the guarded documentation audit or fingerprint freeze unless the review itself exposes a guarded risk.

### `guarded`

Promote to `guarded` if any of these apply:

- authentication, authorization, secrets, security boundaries, privacy, or permission logic;
- payments, billing, quotas, entitlements, or other money/value movement;
- destructive operations, deletion, irreversible state changes, backup/restore, or data-loss risk;
- database/schema migrations, persistence format changes, data model semantics, or compatibility-sensitive serialization;
- public API/CLI/config contracts, protocol/version compatibility, package publishing, or externally consumed behavior;
- concurrency, locking, idempotency, retry semantics, distributed coordination, or race-prone state transitions;
- install/update/bootstrap/release/deployment/credential flows;
- dependency changes with runtime, supply-chain, security, or compatibility impact;
- broad refactors, architectural changes, cross-package/shared-runtime changes, or an uncertain blast radius;
- the repository policy, owner, or work item explicitly requires strict/final independent review;
- evidence is contradictory or the agent cannot confidently bound the failure mode.

Guarded shipping uses the full final-content discipline: documentation blast-radius audit, fingerprint-bound independent review, content freeze after approval, and re-review after any reviewed-content change.

## Promotion rules

Promote one level when classification is ambiguous. Promote directly to `guarded` for any guarded trigger. Never use diff size, elapsed implementation time, or perceived triviality as the only reason to lower risk.

If a `light` or `standard` run discovers a guarded trigger, stop the cheaper path and continue as `guarded`; already-completed tests may be reused only while the code/test tree is unchanged in the same invocation.

## What to record

Record the class and one sentence of evidence, for example:

```text
Ship class: light — docs-only correction; no runtime or public contract changed.
Ship class: standard — contained parser bug fix; behavior changed but no guarded surface.
Ship class: guarded — installer/update flow changed; release and credential-adjacent path.
```
