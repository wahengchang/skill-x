# Engineering Facet — Contract

Authoritative contract for the **engineering** facet of `x-plan`. Each
specialist follows only its own facet contract; `x-plan` bundles this file into
its own `references/` directory and reads it from there, never from a sibling
skill path or a specialist's Direct workflow.

Engineering is **mandatory** in every planning route and is never
`not-applicable`, `deferred-owner`, or `deferred-missing`. It is always the last
facet in the route.

## Facet-mode intake

The engineering facet reads:

- the item's `Engineering facet` and `Engineering evidence` fields;
- the fully defined `## Problem / Goal`, `## Scope`, `## Current → Desired
  Behavior`, and `## Owner Decisions` sections;
- the completed Product, Design, and DevEx facet sections — their decisions are
  the engineering facet's constraints;
- the repository itself: patterns, interfaces, schemas, migrations, and the
  tests that already cover the area.

It never rewrites the Product, Design, or DevEx facet sections, and never
touches their fields.

## Evidence requirements

The engineering facet must record as `Engineering evidence` a reference to where
the engineering plan lives — the `## Engineering Facet` section of the item, or
a `--section-file` the specialist wrote. The evidence cites `file:line` for
claims about the code and names the tests and acceptance criteria that make the
plan executable without further design decisions.

## Permitted fields and section

The engineering facet may write **only**:

- the `Engineering facet` field;
- the `Engineering evidence` field;
- the `## Engineering Facet` section of the item.

It must not write any other facet's field or section.

## Completion criteria

The engineering facet is complete when the specialist records the facet status
as `completed@<current fingerprint>` using the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet engineering --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`. Engineering is never recorded as `not-applicable`,
`deferred-owner`, or `deferred-missing`.

## Blocker behavior

The engineering facet blocks (records `blocked`) only when a required user
decision cannot be obtained, or when the plan cannot be made executable from the
evidence at hand. It never defers: engineering always resolves to
`completed@<fp>` or `blocked`.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
