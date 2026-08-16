# Product Facet — Contract

Authoritative contract for the **product** facet of `x-plan`. Each specialist
follows only its own facet contract; `x-plan` bundles this file into its own
`references/` directory and reads it from there, never from a sibling skill path
or a specialist's Direct workflow.

## Facet-mode intake

The product facet reads:

- the item's `Product facet` and `Product evidence` fields;
- the `## Problem / Goal` and `## Scope` sections of the `IS` / `SP` document;
- any existing `## Owner Decisions` rows that affect product direction, scope,
  priority, or user-visible behavior.

It never reads the Design, DevEx, or Engineering facet sections, and never
touches their fields.

## Evidence requirements

The product facet must record as `Product evidence` a reference that points to
where the reasoning actually lives — the `## Product Facet` section of the item,
or a `--section-file` the specialist wrote. Every scope expansion, reduction, or
redefinition must be recorded as a **pending Owner Decision** in the
`## Owner Decisions` table, with a recommended answer, and the specialist must
stop there rather than silently adopting the recommendation.

## Permitted fields and section

The product facet may write **only**:

- the `Product facet` field;
- the `Product evidence` field;
- the `## Product Facet` section of the item.
- one pending product Owner Decision row, atomically with a blocked Product
  status, through the sole scoped writer.

It must not write any other facet's field or section.

## Completion criteria

The product facet is complete when the specialist records the facet status as
`completed@<current fingerprint>` using the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet product --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`.

## Blocker behavior

The product facet blocks (records `blocked`) only when an Owner decision is
required and cannot be obtained. A scope expansion, reduction, or redefinition
is exactly such a case: the specialist records it as a pending Owner Decision
and stops — it never silently adopts a recommended answer, and never expands,
reduces, or redefines scope on its own authority. Once the decision is obtained,
the orchestrator first records it with the ID-keyed writer, then the specialist
records `completed@<fp>` and returns:

```bash
xdh plan decision set <item> --id OD-001 --facet product \
  --question "<same pending question>" --decision "<owner answer>" \
  --state accepted@<current-fp>
```

The writer permits only pending → accepted at the current fingerprint,
treats an identical retry as a no-op, and rejects every other ID collision.

For a scope change, it writes one project-local file containing a complete
pending product row (`| OD-001 | product | question | recommendation | pending | — |`)
and invokes the same scoped writer with `--owner-decision-file <f>`. The Product
fields, Product section, and decision row are replaced together.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
