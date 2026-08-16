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

This is the portion that runs as a facet inside `x-plan` orchestration. It must
follow `references/facet-contract.md`.

The facet reads the item's `Product facet` / `Product evidence` fields and its
`## Problem / Goal`, `## Scope`, and `## Owner Decisions` sections, resolves the
product facet, and writes back via the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet product --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>`. Completion
records `completed@<current fingerprint>`; the fingerprint is reported by the
read-only `xdh plan fingerprint <item>`.

Product records every scope expansion, reduction, or redefinition as a pending
Owner Decision and stops — it never silently adopts a recommended answer, and
never expands, reduces, or redefines scope on its own authority.

After the Owner answers, the orchestrator accepts that same decision ID with
`xdh plan decision set` at the current fingerprint before Product completes.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Provenance

Merges the Owner's Kickoff and Backlog-Refinement prompts with the product /
scope discipline of gstack `spec` (snapshot `d078622`, MIT). The facet contract
is the single canonical source and lives in
`commands-src/_x-shared/facets/product-facet-contract.md`.
