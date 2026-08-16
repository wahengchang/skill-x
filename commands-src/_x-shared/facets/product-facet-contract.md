# Product Facet — Contract

Authoritative contract for the **product** facet of `x-plan`. Each specialist
follows only its own facet contract; `x-plan` bundles this file into its own
`references/` directory and reads it from there, never from a sibling skill path
or a specialist's Direct workflow.

## Facet-mode intake

The product facet reads:

- the item's `Product facet` and `Product evidence` fields;
- the `## Problem / Goal`, `## Scope`, and relevant `## Current → Desired
  Behavior` content of the `IS` / `SP` document;
- any existing `## Owner Decisions` rows that affect product direction, scope,
  priority, or user-visible behavior;
- repository/product evidence needed to distinguish an actual product decision
  from an implementation detail.

It never reads the Design, DevEx, or Engineering facet sections, and never
touches their fields.

External developer-facing API / CLI / SDK semantics are Product concerns.
Internal contributor setup, build, test, debug, CI/release, and maintainer
workflow belong to DevEx.

## Required product result

Before completion, the `## Product Facet` section must make these constraints
explicit enough for downstream facets to consume without guessing:

- intended outcome / problem being solved;
- user-visible or external developer-visible behavior;
- in-scope and out-of-scope boundaries;
- priority or material product tradeoffs;
- accepted Owner constraints, if any.

Technical implementation details that do not change those concerns are not
Product decisions.

## Evidence requirements

The product facet must record as `Product evidence` a reference that points to
where the reasoning actually lives — the `## Product Facet` section of the item,
or a `--section-file` the specialist wrote.

Every scope expansion, reduction, or redefinition must be recorded as a
**pending Owner Decision** in the `## Owner Decisions` table, with a recommended
answer, and the specialist must stop there rather than silently adopting the
recommendation. The Product section must also identify which canonical planning
input would change if the Owner accepts (`Planning route`, `Selected work`,
`## Problem / Goal`, `## Scope`, or `## Current → Desired Behavior`).

## Canonical input handoff

Facet mode never rewrites fingerprinted canonical inputs itself. When the Owner
accepts a Product decision that changes one of those inputs, control returns to
`x-plan`:

1. `x-plan` applies the accepted canonical edit;
2. `x-plan` recomputes the planning fingerprint;
3. `x-plan` accepts the same Owner Decision ID at that new fingerprint using
   `xdh plan decision set`;
4. Product is re-dispatched and may complete only against the new fingerprint.

This ordering prevents an accepted scope or behavior change from remaining
anchored to an obsolete fingerprint.

## Permitted fields and section

The product facet may write **only**:

- the `Product facet` field;
- the `Product evidence` field;
- the `## Product Facet` section of the item;
- one pending product Owner Decision row, atomically with a blocked Product
  status, through the sole scoped writer.

It must not write any other facet's field or section, and it must not rewrite
fingerprinted canonical input sections in Facet mode.

## Completion criteria

The product facet is complete only when the required product result above is
resolved and there is no pending Product Owner Decision. The specialist records
the facet status as `completed@<current fingerprint>` using the sole Facet-mode
writer:

```bash
xdh plan facet set <item> --facet product --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`.

## Blocker behavior

The product facet blocks (records `blocked`) only when an Owner decision is
required and cannot yet be obtained. A scope expansion, reduction, or
redefinition is exactly such a case: the specialist records it as a pending
Owner Decision and stops — it never silently adopts a recommended answer, and
never expands, reduces, or redefines scope on its own authority.

For a scope change, it writes one project-local file containing a complete
pending product row (`| OD-001 | product | question | recommendation | pending | — |`)
and invokes the scoped writer with `--owner-decision-file <f>`. The Product
fields, Product section, and decision row are replaced together.

After the Owner answers, `x-plan` — not Product — performs any required canonical
input edit and records the accepted transition with the same ID:

```bash
xdh plan decision set <item> --id OD-001 --facet product \
  --question "<same pending question>" --decision "<owner answer>" \
  --state accepted@<current-fp>
```

The writer permits only pending → accepted at the current fingerprint, treats an
identical retry as a no-op, and rejects every other ID collision.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
