# Codex Development Instructions

- `commands-src/` and `_shared/` are the only tracked build inputs. Skill content
  lives in `commands-src/<name>/SKILL.md`; `_shared/update-check-header.md` is
  the shared text inserted into every generated skill.
- Generated `commands/`, `opencode-commands/`, and any future artifact trees are
  disposable build outputs (declared in `.gitignore`). Never hand-edit them and
  never commit them; they will be overwritten by `bin/build.sh`.
- After changing a skill or `_shared/update-check-header.md`, run `bin/build.sh`
  so `git status` stays clean of generated directories and so downstream
  `bin/sync-skills.sh` / `bin/cloud-bootstrap.sh` have something to install.
- Run the tests before finishing. Which suite depends on what you touched:
  - **`make test`** (fast, the routine path) is enough for low-risk changes
    that only touch skill content: `commands-src/**/SKILL.md`, skill support
    files, `_shared/update-check-header.md`, or documentation. It covers the
    canonical build, artifact/shim generation, and essential smoke coverage.
  - **`make test-full`** is mandatory for everything else — any change under
    `bin/` (including `bin/targets/`), `tests/`, `install.sh`, `Makefile`, or
    anything affecting lifecycle (`init`/`install`/`sync`/`update`/`uninstall`),
    Git update checks, cloud bootstrap, target adapters, or `xdh` behavior. It
    runs all 61 integration and regression tests.
  - When in doubt, run `make test-full`; it is the release-quality gate.
  - Both suites print per-test elapsed time and a slowest-cases summary, and
    terminate any single test that exceeds `SKILL_X_TEST_TIMEOUT` (default
    240s) as a failure instead of hanging.
- Follow the workflows, naming rules, and design decisions documented in
  `CONTRIBUTING.md` and `ARCHITECTURE.md`.
- Keep changes focused and avoid unrelated behavior changes.

## Adding an AI runtime

The build pipeline separates **common canonical processing** from **target
metadata** (`bin/targets/targets.conf`) and **transform adapters**
(`bin/targets/<adapter>.sh`). When adding a new runtime, pick the lighter path:

- **Canonical-format target** (reads the `$CANONICAL_DEST/<name>/SKILL.md`
  artifact verbatim): append an entry to `CANONICAL_CONSUMERS` in
  `bin/targets/targets.conf`. No adapter script is needed;
  `bin/sync-skills.sh` and `bin/cloud-bootstrap.sh` read that metadata to pick
  deployment paths.
- **Transformed target** (needs a different on-disk representation): add an
  adapter script `bin/targets/<adapter>.sh`, then declare it in
  `TRANSFORMED_TARGETS` as
  `<adapter>:<artifact-directory-under-repo-root>`. Adapters use this action
  contract:

  - `<adapter>.sh build <canonical-staging-dir> <artifact-staging-dir>`
  - `<adapter>.sh sync <artifact-dir>`
  - `<adapter>.sh bootstrap <artifact-dir>`

  The `build` action receives the fully processed canonical staging tree after
  shared header injection and support-file materialization. `bin/build.sh`
  invokes it only after common canonical processing succeeds; sync/bootstrap
  then consume the resulting artifact tree.
