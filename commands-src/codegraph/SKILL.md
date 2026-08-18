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

## Notes

- `index` requires a prior `init`; use `sync` for cheap incremental updates.
- `impact` defaults to traversal depth 2 — raise `-d` for a deeper blast radius.
- `query` is substring-based; refine with `-k` (e.g. `function`, `class`).
- Supported languages (v1.5.0): TypeScript/JavaScript, Python, Go, Rust, Java,
  C/C++, C#, Ruby, PHP, Swift, Kotlin, Scala, Dart, Lua, Solidity, Terraform,
  Nix, and more — but no shell, Markdown, or YAML. Shell-heavy projects index
  almost nothing.
