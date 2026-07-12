# Skills repo

Public repo of agent skills installable via skills.sh (`npx skills@latest add alexnikolis/skills`).

## Structure

- Each skill lives in `skills/<name>/` with a `SKILL.md` entry point (YAML frontmatter: `name`, `description`, optional `disable-model-invocation`).
- Supporting files (templates, scripts, references) sit alongside the `SKILL.md` and are installed with the skill.

## Conventions

- This repo holds the canonical copies. When a skill also exists in `~/.claude/skills/`, edit here and sync outward — never the reverse.
- When adding a skill, add a row to the table in README.md.
