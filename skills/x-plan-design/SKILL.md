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

This is the portion that runs as a facet inside `x-plan` orchestration. Read
`references/facet-contract.md` and follow it.

The orchestrator hands over the item's file path, the facet name, and the
current fingerprint. Resolve the design facet and write back through the sole
Facet-mode writer:

```bash
xdh plan facet set <item> --facet design --status <value> --evidence <ref> [--section-file <f>]
```

Everything else about this facet — intake, evidence, permitted fields, the
status vocabulary, deferral rules and forbidden lifecycle mutations — is in
`references/facet-contract.md`. Follow it there; it is the canonical text and
restating it here only doubled what a plan loads into context.

One thing is specific to this skill and is not in the contract: stage design
artifacts exactly as Direct mode does — the same `design prepare` call, with the
three capability results stated explicitly and `--fingerprint` set to the
planning fingerprint the orchestrator handed over, so the design directory is
reused rather than rebuilt while that fingerprint holds.

