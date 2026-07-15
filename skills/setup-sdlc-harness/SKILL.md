---
name: setup-sdlc-harness
description: "Stamp the autonomous SDLC harness (clear-board orchestrator, stage agents, board convention extensions) into a repo already set up with mattpocock/skills. Detects the repo's issue-tracker backend (local markdown, GitHub, or GitLab) and stamps matching conventions."
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
2. Copy `templates/agents/*.md` → `.claude/agents/` (create dir if needed, overwrite existing sdlc-* files).
3. Copy `templates/skills/clear-board/` → `.claude/skills/clear-board/` (overwrite).
4. Append `templates/conventions/<backend>/issue-tracker-extension.md` to `docs/agents/issue-tracker.md` — idempotent: skip if the file already contains the heading `## SDLC harness extensions` with identical content; if the section exists but differs from the template (including after a backend switch), replace that whole section with the template version.
5. Append `templates/conventions/<backend>/triage-labels-extension.md` to `docs/agents/triage-labels.md` — same idempotency rule, marker heading `## SDLC harness statuses`.
6. **Remote backends only** (`github`/`gitlab`): offer to create the `in-progress` label now (`gh label create in-progress --color FBCA04 --description "Claimed by the SDLC harness"` / `glab label create --name in-progress --color "#FBCA04" --description "Claimed by the SDLC harness"`). The `ready-for-*` labels already exist from the triage setup.
7. Report what was stamped and for which backend, and suggest committing the changes.
