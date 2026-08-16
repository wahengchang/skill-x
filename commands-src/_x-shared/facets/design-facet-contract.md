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
- any `## Owner Decisions` rows that affect UX, interaction, or the user-visible
  capability surface.

It never reads the Product, DevEx, or Engineering facet sections, and never
touches their fields.

## Evidence requirements

The design facet must record as `Design evidence` a reference to where the design
reasoning lives — the `## Design Facet` section of the item, or a `--section-file`
the specialist wrote. When capabilities are in play, the specialist records the
capability ladder: it independently detects each of **Image Generate**,
**Image Display**, and **Image Compare**, and records each as `available` or
`unavailable` together with the evidence for that judgement.

## Permitted fields and section

The design facet may write **only**:

- the `Design facet` field;
- the `Design evidence` field;
- the `## Design Facet` section of the item.

It must not write any other facet's field or section.

## Completion criteria

The design facet is complete when the specialist records the facet status as
`completed@<current fingerprint>` using the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet design --status completed@<fp> --evidence <ref> [--section-file <f>]
```

`<fp>` is the current planning fingerprint reported by the read-only
`xdh plan fingerprint <item>`.

## Capability ladder and downgrade rule

Image Generate, Image Display, and Image Compare are detected independently; a
missing capability **downgrades** the design rather than blocks it. The
specialist records the missing capability as `unavailable` in
`## Design Facet`, notes the downgrade, and proceeds with the capability set
that is actually present. It blocks only when a required user decision cannot be
obtained — a UX choice that no evidence resolves and that only the Owner can
settle.

When staging design artifacts, the specialist passes each observed result
through the public `design prepare` options `--image-generate`,
`--image-display`, and `--image-compare`. Each value is explicitly
`available` or `unavailable`; no implicit environment default is accepted.

## Blocker behavior

The design facet blocks (records `blocked`) only when a required user decision
cannot be obtained. A missing Image Generate / Display / Compare capability is
not a blocker: it is recorded as `unavailable` and the design proceeds with what
exists.

## Forbidden lifecycle mutations

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. Those are the orchestrator's lifecycle operations, not the
facet's. The facet's only item mutation is the `xdh plan facet set` write above.
