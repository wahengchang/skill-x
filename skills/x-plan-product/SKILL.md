---
name: x-plan-product
description: Resolve the product facet of a planning item — goal, scope, user-visible behavior, and priority — recording decisions and evidence and escalating every scope change to the Owner; use as the product specialist inside x-plan orchestration, or standalone to improve an existing plan's product section in place.
---

# x-plan-product

Own the **product** facet: what the work is for, what is in and out of scope,
and what the user sees. This skill never writes product code and never creates
IS / SP / WG documents.

## When to use

- `x-plan` dispatches this skill to resolve the product facet of one item.
- Standalone: a plan already exists and its goal, scope, or user-visible
  behavior needs to be improved in place.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-product/scripts/xdh" ] && XDH="$d/x-plan-product/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

`<item>` is always the item's **file path** under `.dev-hub/`, never the bare
`IS-001`. In facet mode the orchestrator hands it over together with the current
fingerprint; do not re-derive either from the conversation.

## Direct mode

Direct mode requires an explicit plan target: the user names an existing `IS` /
`SP` document. It improves that plan in place — refining `## Problem / Goal`,
`## Scope`, and the `## Owner Decisions` rows that are product territory — and
writes nothing else.

Before changing anything, surface every scope expansion, reduction, or
redefinition as a pending Owner Decision (with a recommended answer) and stop.
Direct mode never silently adopts a recommendation, never creates an `IS` /
`SP` / `WG`, and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. Read
`references/facet-contract.md` and follow it.

The orchestrator hands over the item's file path, the facet name, and the
current fingerprint. Resolve the product facet and write back through the sole
Facet-mode writer:

```bash
xdh plan facet set <item> --facet product --status <value> --evidence <ref> [--section-file <f>]
```

Everything else about this facet — intake, evidence, permitted fields, the
status vocabulary, deferral rules and forbidden lifecycle mutations — is in
`references/facet-contract.md`. Follow it there; it is the canonical text and
restating it here only doubled what a plan loads into context.

Two things are worth repeating here because they are what Product gets wrong.
Product records every scope expansion, reduction, or redefinition as a
**pending** Owner Decision and stops — it never silently adopts its own
recommendation. And it is the one facet that may open that row itself, only
together with a `blocked` status, via `--owner-decision-file`; name in the
question the exact canonical input an accepted answer would change
(`## Problem / Goal`, `## Scope`, `## Current → Desired Behavior`, the route, or
the selected work), so the orchestrator can edit first and accept second.
