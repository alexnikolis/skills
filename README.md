# Skills

[![skills.sh](https://skills.sh/b/alexnikolis/skills)](https://skills.sh/alexnikolis/skills)

My custom agent skills, installable via [skills.sh](https://skills.sh).

## Install

```bash
npx skills@latest add alexnikolis/skills
```

Pick the skills you want and which coding agents to install them on.

## Skills

| Skill | Description |
| --- | --- |
| [`setup-sdlc-harness`](./skills/setup-sdlc-harness/SKILL.md) | Stamp the autonomous SDLC harness (clear-board orchestrator, stage agents, code-review skill, board convention extensions) into a repo already set up with [mattpocock/skills](https://github.com/mattpocock/skills). Installs a lite variant by default — rigor scoped to the risks the project names — or the full-rigor variant with `full`. |

## Repo layout

Each skill lives in `skills/<name>/` with a `SKILL.md` entry point. Files alongside the `SKILL.md` (templates, scripts, references) are installed with the skill.

## License

[MIT](./LICENSE)
