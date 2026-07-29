---
name: setup-sdlc-harness
description: "Stamp the autonomous SDLC harness (clear-board orchestrator, stage agents, tiered code-review skill, board convention extensions) into a repo already set up with mattpocock/skills. Detects the repo's issue-tracker backend (local markdown, GitHub, or GitLab) and stamps matching conventions."
disable-model-invocation: true
---

# Setup SDLC harness

Installs the autonomous board-clearing harness into the current repo. Prerequisite: the repo was set up with `setup-matt-pocock-skills` (has `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`), and its tracker is Local Markdown, GitHub, or GitLab.

## Canonical-copy rule

The templates in this skill's `templates/` directory are the canonical versions. When iterating on agent prompts or the clear-board protocol, edit the templates here and re-run this skill to re-stamp — never edit the stamped copies in a repo directly.

## Steps

1. **Detect the backend**: read the first heading of `docs/agents/issue-tracker.md`.
   - `# Issue tracker: Local Markdown` → `local`
   - `# Issue tracker: GitHub` → `github`
   - `# Issue tracker: GitLab` → `gitlab`
   - Anything else (Jira, Linear, freeform "Other") → **decline and stamp nothing**: "The SDLC harness supports local, GitHub, and GitLab boards only. Your tracker is '<X>'. To use it anyway, write the two harness-extension sections by hand, modeled on this skill's `templates/conventions/`."
2. Copy the four core agents (`sdlc-planner.md`, `sdlc-implementer.md`, `sdlc-reviewer.md`, `sdlc-advisor.md`) from `templates/agents/` → `.claude/agents/` (create dir if needed, overwrite existing sdlc-* files). The `*-codex.md` variants are copied only in step 4.
3. Copy every skill directory under `templates/skills/` → `.claude/skills/<name>/` (currently `clear-board` and `sdlc-code-review`; overwrite, but leave any existing `clear-board/config.json` alone — step 4 owns it).
4. **Optional Codex backend**: ask whether the implement and/or review stages should run on an OpenAI model via the Codex CLI instead of Claude (planner, advisor, and orchestrator always stay Claude).
   - If yes: verify `codex --version` works — if not, say so and skip this step. Copy `templates/agents/sdlc-implementer-codex.md` and/or `sdlc-reviewer-codex.md` → `.claude/agents/` for the chosen stages, ask which model to pass as `-m` (blank = the Codex CLI's configured default), and write `.claude/skills/clear-board/config.json`, e.g. `{"implementer": "sdlc-implementer-codex", "reviewer": "sdlc-reviewer-codex", "codexModel": "gpt-5.1-codex"}` — include only the stage keys being rerouted, and omit `codexModel` if blank.
   - If no but an existing `config.json` reroutes stages: offer to delete it (reverting those stages to the Claude agents).
5. Append `templates/conventions/<backend>/issue-tracker-extension.md` to `docs/agents/issue-tracker.md` — idempotent: skip if the file already contains the heading `## SDLC harness extensions` with identical content; if the section exists but differs from the template (including after a backend switch), replace that whole section with the template version.
6. Append `templates/conventions/<backend>/triage-labels-extension.md` to `docs/agents/triage-labels.md` — same idempotency rule, marker heading `## SDLC harness statuses`.
7. **Remote backends only** (`github`/`gitlab`): offer to create the two harness labels now — `in-progress` (`gh label create in-progress --color FBCA04 --description "Claimed by the SDLC harness"` / `glab label create --name in-progress --color "#FBCA04" --description "Claimed by the SDLC harness"`) and the optional `sdlc:deep-review` review-tier marker (exact commands in the stamped `triage-labels-extension`). The `ready-for-*` labels already exist from the triage setup.
8. Report what was stamped, for which backend, and which stage backends are in effect, and suggest committing the changes.
