---
name: x-plan-devex
description: Resolve the internal developer-experience facet of a planning item — setup, first change, test, debug, CI/release, and contributor workflow — grounding current-state claims in repository evidence and turning desired changes into executable journey contracts; use inside x-plan orchestration or standalone to improve an existing plan's DevEx section in place.
---

# x-plan-devex

Own the **devex** facet: the internal engineering-team journey from a fresh
checkout to a shipped change — setup, first change, test, debug, and CI/release.
External user/developer-facing API / CLI / SDK behavior belongs to Product, not
DevEx. This skill never writes product code and never creates IS / SP / WG
documents.

## When to use

- `x-plan` dispatches this skill when the work changes contributor setup, build,
  test, debug, CI/release, maintainer docs, or the first-change feedback loop.
- Standalone: a plan already exists and its internal developer-experience story
  needs to be improved in place.

## Journey checklist

Resolve each applicable stage as **current evidence → desired contract**:

- **setup:** prerequisites, bootstrap/install command, generated state, and a
  clear success signal;
- **first change:** where a contributor edits, how fast feedback appears, and
  which command/path proves the change is wired correctly;
- **test:** exact local commands, relevant test layers, fixtures/dependencies,
  and failure signals;
- **debug:** reproduction path, logs/traces/diagnostics, inspection commands, and
  the expected path from symptom to evidence;
- **CI/release:** pipeline job or release path, required checks, artifacts,
  documentation, and the handoff from local success to shipped change.

A stage that truly does not apply may be marked not applicable in the DevEx
section with a reason. Do not silently omit a stage.

## Evidence model

This is a planning skill, not a post-implementation audit. Separate facts about
the current repository from the target contract:

- **Current-state claims require real evidence**: a command that ran, a file or
  config that exists, a documented workflow, or a pipeline step that is defined.
- **Desired behavior may be new**: specify the exact command/path/expected
  result/failure behavior that implementation must create, even though that
  target does not exist yet.

Never pretend a future command already works. Conversely, do not block planning
merely because the feature being planned has not been implemented yet.

## Toolkit

```bash
for d in ~/.claude/skills ~/.codex/skills ~/.agents/skills ~/.config/opencode/skills; do
  [ -x "$d/x-plan-devex/scripts/xdh" ] && XDH="$d/x-plan-devex/scripts/xdh" && break
done
"$XDH" paths
```

The facet contract this skill follows is bundled at `references/facet-contract.md`.

Every `<item>` below is the item's **file path** under `.dev-hub/`, normally the
path handed over by `x-plan` as `X_ITEM_FILE`; never substitute only `IS-001` or
`SP-001`. In Facet mode use the fingerprint handed over by the orchestrator and
confirm it with `xdh plan fingerprint <item>`.

## Direct mode

Direct mode requires an explicit plan target: the user names an existing `IS` /
`SP` document. Inspect the repository before editing. Improve that plan in place
by refining `## Scope`, `## Current → Desired Behavior`, the `## DevEx Facet`
section, and DevEx Owner Decisions; write nothing outside the plan.

For every applicable journey stage, distinguish observed current behavior from
the executable desired contract. An unverifiable **current** claim is reported,
not guessed; a **future** stage is acceptable when the plan specifies what must
exist and how implementation/review will verify it.

Direct mode never creates an `IS` / `SP` / `WG` and never writes product code.

## Facet mode

This is the portion that runs as a facet inside `x-plan` orchestration. It must
follow `references/facet-contract.md`.

The facet reads the item's `DevEx facet` / `DevEx evidence` fields,
`## Scope`, `## Current → Desired Behavior`, relevant completed Product/Design
constraints, repository build/test/debug/CI evidence, and DevEx Owner Decisions.
It writes back only through the sole Facet-mode writer:

```bash
xdh plan facet set <item> --facet devex --status <value> --evidence <ref> [--section-file <f>]
```

`<value>` is one of `pending | in-progress | blocked |
completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>`. Completion
records `completed@<current fingerprint>`; the fingerprint is reported by the
read-only `xdh plan fingerprint <item>`.

The two deferred values are Owner-sanctioned exceptions, never shortcuts past
work DevEx could have completed. `plan check` accepts a DevEx deferral only when
a DevEx Owner Decision is accepted at the same fingerprint; otherwise it fails
with `facet=devex status=deferred-unaccepted`. Any status carrying an old
fingerprint is stale.

The `## DevEx Facet` section records the full journey — setup → first change →
test → debug → CI/release — with current evidence and the desired contract for
each applicable stage. Never fill a current-state gap by assumption, and never
mistake "not implemented yet" for "cannot be planned".

If a gap requires a product/policy choice rather than an engineering design
choice, record `blocked` and return a numbered decision brief to `x-plan` with a
question, recommended answer, and consequences. DevEx does **not** insert the
Owner Decision row; the orchestrator owns that row for non-Product facets.

If the Owner answer changes a fingerprinted canonical scope/behavior input,
`x-plan` applies the accepted edit while the decision is still pending,
recomputes the fingerprint, accepts the same pending OD ID at the new
fingerprint, and re-dispatches affected facets. If an already-accepted decision
later becomes stale, do not invent a new OD ID as if that removed the old stale
row; return the machine-layer blocker to `x-plan`.

Do not block on a normal technical choice: make the best evidence-backed call
and record the rationale. Block only when required evidence cannot be obtained,
a material Owner-only decision cannot be obtained, or the target journey cannot
be specified safely enough for implementation and review.

This facet must never create an item (`item new`), create a Work Group
(`wg new`), create a worktree or branch, run the generic `field set`, or run
`plan ready`. The facet's only item mutation is the `xdh plan facet set` write
above.

## Provenance

Merges the Owner's Spec-Finalization prompt with the developer-journey
verification discipline of gstack `spec` (snapshot `d078622`, MIT). The
setup → first change → test → debug → CI/release evidence chain and explicit
current-evidence / future-contract split are specific to this framework. The
facet contract is bundled at `references/facet-contract.md` at runtime.
