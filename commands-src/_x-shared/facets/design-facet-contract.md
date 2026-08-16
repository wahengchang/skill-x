# Design Facet — Contract

Authoritative contract for the **design** facet of `x-plan`. Each specialist
follows only its own facet contract; `x-plan` bundles this file into its own
`references/` directory and reads it from there, never from a sibling skill path
or a specialist's Direct workflow.

## Facet-mode intake

The design facet reads:

- the item's `Design facet` and `Design evidence` fields;
- the `## Current → Desired Behavior` and `## Scope` sections of the `IS` / `SP`
  document;
- the completed `## Product Facet` section as a read-only constraint when
  Product is in the route;
- any `## Owner Decisions` rows that affect UX, interaction, or the user-visible
  capability surface;
- relevant existing UI, design-system, and implementation evidence.

It never rewrites the Product, DevEx, or Engineering facet sections and never
touches their fields.

## Required design result

Before completion, the `## Design Facet` section resolves every applicable
concern:

- information architecture, hierarchy, labels, and navigation placement;
- primary user journey;
- interaction states including loading/progress, empty, success, error,
  disabled/permission, confirmation, and recovery where relevant;
- concrete visual intent: hierarchy, density, emphasis, and content placement;
- design-system component/token/pattern reuse and intentional deviations;
- responsive behavior and accessibility constraints;
- any unresolved material UX choice that requires the Owner.

A screenshot or generated image by itself is not sufficient evidence. The design
must explain behavior and constraints that an implementation agent can execute.

## Evidence requirements

The design facet must record as `Design evidence` a reference to where the design
reasoning lives — the `## Design Facet` section of the item, or a
`--section-file` the specialist wrote.

When capabilities are in play, record the **capability ladder** by independently
detecting **Image Generate**, **Image Display**, and **Image Compare**. Record
each as `available` or `unavailable` together with evidence for that judgement.
Capability availability controls the exploration method, not whether design
reasoning is required.

## Variant workflow

For UI work where alternatives materially affect the UX:

1. With Image Generate available, produce 2–3 meaningfully different variants
   bound to the same planning fingerprint.
2. With Image Display available, show them; otherwise preserve artifacts and
   provide text summaries.
3. With Image Compare available, compare them side by side against the same
   criteria; otherwise write the comparison explicitly.
4. Record the recommended/selected direction and why it fits Product constraints.

Without Image Generate, use text or wireframe alternatives when a choice still
matters. Missing capability **downgrades** the workflow rather than blocks it and
must not silently collapse multiple plausible directions into one.

When staging design artifacts, pass each observed result through the public
`design prepare` options `--image-generate`, `--image-display`, and
`--image-compare`. Each value is explicitly `available` or `unavailable`; no
implicit environment default is accepted.

## Owner decision handoff

If evidence cannot resolve a material UX choice, the specialist returns a
numbered decision brief to `x-plan` with the question, recommendation, and
consequences. The specialist does not insert or accept the Owner Decision row
itself because its only item mutation is the scoped Design writer.

`x-plan` records the pending decision through `xdh plan decision set`. After the
Owner answers, if the decision changes a fingerprinted canonical scope/behavior
input, `x-plan` applies that canonical edit first, recomputes the fingerprint,
accepts the same decision ID at the new fingerprint, and re-dispatches the
affected facets.

## Permitted fields and section

The design facet may write **only**:

- the `Design facet` field;
- the `Design evidence` field;
- the `## Design Facet` section of the item.

It must not write any other facet's field or section, Owner Decision rows, or
fingerprinted canonical input sections.

## Completion criteria

The design facet is complete only when the required design result is executable,
any applicable variant comparison is recorded, capability downgrades are
explicit, and no material Design Owner decision remains unresolved. The
specialist records the facet status as `completed@<current fingerprint>` using
the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet design --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`.

## Blocker behavior

A missing Image Generate / Display / Compare capability is not a blocker. The
specialist records it as `unavailable`, documents the fallback, and continues.
The design facet records `blocked` only when a required Owner decision cannot be
obtained or the available evidence is insufficient to specify safe executable
UX behavior.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
