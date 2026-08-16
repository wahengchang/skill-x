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
- completed Product / Design constraints that materially affect the internal
  contributor journey, as read-only input;
- repository documents, build / test / debug / CI configuration, and any
  `## Owner Decisions` rows that affect developer experience.

It never rewrites the Product, Design, or Engineering facet sections and never
touches their fields.

External developer-facing API / CLI / SDK semantics are Product concerns.
DevEx is specifically the internal contributor / maintainer workflow.

## Required journey result

The `## DevEx Facet` section covers the full journey:

- **setup** — prerequisites, bootstrap/install path, generated state, success
  signal;
- **first change** — where to edit, feedback loop, and the command/path that
  proves the change is connected;
- **test** — exact local commands, layers, fixtures/dependencies, and failure
  signals;
- **debug** — reproduction path, logs/traces/diagnostics, and inspection tools;
- **CI/release** — pipeline/release path, required checks, artifacts/docs, and
  handoff from local success to shipping.

A truly irrelevant stage may be marked not applicable in the section with a
reason; it must not be silently omitted.

## Evidence model

This facet separates current facts from future requirements:

- A **current-state claim** must be backed by real repository evidence — a
  command that ran, a file/config that exists, a documented workflow, or a
  pipeline step that is defined. A guessed current state is never an assumption
  the facet may silently make.
- A **desired-state contract** may describe behavior that does not exist yet.
  Specify the exact command/path/expected result/failure behavior that
  implementation must create and that review can later verify.

Therefore an unimplemented target is not automatically a blocker. The facet
blocks only when the current evidence needed to plan safely cannot be obtained,
or the target journey cannot be specified to executable depth.

## Evidence requirements

`DevEx evidence` points to the full journey reasoning — normally the
`## DevEx Facet` section or a `--section-file`. Each applicable stage identifies
its current evidence and its desired contract. Never present a future command as
if it already ran, and never fill a current-state gap by assumption.

## Owner decision handoff

Most DevEx choices are technical and should be decided from evidence with the
rationale recorded. If a gap actually requires an Owner-only product/policy
choice, return a numbered decision brief to `x-plan` with the question,
recommendation, and consequences. The specialist does not insert or accept the
Owner Decision row itself.

`x-plan` records the pending decision through `xdh plan decision set`. If the
accepted answer changes a fingerprinted canonical scope/behavior input, `x-plan`
applies that edit first, recomputes the fingerprint, accepts the same decision
ID at the new fingerprint, and re-dispatches affected facets.

## Permitted fields and section

The devex facet may write **only**:

- the `DevEx facet` field;
- the `DevEx evidence` field;
- the `## DevEx Facet` section of the item.

It must not write any other facet's field or section, Owner Decision rows, or
fingerprinted canonical input sections.

## Completion criteria

The devex facet is complete only when every applicable journey stage has enough
current evidence and/or a precise desired contract for implementation and later
verification, with any non-applicable stage explained and no unresolved
Owner-only decision. Record the facet status as `completed@<current fingerprint>`
using the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet devex --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`.

## Blocker behavior

The devex facet records `blocked` only when required current evidence cannot be
obtained, a required Owner decision cannot be obtained, or the desired journey
cannot be specified safely enough for implementation/review. A normal technical
choice is not an Owner blocker: make the evidence-backed call and record why.

A missing existing command or pipeline step is not by itself a blocker when the
work is explicitly planning to create it; describe the future contract instead
of pretending the command already exists.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
