---
name: x-plan-design
description: Resolve the design facet of a planning item — information architecture, UX flow, interaction states, visual intent, design-system reuse, responsive/accessibility behavior, and capability-aware variants — recording decisions and evidence; use as the design specialist inside x-plan orchestration, or standalone to improve an existing plan's design section in place.
---

# x-plan-design

Own the **design** facet: how the user understands, navigates, and interacts with
the product surface, and what design evidence the implementation can rely on.
Tool availability changes the method, not the standard of design reasoning. This
skill never writes product code and never creates IS / SP / WG documents.

## When to use

- `x-plan` dispatches this skill for new or changed UI, interaction flow/state,
  information architecture, or design-system behavior.
- Standalone: a plan already exists and its UX, interaction, visual intent, or
  capability surface needs to be improved in place.

## Design review checklist

Resolve every applicable concern before completion:

- **Information architecture:** hierarchy, labels, navigation, and where the
  change lives in the existing product structure.
- **Primary journey:** the shortest credible path from user intent to outcome.
- **Interaction states:** default, loading/progress, empty, success, error,
  permission/disabled, destructive confirmation, and recovery where relevant.
- **Visual intent:** hierarchy, density, emphasis, copy placement, and concrete
  constraints that prevent a generic or arbitrary generated look.
- **Design-system reuse:** existing components, tokens, patterns, and intentional
  deviations.
- **Responsive + accessibility:** keyboard/focus behavior, semantics, contrast,
  touch targets, motion, and layout changes across relevant viewports.
- **Open choices:** any material UX decision that evidence cannot resolve and
  therefore needs the Owner.

Do not invent screens or polish that are outside the Product-approved scope.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-design/scripts/xdh" ] && XDH="$d/x-plan-design/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

## Capability ladder

Detect **Image Generate**, **Image Display**, and **Image Compare** independently.
Record each as `available` or `unavailable` with evidence. Missing capability
downgrades the design workflow; it does not lower the completion standard and is
not itself a blocker.

For UI work, prefer comparable alternatives rather than presenting the first
idea as final:

1. If Image Generate is available, produce 2–3 meaningfully different variants
   bound to the same planning fingerprint.
2. If Image Display is available, show the variants; otherwise preserve the
   artifacts and provide concise text summaries.
3. If Image Compare is available, compare them side by side against the same
   criteria; otherwise write the comparison explicitly.
4. Recommend one option and ask the Owner only when the remaining choice is a
   material product/UX decision rather than a technical implementation detail.

If Image Generate is unavailable, create text/wireframe alternatives when a
choice still matters. Capability absence must never turn "no visual exploration"
into an implicit design decision.

## Direct mode

Direct mode requires an explicit plan target: the user names an existing `IS` /
`SP` document. Inspect the current product scope, existing UI/design system, and
relevant implementation evidence before editing. Improve that plan in place by
refining `## Current → Desired Behavior`, `## Design Facet`, and design Owner
Decisions; write nothing outside the plan except optional design artifacts in the
prepared design directory.

When staging design artifacts, prepare a directory bound to the current
fingerprint:

```bash
xdh design prepare --slug <slug> --fingerprint <fp> \
  --image-generate <available|unavailable> \
  --image-display <available|unavailable> \
  --image-compare <available|unavailable>
```

Pass all three capability results explicitly after inspecting the current host's
tools; there are no environment-variable defaults. `X_DESIGN_DIR` is the
prepared directory and `X_DESIGN_REUSED` reports deterministic reuse. Store the
brief, variant metadata/artifacts or text alternatives, comparison, and approved
selection there when those artifacts are needed.

Direct mode never creates an `IS` / `SP` / `WG` and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. It must
follow `references/facet-contract.md`.

The facet reads the item's `Design facet` / `Design evidence` fields,
`## Current → Desired Behavior`, `## Scope`, the completed Product constraints,
and relevant design Owner Decisions. It resolves the design review checklist and
writes back only through the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet design --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>`. Completion
records `completed@<current fingerprint>`; the fingerprint is reported by the
read-only `xdh plan fingerprint <item>`.

The `## Design Facet` section must capture the resolved UX structure and states,
design-system reuse, responsive/accessibility constraints, capability ladder,
variant/comparison evidence when applicable, and the selected/recommended
direction. A screenshot alone is not sufficient evidence.

A missing Image Generate / Display / Compare capability downgrades the method
rather than blocks it. The facet blocks only when a material UX decision cannot
be resolved from evidence and a later Owner response cannot currently be
obtained; otherwise ask clearly, record the pending decision, and stop this turn.

If an Owner decision changes a fingerprinted canonical behavior or scope input,
return control to `x-plan` so the orchestrator can apply the accepted canonical
edit, recompute the fingerprint, accept the decision at the new fingerprint,
and re-dispatch affected facets. Design does not rewrite canonical fingerprint
inputs in Facet mode.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Provenance

Merges the Owner's Spec-Finalization prompt with the UX / interaction discipline
of gstack `spec` (snapshot `d078622`, MIT). The independent capability ladder,
variant fallback behavior, and concern-based Design facet are specific to this
framework. The facet contract is bundled at `references/facet-contract.md` at
runtime.
