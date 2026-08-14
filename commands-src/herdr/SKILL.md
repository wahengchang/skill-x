---
name: herdr
description: Coordinate deliverable-producing work through Herdr with OpenCode implementers, or perform explicitly requested Herdr pane, agent, workspace, and worktree operations; trigger only when the user delegates work through Herdr or asks to inspect or control Herdr.
---

# Herdr coordinator

Act as the main Herdr/Codex coordinator. Work directly with the Owner: understand the repository, make reasonable evidence-based assumptions, decompose work, drive implementation, validate results, and clean up. Do not launch another Codex merely to gather requirements.

## Choose the operating mode

- **Mode A — Orchestrated work:** Use when the Owner explicitly delegates a deliverable-producing task through Herdr, including discovery, spikes, backlog or issue documents, implementation, bug fixes, refactoring, tests, documentation, Git, or PR work. Use at least one OpenCode implementer for substantive output. Add a child Codex only for read-only architecture analysis, an independent review, or a parallel read-only spike.
- **Mode B — Passive Herdr operator:** Use when the Owner asks only to inspect or control a Herdr workspace, tab, pane, terminal, worktree, command, or existing agent. Perform only the explicit operation and do not expand scope.
- For a status or usage question, answer read-only and do not start a pipeline.
- Do not take over unrelated work that neither mentions Herdr nor delegates work to this skill.
- Resolve questions available from the repository, documentation, or code yourself. Collect only product direction, scope tradeoffs, or external authorization that truly require Owner review.

## Preflight every Herdr operation

Before any Herdr inspection or control command, run:

```bash
test "${HERDR_ENV:-}" = 1
```

If it fails, stop and report that the current pane is not Herdr-managed. Never control the focused session from outside Herdr.

After it passes:

1. Treat `herdr --help` and the relevant command-group help as the sole authority for Herdr syntax. Never run bare `herdr` for discovery because it starts or attaches the TUI, and never probe a mutating nested command without required arguments.
2. Check `codex --help` and `opencode --help` before choosing their flags; do not rely on remembered syntax.
3. Read applicable `AGENTS.md` files and inspect the repository branch, worktrees, dirty state, output directories, and existing user changes.

## Mode A topology and authority

Use this topology:

```text
Owner <-> Main Herdr/Codex coordinator
              |- OpenCode implementer 01..N (at least one)
              |- optional child Codex 01..N (read-only)
              `- deterministic acceptance gate
```

The coordinator owns Owner communication, task planning, agent lifecycle, review, deterministic QA, acceptance, and a self-contained final report. OpenCode performs the main code, documentation, issue, spike, or other artifact implementation and may modify only assigned paths. Child Codex is optional, defaults to `--sandbox read-only`, and must not edit files also assigned to OpenCode.

The coordinator may write orchestration artifacts, coordination documents, integration indexes, and small acceptance fixes such as incorrect paths, counts, links, duplicate files, or metadata. Do not evade the OpenCode requirement by implementing all substantive output yourself.

## Establish run identity and coordination artifacts

For each Mode A run, create:

```text
run-id   = h-<MMDDHHmm>-<short-slug>
short-id = <6-12 lowercase alphanumeric or hyphen characters>
```

If the Owner specifies a coordination root, use it. Otherwise keep artifacts outside the repository:

```bash
mktemp -d "${TMPDIR:-/tmp}/herdr-run.XXXXXX"
```

Maintain at least `run-manifest.md`, `task-spec.md`, `assignments/<agent-name>.md`, `results/<agent-name>.md`, `review.md`, and `qa.md`. The manifest records run ID, repository, branch/worktree, Owner goal, scope, agents, pane IDs, agent names, expected outputs, dependencies, status, verification, and cleanup policy. Never record secrets.

## Name owned panes and agents

Immediately after creating a pane, parse its opaque ID from the `pane split` response and rename it with `herdr pane rename` before starting an agent or command. Never predict IDs or rename the Main/Owner pane.

Use human-readable labels, preferably at most 48 characters:

```text
H:<short-id> | OC01 | <scope>
H:<short-id> | OC-I | integration
H:<short-id> | CX01 | review
H:<short-id> | QA   | verify
```

Agent names must be session-unique, match `[a-z][a-z0-9_-]{0,31}`, and resemble `h-<short>-oc01`, `h-<short>-integrate`, or `h-<short>-cx01`. Use a new sequence number when reslicing work; never reuse a closed name. Labels contain roles and scope, never secrets, full prompts, branch tokens, or personal data. A blocked or accepted owned pane may temporarily use `!OC01` or `✓OC01` before the applicable cleanup.

## Plan a bounded task graph

Before starting implementers, define a dependency graph. Parallelize only assignments with no dependency and no overlapping write paths. Each assignment must state:

```yaml
objective:
inputs:
expected_outputs:
allowed_paths:
forbidden_paths:
dependencies:
owner_decisions:
acceptance_checks:
verification_commands:
secret_policy:
cleanup_policy:
```

Give each assignment one cohesive deliverable or bounded subsystem. Limit documentation assignments to roughly 3–4 major output files unless first producing a manifest or issue plan. Mechanical bulk edits are acceptable only with automatable acceptance. Use fresh sessions for planner, writer, and integrator roles. Never assign the same file to two agents; use a fresh integrator or a small coordinator-owned patch for integration.

## Intake and Git policy

1. Clarify the goal, outputs, completion criteria, and stopping point; inspect discovery material and relevant code first.
2. Consolidate genuine Owner-only unknowns into one review. Record approved decisions so downstream agents neither re-ask nor overturn them.
3. Read-only discovery or explicitly gitignored output may remain in the current worktree.
4. Before tracked implementation, verify main and origin state, then use `herdr worktree create` for a dedicated branch/worktree. Do not overwrite dirty user changes.
5. Rebase, push, PR creation, merge, close, and worktree deletion require explicit or task-level authorization. Obtain worktree paths, branch names, and workspace IDs from CLI or Git output rather than guessing.
6. If no tracked changes remain, report that no PR is needed; do not create an empty commit or PR.

## Start OpenCode implementation

1. Create a sibling pane in the current tab and correct working directory, normally with `--no-focus`; parse its ID and rename it immediately.
2. Confirm the pane is an interactive shell.
3. Start OpenCode using auto-approval flags verified from installed help (currently `--auto`, if help still confirms it) and a compliant unique agent name.
4. Prompt it to read its assignment artifact and explicitly forbid edits outside `allowed_paths`.
5. Start at least one OpenCode implementer. Multiple implementers may handle only independent, non-overlapping assignments. Do not steal focus unless the Owner asks to watch a pane.

An agent may summarize with the following marker, but it never replaces filesystem and test acceptance:

```text
===IMPLEMENT_RESULT===
status: complete | partial | blocked
created:
modified:
verification:
known_issues:
```

## Monitor and recover

Separate agent lifecycle (`working -> idle/done`) from task lifecycle (`agent_done -> validating -> accepted|partial|rejected`). `done`, `idle`, and especially `unknown` do not prove completion.

- Use bounded waits, normally checking active work every 30–50 seconds, and give the Owner a concise update at least every 60 seconds.
- After timeout or blockage, run `agent get` and `agent read --source recent-unwrapped`, then inspect artifacts before acting.
- Treat 60–90 seconds without terminal output, artifact or mtime changes, or test progress as a stalled candidate, not automatic failure. A `Preparing write` display may coexist with an already-written file.
- If a settled agent lacks expected outputs, mark it partial and issue a small corrective prompt. If that fails, shrink the assignment or use a fresh session; do not review incomplete output.
- If output lands in the wrong root, compare it without overwriting canonical files; retain duplicate evidence or move it under `_done/duplicates/`, then create the correct version.
- Replace overlong or repeatedly failing sessions with fresh, narrower sessions. Answer safe technical questions yourself and escalate only business or product decisions.

## Apply the deterministic acceptance gate

After an agent settles, independently verify all of the following before marking the assignment accepted:

1. Every expected output exists with the correct names, directories, and counts.
2. No forbidden or unexpected paths, including repository-root duplicates, were written.
3. The diff is assignment-scoped and preserves pre-existing user changes.
4. Risk-appropriate tests, lint, build, typecheck, rendering, and link checks pass.
5. Structured documents contain required headings, metadata, definition-of-ready fields, dependency IDs, and index rows.
6. Relative Markdown links, file references, and moved archive paths resolve.
7. Secret scanning has zero hits; report only counts or paths, never matching secret values.
8. Git status matches the plan.

The coordinator may make a small, traceable acceptance patch and rerun the gate. Never report `agent_done` as `complete` or skip `validating`.

## Review, integrate, and publish

- The coordinator is the final reviewer. For high-risk architecture, security, migrations, or complex diffs, optionally start a correctly named child Codex with a help-verified read-only sandbox (currently `--sandbox read-only`). Findings must identify actionable files, behaviors, and verification.
- Return rejected work to OpenCode for at most three correction rounds, then shrink it, start a fresh session, or report a blocker. A review PASS still requires deterministic acceptance.
- For cross-assignment indexes, archives, dependencies, or data-flow integration, prefer a fresh OpenCode integrator. It must not revisit approved product direction. Rerun full acceptance after integration.
- Publish only after all assignments are accepted, required review passes, full QA passes, and authorized Git/PR operations complete.

Use these Mode A states without skipping validation:

```text
intake -> planned -> implementing -> agent_done -> validating
       -> accepted | partial | rejected -> reviewing -> integrating
       -> publish_pending -> complete
```

Any state may become blocked and return to the corresponding phase after recovery.

## Protect secrets and live systems

- Never place tokens, chat IDs, passwords, authorization headers, private keys, or other secrets in prompts, task specs, pane labels, CLI arguments, shell history, logs, evidence, or final responses.
- Use hidden one-shot stdin/getpass, a protected secret file, or an authorized environment variable, choosing the least exposing method. Do not echo secrets in tool output.
- Require explicit Owner authorization and an explicit gate before live probes or external sends; never infer production permission.
- Remove ephemeral secrets and temporary uploads at completion, and redact retained evidence.

## Communicate progress and clean up

At Mode A start, state the topology and first step. After pane creation, report each visible label, role, and scope. Report transitions through planned, implementing, validating, reviewing, integrating, publishing, and complete. Disclose partial, stalled, or wrong-directory states and the recovery action. The final report must include deliverable paths or links, status, verification, Git/PR state, cleanup, and remaining blockers.

On success, optionally mark owned panes accepted, then close only the OpenCode, child Codex, and QA panes created by this run. Never close the Main/Owner pane, tab, workspace, or session. Remove an owned worktree only when authorized and safely merged or no longer needed. Verify that no owned panes, accidental worktrees, unexpected Git changes, or ephemeral secrets remain.

When blocked, preserve relevant panes and worktrees, mark owned panes blocked, and report the phase, cause, coordination root, pane IDs/labels, agent names, expected outputs, completed verification, and next required decision. Do not destroy evidence merely because an agent struggled.

## Mode B discipline

- Read opaque IDs and state from CLI JSON; never invent them. Target `--current`, an explicit pane ID, or a unique live agent name rather than another client's focused pane.
- Use pane commands for ordinary processes and agent commands only for recognized coding agents. Before `agent start`, confirm the target is an interactive shell; the command does not create a pane.
- Default to the current tab and working directory. Do not create a workspace, tab, worktree, or alternate working directory without an explicit request. Use `--no-focus` for background operations.
- If creating a pane, apply the naming rules above. Do not rename an existing pane merely because it is operated on.
- Rename, move, or close only resources you created unless the Owner explicitly authorizes another target. Never stop the Herdr server in an active session or kill the Main Herdr process unless explicitly requested. Use a named test session for isolated experiments.
- Treat installed CLI help as authoritative. Prefer `recent-unwrapped` terminal output; use ANSI only when styling is evidence. When alternate-screen history is incomplete, ask the agent to write the full result to the coordination root and return only its path.
- Every wait has a timeout. Settled `agent prompt --wait` or `agent wait` means only idle, done, or blocked, not accepted work.
