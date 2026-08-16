---
name: x-plan-product
description: Resolve the product facet of a planning item — goal, scope, user-visible behavior, priority, and external developer-facing product semantics — recording decisions and evidence and escalating every scope change to the Owner; use as the product specialist inside x-plan orchestration, or standalone to improve an existing plan's product section in place.
---

# x-plan-product

Own the **product** facet: what the work is for, who or what behavior it serves,
what is in and out of scope, and which user-visible tradeoffs matter. External
developer-facing API / CLI / SDK semantics are Product concerns; internal
engineering workflow belongs to DevEx. This skill never writes product code and
never creates IS / SP / WG documents.

## When to use

- `x-plan` dispatches this skill when the work introduces a capability, changes
  user-visible behavior, has unclear product scope/priority, or changes an
  external developer-facing product surface.
- Standalone: a plan already exists and its goal, scope, priority, or
  user-visible behavior needs to be improved in place.

## Product questions

Resolve these from repository/product evidence before asking the Owner:

- What problem or outcome is this work responsible for?
- Which user-visible or external developer-visible behavior changes?
- What is explicitly **in** scope and **out** of scope?
- What priority or tradeoff constrains the plan?
- Is any recommendation actually a scope expansion, reduction, or redefinition?

Do not turn implementation choices into product questions. Ask the Owner only
when evidence cannot decide a product direction, scope, priority, or
user-visible behavior.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-product/scripts/xdh" ] && XDH="$d/x-plan-product/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

## Direct mode

Direct mode requires an explicit plan target: the user names an existing `IS` /
`SP` document. Inspect the current plan and supporting repository evidence
before editing. Improve the plan in place by refining `## Problem / Goal`,
`## Scope`, relevant user-visible behavior, the `## Product Facet` section, and
product `## Owner Decisions`; write nothing outside that plan.

Before changing scope, surface every expansion, reduction, or redefinition as a
pending Owner Decision with a recommended answer and stop. Direct mode never
silently adopts a recommendation. After the Owner accepts, apply the accepted
change to the canonical plan text, then recompute the planning fingerprint so
any stale facet completion is visible before the plan returns to orchestration.
Direct mode never creates an `IS` / `SP` / `WG` and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. It must
follow `references/facet-contract.md`.

The facet reads the item's `Product facet` / `Product evidence` fields,
`## Problem / Goal`, `## Scope`, relevant `## Current → Desired Behavior`, and
product `## Owner Decisions`. It writes back only through the sole Facet-mode
writer:

```bash
xdh plan facet set <item> --facet product --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>`. Completion
records `completed@<current fingerprint>`; the fingerprint is reported by the
read-only `xdh plan fingerprint <item>`.

The `## Product Facet` evidence should make the resolved product contract easy
for downstream facets to consume: intended outcome, user-visible behavior,
scope boundaries, priority/tradeoffs, and any accepted Owner constraint.

Product records every scope expansion, reduction, or redefinition as a pending
Owner Decision and stops — it never silently adopts a recommended answer, and
never expands, reduces, or redefines scope on its own authority. When proposing
such a decision, include the exact canonical input that would need to change
(`## Problem / Goal`, `## Scope`, `## Current → Desired Behavior`, route, or
selected work) so `x-plan` can apply the accepted change deterministically.

After the Owner answers, the orchestrator keeps the same decision ID. If the
answer changes a fingerprinted input, `x-plan` applies the accepted canonical
edit first, recomputes the fingerprint, accepts that decision with
`xdh plan decision set` at the new fingerprint, and then re-dispatches Product.
Product itself does not mutate canonical fingerprint inputs in Facet mode.

Do not complete while the intended outcome, user-visible behavior, scope
boundary, or required Owner decision is unresolved. A technical implementation
detail that does not change product behavior is not a Product blocker.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Provenance

Merges the Owner's Kickoff and Backlog-Refinement prompts with the product /
scope discipline of gstack `spec` (snapshot `d078622`, MIT). The facet contract
is the single canonical source and lives in the bundled
`references/facet-contract.md` at runtime.
