# Third-Party Notices

## gstack

The `x-*` development-cycle skill set (`x-discovery`, `x-plan-eng`, `x-review`,
`x-debug`, `x-ship`, `x-housekeeping`) adapts workflow methodology from
**garrytan/gstack**.

- Repository: <https://github.com/garrytan/gstack>
- Snapshot referenced: `d078622b73539fc1a7a27e709861e9b6b058ae98` (v1.62.0.0)
- License: MIT — <https://github.com/garrytan/gstack/blob/d078622b73539fc1a7a27e709861e9b6b058ae98/LICENSE>

### What was borrowed

Methodology and discipline only: explicit workflow boundaries, repository-first
investigation, artifact handoff between stages, the
architecture / data-flow / failure-mode / test standard for an executable
specification, independent "outside voice" review, root-cause-first debugging
with a regression test that fails without the fix, idempotent shipping with PR
create-or-update, and the documentation blast-radius audit.

The upstream files consulted are cited per skill in the `## Provenance` section
of each `commands-src/x-*/SKILL.md`.

### What was not borrowed

No gstack source code, generated preamble, or substantial prompt text is
included in this repository. The following upstream behaviors are deliberately
excluded: the generated shared preamble, telemetry / analytics / gbrain, the
global `~/.gstack` state directory, the browser and QA daemons, the
auto-updater and installer infrastructure, Claude-only hooks and routing, the
reviewer auto-fix behavior (this repository requires a read-only reviewer), and
gstack's VERSION / CHANGELOG queue policy.

Should any gstack code or substantial prompt text be copied into this
repository in the future, the applicable MIT copyright and permission notice
must be retained with it.
