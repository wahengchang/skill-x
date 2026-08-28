---
name: codegraph
description: Use the CodeGraph CLI to inspect code relationships (callers, callees, blast radius) before refactors or when navigating unfamiliar code.
---

# CodeGraph — Code Intelligence Skill

Use the CodeGraph CLI to understand code relationships before editing. This
skill calls the `codegraph` binary directly — no MCP server or agent
registration required.

## Goal

Avoid unsafe refactors by checking impact before touching symbols that may
affect callers, callees, imports, or downstream files.

## Prerequisites

- Node.js >= 20
- `codegraph` CLI installed: `npm i -g @colbymchenry/codegraph`

## Setup (once per project)

```bash
cd <project-root>
codegraph init        # initialize and build the first index
```

The index lives in `.codegraph/` (add it to `.gitignore`).

## Cost discipline

The commands are not equally cheap, and the difference is the whole reason to
use this instead of grep.

**Ask for relationships first.** `callers`, `callees`, `impact`, `query`,
`files` and `affected` return names, kinds and `file:line` — a few hundred bytes
that say who calls what. Measured on two real projects, the answer to a callers
question came back in 0.2–1.3 KB against 26–243 KB for the files that contain
the symbol. That gap is the point: the graph tells you which few files are worth
opening.

**Use the plain output, not `--json`.** The JSON envelope runs about twice the
bytes for the same facts, and the plain form is already structured.

**`explore` is different in kind.** It returns a compact blast-radius header
*followed by verbatim source* — roughly 11 KB for one query in the measured
case. That is not waste when you were going to read those files anyway (it says
so itself: treat each block as a Read already performed), but it is the wrong
default. Reach for it, or for `node <symbol>`, only once you know which symbol's
body you actually need.

## Core workflow (before risky edits)

1. Confirm the index is fresh: `codegraph status`
2. Find a symbol when the exact name is unknown: `codegraph query <substring>`
3. Inspect blast radius: `codegraph impact <symbol>` (depth 2 by default; widen with `-d`)
4. Drill into edges: `codegraph callers <symbol>` / `codegraph callees <symbol>`
5. Edit only after callers/callees/impact are understood
6. Refresh the index after edits: `codegraph sync`

If the index is stale or new files were added, rebuild it: `codegraph index`.

## Command reference

| Command | Purpose |
| --- | --- |
| `codegraph init [path]` | Initialize a project and build the first index |
| `codegraph index [path]` | Rebuild the full index from scratch (requires prior `init`) |
| `codegraph sync [path]` | Incrementally sync changes since the last index |
| `codegraph status [path]` | Index health, freshness, and statistics |
| `codegraph query <search>` | Symbol substring lookup (`-k kind`, `-l limit`, `-j` JSON) |
| `codegraph callers <symbol>` | Inbound call sites — who calls this symbol |
| `codegraph callees <symbol>` | Outbound dependencies — what this symbol calls |
| `codegraph impact <symbol>` | Blast radius — affected symbols and files (`-d depth`) |
| `codegraph explore <query...>` | Area overview: relevant symbols + call paths |
| `codegraph node <name>` | One symbol's source + caller/callee trail |
| `codegraph files` | Project file structure from the index |
| `codegraph affected [files...]` | Test files affected by changed source files |

`--path <dir>` selects the project; the default is the current directory.

## Traps

These cost correctness, not just tokens.

- **`affected` fails silently.** Its default glob matches `*.test.*` /
  `*.spec.*` only, so a Python suite named `test_*.py` returns "No test files
  affected" — indistinguishable from a genuine empty answer. Always pass
  `-f "<glob>"` matching the project's own convention. And even then it follows
  *import* edges: Playwright-style suites that drive a browser link to nothing,
  so an empty result is never evidence that no test covers the change.
- **Telemetry is on by default.** The CLI reports that it "collects anonymous
  usage stats" on first use. Set `CODEGRAPH_TELEMETRY=0` (or run
  `codegraph telemetry off`) before pointing it at a private repository.
- **`.codegraph/` lands in the project.** It is roughly 6–11 MB and must be
  added to that project's `.gitignore`; `init` does not do it for you.

## Notes

- `index` requires a prior `init`; use `sync` for cheap incremental updates.
- `impact` defaults to traversal depth 2 — raise `-d` for a deeper blast radius.
- `query` is substring-based; refine with `-k` (e.g. `function`, `class`).
- Supported languages (v1.5.0): TypeScript/JavaScript, Python, Go, Rust, Java,
  C/C++, C#, Ruby, PHP, Swift, Kotlin, Scala, Dart, Lua, Solidity, Terraform,
  Nix, and more — but no shell, Markdown, or YAML. Shell-heavy projects index
  almost nothing.
- Indexing is fast enough not to plan around: a 353-file TypeScript project
  indexed in ~1.8s, and `sync` after a one-file edit took ~0.5s. Large
  repositories are the exception — budget minutes, not seconds, for a first
  `init` on tens of thousands of files.
