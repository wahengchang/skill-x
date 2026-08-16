---
name: x-plan-devex
description: Resolve the DevEx facet of a planning item — the developer experience from setup through first change, test, debug, and CI/release — verifying and recording evidence for each stage of the journey; use as the DevEx specialist inside x-plan orchestration, or standalone to improve an existing plan's DevEx section in place.
---

# x-plan-devex

Own the **devex** facet: the journey a developer takes from a fresh checkout to
a shipped change — setup, first change, test, debug, and CI/release. This skill
never writes product code and never creates IS / SP / WG documents.

## When to use

- `x-plan` dispatches this skill to resolve the devex facet of one item.
- Standalone: a plan already exists and its developer-experience story needs to
  be improved in place.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-devex/scripts/xdh" ] && XDH="$d/x-plan-devex/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

`<item>` is always the item's **file path** under `.dev-hub/`, never the bare
`IS-001`. In facet mode the orchestrator hands it over together with the current
fingerprint; do not re-derive either from the conversation.

## Direct mode

Direct mode requires an explicit plan target: the user names an existing `IS` /
`SP` document. It improves that plan in place — refining `## Scope` and the
`## DevEx Facet` section — and writes nothing else.

Direct mode verifies each stage of the developer journey — setup, first change,
test, debug, and CI/release — against real evidence (a command that ran, a
config file that exists, a pipeline step that is defined). It never fills a gap
by assumption: an unverifiable stage is reported, not guessed. Direct mode never
creates an `IS` / `SP` / `WG` and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. It must
follow `references/facet-contract.md`.

The facet reads the item's `DevEx facet` / `DevEx evidence` fields and its
`## Scope` and `## Current → Desired Behavior` sections, resolves the devex
facet, and writes back via the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet devex --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>`. Completion
records `completed@<current fingerprint>`; the fingerprint is reported by the
read-only `xdh plan fingerprint <item>`.

The two deferred values are Owner-sanctioned, never a shortcut past work the
facet could have done: `plan check` accepts a deferral only when an Owner
Decision for this facet is accepted at the same fingerprint, and otherwise
rejects it as `facet=devex status=deferred-unaccepted`. A status carrying a
fingerprint must carry the current one; anything older is reported as stale.

The devex facet records evidence for the full journey — setup → first change →
test → debug → CI/release — each stage backed by real evidence, never an
assumption.

A stage that cannot be verified is written into `## DevEx Facet` as an
unverified gap. If it needs an Owner call, the facet reports the question with a
`blocked` status and a recommended answer, and the orchestrator opens the
decision row; DevEx cannot open one itself — the row writer accepts an atomic
facet-and-row write only for `product`.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Provenance

Merges the Owner's Spec-Finalization prompt with the developer-journey
verification discipline of gstack `spec` (snapshot `d078622`, MIT). The
setup → first change → test → debug → CI/release evidence chain is new to this
framework. The facet contract is the single canonical source and lives in
`commands-src/_x-shared/facets/devex-facet-contract.md`.
