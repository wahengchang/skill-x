# Development instructions

- `skills/` is the only skill source and the public distribution. Edit it
  directly; do not add a generated source tree or repository-specific lifecycle
  scripts.
- Keep every skill self-contained. Relative links and runtime files must stay
  inside that skill's directory.
- Keep the skill directory name equal to the `name` in its `SKILL.md`
  frontmatter. Names use lowercase letters, digits, and hyphens.
- Preserve the `x-*` and `q-*` namespaces. New quick Skill Q workflows belong
  here under `skills/q-*`; do not update the separate `skill-q` repository as
  part of this repository's changes.
- Use native CLI commands for lifecycle tasks: `npx skills init`,
  `npx skills add`, `npx skills update`, and `npx skills remove`.
- Before finishing, run `npx skills add . --list` and validate each changed or
  added skill's frontmatter and referenced local files.
