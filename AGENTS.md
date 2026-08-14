# Codex Development Instructions

- Treat `commands-src/` as the source of truth for skills. Never manually edit the generated files in `commands/`.
- After changing a skill or `_shared/update-check-header.md`, run `bin/build.sh` and commit the corresponding generated changes in `commands/` so both directories stay in sync.
- Run `make test` before finishing.
- Follow the workflows, naming rules, and design decisions documented in `CONTRIBUTING.md` and `ARCHITECTURE.md`.
- Keep changes focused and avoid unrelated behavior changes.
