# Test suites

The repository has two validation paths.

## Fast developer suite

```bash
make test
# equivalent: make test-fast
```

Use this for content-only `commands-src/<name>/SKILL.md` edits, documentation, and other low-risk changes. The fast suite prepares one source-only project fixture and reuses it across three smoke checks so routine validation does not repeat expensive repository/build setup.

It verifies:

- source-only install performs the canonical build and OpenCode shim build;
- shared support files such as `x-discovery/scripts/xdh` are materialized into generated artifacts;
- Claude/Codex/OpenCode targets are installed from the generated artifacts;
- a second sync is idempotent;
- `doctor --strict` passes for the managed installation;
- generated `commands/` and `opencode-commands/` trees remain gitignored/disposable.

Collision ownership, lifecycle/update behavior, bootstrap behavior, target-adapter contracts, and `xdh` regressions remain in the full suite rather than the routine path.

## Full regression suite

```bash
make test-full
```

Use the full suite for changes to `bin/`, `tests/`, `Makefile`, lifecycle behavior, Git update/status behavior, sync/bootstrap, target adapters, `xdh`, executable support code, release-quality validation, or any other higher-risk change.

The target runs every pre-existing regression test without removing or weakening coverage:

| Suite | Command | Existing tests |
|---|---|---:|
| Core integration | `tests/run.sh` | 51 |
| Safety regressions | `tests/pr10-safety-regression.sh` | 3 |
| Target-adapter regressions | `tests/pr15-regression.sh` | 7 |
| **Total** | | **61** |

## Timing and bounded timeouts

Both Make targets run each suite through `tests/run-suite.sh`. The wrapper prints elapsed time and returns a clear non-zero timeout failure if the suite stalls. The watchdog terminates the suite process group so deadlocked child commands do not continue running after the timeout.

Defaults:

- fast suite: 300 seconds;
- each full-suite component: 3600 seconds.

Override the bound when diagnosing a known slow environment:

```bash
SKILL_X_SUITE_TIMEOUT_SECONDS=900 make test
SKILL_X_SUITE_TIMEOUT_SECONDS=7200 make test-full
```

Validate the timeout failure path itself with:

```bash
make test-timeout
```

That target runs a controlled sleep behind a one-second timeout, expects the wrapper to fail non-zero, and checks that the output contains `TIMEOUT`.

All suites keep the existing no-network design. Test installations use temporary project/HOME directories rather than the developer's real agent configuration.
