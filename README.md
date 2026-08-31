# skill-x

`skill-x` is a direct [Agent Skills](https://agentskills.io/) repository for the
X and Q skill sets. Every installable skill lives under `skills/`; there is no
generated copy, repository-specific installer, build step, or lifecycle wrapper.

## Install

List the available skills:

```bash
npx skills add wahengchang/skill-x --list
```

Install interactively:

```bash
npx skills add wahengchang/skill-x
```

Install selected skills for selected agents:

```bash
npx skills add wahengchang/skill-x \
  --skill x-plan --skill x-debug --skill q-ship \
  --agent claude-code --agent codex --agent opencode
```

Project-local installation is the default. Add `--global` for a user-global
installation:

```bash
npx skills add wahengchang/skill-x --global
```

## Manage installed skills

Use the native `skills` CLI for the complete lifecycle:

```bash
npx skills list
npx skills update
npx skills remove x-plan
```

Use the same scope when updating or removing global skills:

```bash
npx skills update --global
npx skills remove --global x-plan
```

There is no separate `uninstall` command; the native command is
`npx skills remove`.

## Create or edit a skill

`skills/` is the source of truth. Edit a skill there directly. To scaffold a new
one with the native CLI:

```bash
cd skills
npx skills init my-skill
```

The directory name and the `name` in `SKILL.md` frontmatter must match. This
repository does not require a build after editing.

## Included skill sets

- `x-*`: the original Skill X workflows and utilities.
- `q-*`: the lightweight Skill Q workflows, now distributed from this
  repository.
- Unprefixed skills: standalone utilities such as `ai-x`, `codegraph`,
  `handoff`, and `to-spec`.

Run `npx skills add wahengchang/skill-x --list` for the current complete list.

## Repository layout

```text
skills/
  <skill-name>/
    SKILL.md
    scripts/       # optional
    references/    # optional
    assets/        # optional
```

Some X skills include shared scripts and templates inside their own directory.
This duplication is intentional: installing one skill must produce a complete,
self-contained skill.
