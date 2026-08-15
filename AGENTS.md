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
- Run `make test` before finishing.
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
