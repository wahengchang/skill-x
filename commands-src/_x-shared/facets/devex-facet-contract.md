# DevEx Facet — Contract

Authoritative contract for the **devex** facet of `x-plan`. Each specialist
follows only its own facet contract; `x-plan` bundles this file into its own
`references/` directory and reads it from there, never from a sibling skill path
or a specialist's Direct workflow.

## Facet-mode intake

The devex facet reads:

- the item's `DevEx facet` and `DevEx evidence` fields;
- the `## Scope` and `## Current → Desired Behavior` sections of the `IS` / `SP`
  document;
- repository documents, build / test / debug / CI configuration, and any
  `## Owner Decisions` rows that affect the developer experience.

It never reads the Product, Design, or Engineering facet sections, and never
touches their fields.

## Evidence requirements

The devex facet must record as `DevEx evidence` a reference to the full
developer journey the specialist verified, from setup through first change,
test, debug, and CI/release. Each stage must be backed by real evidence — a
command that ran, a config file that exists, a pipeline step that is defined —
never an assumption.

## Permitted fields and section

The devex facet may write **only**:

- the `DevEx facet` field;
- the `DevEx evidence` field;
- the `## DevEx Facet` section of the item.

It must not write any other facet's field or section.

## Completion criteria

The devex facet is complete when the specialist records the facet status as
`completed@<current fingerprint>` using the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet devex --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`.

## Blocker behavior

The devex facet blocks (records `blocked`) only when a required user decision
cannot be obtained. A gap in the developer journey is recorded in
`## DevEx Facet` as evidence, not silently filled in by assumption; if a stage
cannot be verified or decided, it becomes a blocker or a pending Owner Decision
rather than a guess.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
