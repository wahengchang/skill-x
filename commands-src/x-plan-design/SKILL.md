---
name: x-plan-design
description: Resolve the design facet of a planning item — UX, interaction, and the user-visible capability surface, including independent detection of Image Generate / Display / Compare — recording decisions and evidence; use as the design specialist inside x-plan orchestration, or standalone to improve an existing plan's design section in place.
---

# x-plan-design

Own the **design** facet: how the thing looks, how the user interacts with it,
and which capabilities the design can actually rely on. This skill never writes
product code and never creates IS / SP / WG documents.

## When to use

- `x-plan` dispatches this skill to resolve the design facet of one item.
- Standalone: a plan already exists and its UX, interaction, or capability
  surface needs to be improved in place.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-design/scripts/xdh" ] && XDH="$d/x-plan-design/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

`<item>` is always the item's **file path** under `.dev-hub/`, never the bare
`IS-001`. In facet mode the orchestrator hands it over together with the current
fingerprint; do not re-derive either from the conversation.

## Direct mode

Direct mode requires an explicit plan target: the user names an existing `IS` /
`SP` document. It improves that plan in place — refining
`## Current → Desired Behavior` and the `## Design Facet` section — and writes
nothing else.

When capabilities are in play, Direct mode records the capability ladder in the
`## Design Facet` section: it independently detects each of **Image Generate**,
**Image Display**, and **Image Compare**, and records each as `available` or
`unavailable` with evidence. A missing capability downgrades the design; Direct
mode proceeds with what exists. It stops only when a required user decision
cannot be obtained.

Standalone design work that needs to stage design artifacts (images, mockups)
may prepare a design directory bound to a fingerprint:

```bash
xdh design prepare --slug <slug> --fingerprint <fp> \
  --image-generate <available|unavailable> \
  --image-display <available|unavailable> \
  --image-compare <available|unavailable>
```

Pass all three capability results explicitly after inspecting the current
host's tools; they are validated independently and recorded in `manifest.md`.
There are no environment-variable defaults. `X_DESIGN_DIR` is the prepared
directory; `X_DESIGN_REUSED` reports reuse.
Direct mode never creates an `IS` / `SP` / `WG` and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. It must
follow `references/facet-contract.md`.

The facet reads the item's `Design facet` / `Design evidence` fields and its
`## Current → Desired Behavior` and `## Scope` sections, resolves the design
facet, and writes back via the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet design --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>`. Completion
records `completed@<current fingerprint>`; the fingerprint is reported by the
read-only `xdh plan fingerprint <item>`.

The two deferred values are Owner-sanctioned, never a shortcut past work the
facet could have done: `plan check` accepts a deferral only when an Owner
Decision for this facet is accepted at the same fingerprint, and otherwise
rejects it as `facet=design status=deferred-unaccepted`. A status carrying a
fingerprint must carry the current one; anything older is reported as stale.

The design facet detects Image Generate, Image Display, and Image Compare
independently and records each as `available` or `unavailable`. A missing
capability downgrades the design rather than blocks it; the facet blocks only
when a required user decision cannot be obtained.

Staging design artifacts works the same way here as in Direct mode — the same
`design prepare` call, with the three capability results stated explicitly and
`--fingerprint` set to the planning fingerprint the orchestrator handed over, so
the design directory is reused rather than rebuilt while that fingerprint holds.

A UX question only the Owner can settle is reported to the orchestrator with a
`blocked` status and a recommended answer; the orchestrator opens the decision
row. Design cannot open one itself — the row writer accepts an atomic
facet-and-row write only for `product`.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Provenance

Merges the Owner's Spec-Finalization prompt with the UX / interaction discipline
of gstack `spec` (snapshot `d078622`, MIT). The capability ladder — independently
detecting Image Generate / Display / Compare and downgrading rather than blocking
— is new to this framework. The facet contract is the single canonical source and
lives in `commands-src/_x-shared/facets/design-facet-contract.md`.
