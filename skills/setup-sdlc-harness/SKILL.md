---
name: setup-sdlc-harness
description: "Stamp the autonomous SDLC harness (clear-board orchestrator, stage agents, board convention extensions) into a repo already set up with mattpocock/skills."
disable-model-invocation: true
---

# Setup SDLC harness

Installs the autonomous board-clearing harness into the current repo. Prerequisite: the repo was set up with `setup-matt-pocock-skills` (has `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, and a `.scratch/<feature>/issues/` board).

## Canonical-copy rule

The templates in this skill's `templates/` directory are the canonical versions. When iterating on agent prompts or the clear-board protocol, edit the templates here and re-run this skill to re-stamp — never edit the stamped copies in a repo directly.

## Steps

1. Copy `templates/agents/*.md` → `.claude/agents/` (create dir if needed, overwrite existing sdlc-* files).
2. Copy `templates/skills/clear-board/` → `.claude/skills/clear-board/` (overwrite).
3. Append `templates/conventions/issue-tracker-extension.md` to `docs/agents/issue-tracker.md` — idempotent: skip if the file already contains the heading `## SDLC harness extensions`; if present but differing from the template, replace that section with the template version.
4. Append `templates/conventions/triage-labels-extension.md` to `docs/agents/triage-labels.md` — same idempotency rule, marker heading `## SDLC harness statuses`.
5. Report what was stamped, and suggest committing the changes.
