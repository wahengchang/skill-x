# Facet dispatch

What `x-plan` needs in order to run a multi-facet route: who owns each facet,
what to hand them, what to check on return, and how to recover when the
fingerprint rotates.

The full facet contracts are **not** duplicated here. Each specialist bundles
its own at `references/facet-contract.md` and reads it when it runs; the
orchestrator reading them too put the same ~12 KB into context twice per plan
without informing any decision the orchestrator makes.

## Per facet

| Facet | Specialist skill | Writes only | Section |
|---|---|---|---|
| product | `x-plan-product` | `Product facet`, `Product evidence` | `## Product Facet` |
| design | `x-plan-design` | `Design facet`, `Design evidence` | `## Design Facet` |
| devex | `x-plan-devex` | `DevEx facet`, `DevEx evidence` | `## DevEx Facet` |
| engineering | `x-plan-eng` | `Engineering facet`, `Engineering evidence` | `## Engineering Facet` |

Order is fixed and sequential, one facet at a time:

```text
Product? → Design? → DevEx? → Engineering (required)
```

Engineering is mandatory and always last. A Spike is always `engineering` alone,
and so is the default route — an engineering-only route never reaches this file,
because `x-plan` hands it to `x-plan-eng` Direct mode instead.

## What to hand a specialist

Three things, every time:

1. the item's **file path** (the `X_ITEM_FILE` the creating command reported —
   never the bare `IS-001`);
2. its facet name;
3. the current fingerprint from `xdh plan fingerprint <item>`, re-read
   immediately before this dispatch.

Nothing else. The specialist reads its own contract. One that has to guess the
fingerprint will guess a stale one.

## Status values a specialist may record

```
pending | in-progress | blocked | completed@<fp> | deferred-owner@<fp> | deferred-missing@<fp>
```

All facet writes go through the single Facet-mode writer:

```bash
xdh plan facet set <item> --facet <facet> --status <value> --evidence <ref> [--section-file <f>]
```

## What to verify when a specialist returns

- It wrote **only** its own two fields and its own `## <Facet> Facet` section.
- Any `completed` / `deferred-*` value carries the fingerprint you handed it,
  not an older one. Never carry a stale completion forward because the prose
  still looks right.
- `deferred-owner@<fp>` and `deferred-missing@<fp>` each need an accepted Owner
  Decision **naming that same facet** at that same fingerprint, or `plan check`
  rejects it as `facet=<f> status=deferred-unaccepted`. "Ship without the design
  facet?" is a design row, not a product one, however product-shaped the
  question feels.
- `deferred-owner` is an Owner-sanctioned skip. `deferred-missing` is for a
  specialist that cannot run on this host at all — never for a capability
  missing *inside* a specialist, which downgrades its method rather than its
  status. Never synthesize the missing specialist's reasoning yourself.

## Owner Decision rows

Batch homogeneous Owner decisions into one brief; split genuinely different
questions into separate groups. A question limit is not a licence to guess: it
must never silently apply a default to a facet decision.

Decisions live in one ID-keyed table and move in one direction. A pending row
carries the **recommended** answer in its `Decision` cell and `—` as its
fingerprint; the accepted row carries the Owner's answer and the fingerprint it
was accepted at. Use the same OD ID for both — never edit the table with a
generic text rewrite:

```bash
"$XDH" plan decision set <item> --id OD-001 --facet <facet> \
  --question "<question>" --decision "<recommendation>" --state pending
"$XDH" plan decision set <item> --id OD-001 --facet <facet> \
  --question "<question>" --decision "<owner answer>" --state accepted@<fp>
```

Only `product` may open its own row, atomically with its `blocked` status. For
design, devex and engineering the specialist reports the question and blocks;
the orchestrator opens the row.

If the Owner's answer changes a fingerprinted input, apply the canonical edit
**before** recording the acceptance: the pending row survives the edit — its
fingerprint cell is `—` — so the pending → accepted transition then lands on the
new fingerprint in one move, and the affected facets are re-run from the
earliest one touched. Accepting first and editing after is what strands a row.

## Re-anchoring after a fingerprint change

A shared section edited after a facet completed shows up at the next check as
`BLOCKER facet=<f> status=stale expected=<new> actual=completed@<old>`. Never
force past it; re-anchor deliberately:

1. Re-read the fingerprint with `plan fingerprint` and take the new value.
2. Re-run the facets whose reasoning the change actually touches, starting from
   the earliest one, and let each re-record itself at the new fingerprint.
3. For a facet whose conclusion the change genuinely does not affect, re-stamp
   it in one command instead of re-deriving it:

   ```bash
   "$XDH" plan facet set <item> --facet <facet> --status completed --reaffirm
   ```

   `--reaffirm` carries the existing evidence and facet section forward and
   re-anchors the status to the current fingerprint. It only moves a status
   sideways: the facet must already hold that same status at some fingerprint,
   so it can never manufacture a completion (`status=reaffirm-not-recorded`).
   Reaffirm only after re-reading the facet's section and confirming the
   conclusion still holds — it shortens recording, not thinking.
4. Decisions still `pending` come along for free — their fingerprint cell is
   `—`, so accepting them now lands on the new value.

Purely cosmetic edits no longer rotate the fingerprint at all: the serialization
normalizes tabs, repeated spaces, trailing whitespace and repeated blank lines
before hashing. Reflowing a paragraph across different line breaks still counts
as a change, because line structure is preserved.

Only step 4 can trap you. An **already accepted** decision cannot be moved: the
writer permits pending → accepted and nothing else, so re-accepting the same OD
ID at a new fingerprint fails with `decision=<id> status=id-collision`. Carry
that answer forward under a fresh OD ID, starting from a pending row. With
`product` in the route this is not optional — `plan check` rejects a stale
accepted product row outright (`state=stale-product re-anchor-required`).

## Lifecycle operations no facet may perform

`item new`, `wg new`, branch or worktree creation, the generic `field set`, and
`plan ready`. Those belong to the orchestrator.
