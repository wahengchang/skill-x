---
name: x-plan-devex
description: Resolve the DevEx facet of a planning item — the developer experience from setup through first change, test, debug, and CI/release — starting from the project's shared survey and verifying evidence for the journey stages this item actually touches; use as the DevEx specialist inside x-plan orchestration, or standalone to improve an existing plan's DevEx section in place.
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

Direct mode starts from `xdh survey ensure`, whose `## DevEx commands` section
holds the project's mechanically knowable journey (Make targets, package
scripts, CI steps), then verifies **the stages this item actually touches**
against real evidence: a command that ran, a config file that exists, a pipeline
step that is defined. Untouched stages are named as untouched, not re-verified.
It never fills a gap by assumption: an unverifiable stage that the item does
touch is reported, not guessed. Direct mode never creates an `IS` / `SP` / `WG`
and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. Read
`references/facet-contract.md` and follow it.

The orchestrator hands over the item's file path, the facet name, and the
current fingerprint. Resolve the devex facet and write back through the sole
Facet-mode writer:

```bash
xdh plan facet set <item> --facet devex --status <value> --evidence <ref> [--section-file <f>]
```

Everything else about this facet — intake, evidence, permitted fields, the
status vocabulary, deferral rules and forbidden lifecycle mutations — is in
`references/facet-contract.md`. Follow it there; it is the canonical text and
restating it here only doubled what a plan loads into context.

