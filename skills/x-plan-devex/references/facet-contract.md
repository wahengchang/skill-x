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
- the `## DevEx commands` section of `xdh survey ensure`, and any
  `## Owner Decisions` rows that affect the developer experience.

It never reads the Product, Design, or Engineering facet sections, and never
touches their fields.

## Evidence requirements

The developer journey — setup, first change, test, debug, CI/release — is a
**property of the project, not of a work item**, so it is established once and
reused. `xdh survey ensure` collects the mechanically knowable part of it (Make
targets, package scripts, CI steps) and caches it against the commit and the
working tree.

Per item, the devex facet answers one question: **does this change touch any
stage of that journey?**

- **It does not** — the common case. Record `not-applicable` and name the
  journey stages the change leaves untouched. Do not re-verify them.
- **It does** — verify *only the affected stages*, with real evidence: a command
  that ran, a config file that exists, a pipeline step that is defined. Record
  as `DevEx evidence` a reference to that verification.

Re-walking the entire journey for every work item is what this contract used to
require and now forbids: it re-derives the same project-level facts once per
item at a cost that scales with the backlog. A stage the survey could not
determine mechanically and that this change actually touches is still verified
by hand — never assumed.

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

The devex facet does not write the decision row itself: the atomic
facet-and-row write is reserved for `product`. It records `blocked`, states the
question and its recommended answer in `## DevEx Facet`, and the orchestrator
opens the pending row with the ID-keyed writer.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
