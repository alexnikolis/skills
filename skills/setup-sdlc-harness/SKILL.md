---
name: setup-sdlc-harness
description: "Stamp the autonomous SDLC harness (clear-board orchestrator, stage agents, code-review skill, board convention extensions) into a repo already set up with mattpocock/skills. Installs the lite variant by default, or the full-rigor variant on request. Detects the repo's issue-tracker backend (local markdown, GitHub, or GitLab) and stamps matching conventions."
argument-hint: "[lite|full]"
disable-model-invocation: true
---

# Setup SDLC harness

Installs the autonomous board-clearing harness into the current repo. Prerequisite: the repo was set up with `setup-matt-pocock-skills` (has `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`), and its tracker is Local Markdown, GitHub, or GitLab.

## Variants

- **`lite`** (default) — for personal and prototype projects. Rigor comes from a `## Standards` section in `CLAUDE.md` that names the project's scale and its two or three real risks; everything else is built to the simplest thing that works. No advisor, a short plan, one fix round, review findings verified inline, browser verification only on labelled tickets.
- **`full`** — for projects that need high engineering rigor on every ticket: an advisor for escalations, full acceptance-criteria plans, test-first implementation, two fix rounds, subagent-verified review findings.

Templates live in `templates/<variant>/`, plus `templates/shared/` for the files both variants use.

## Canonical-copy rule

The templates in this skill's `templates/` directory are the canonical versions. When iterating on agent prompts or the clear-board protocol, edit the templates here and re-run this skill to re-stamp — never edit the stamped copies in a repo directly. The exceptions are the project-owned files this skill writes once and then leaves alone: `CLAUDE.md` § Standards, `scripts/sdlc/gates.sh`, and `scripts/sdlc/setup-worktree.sh`.

## Steps

1. **Detect the backend**: read the first heading of `docs/agents/issue-tracker.md`.
   - `# Issue tracker: Local Markdown` → `local`
   - `# Issue tracker: GitHub` → `github`
   - `# Issue tracker: GitLab` → `gitlab`
   - Anything else (Jira, Linear, freeform "Other") → **decline and stamp nothing**: "The SDLC harness supports local, GitHub, and GitLab boards only. Your tracker is '<X>'. To use it anyway, write the two harness-extension sections by hand, modeled on this skill's `templates/<variant>/conventions/`."
2. **Pick the variant**: the argument if one was given, otherwise `lite`. One exception — the repo already has the full variant stamped (`.claude/agents/sdlc-advisor.md` exists) and no argument was given: ask whether to keep `full` or switch to `lite`, rather than silently changing a working setup.
3. Copy every agent in `templates/<variant>/agents/` → `.claude/agents/` (create dir if needed, overwrite existing `sdlc-*` files). Then delete any stamped stage agent the chosen variant does not have: `sdlc-advisor.md` for `lite`, `sdlc-verifier.md` for `full`.
4. Copy `templates/<variant>/skills/clear-board/` and `templates/shared/skills/sdlc-code-review/` → `.claude/skills/<name>/` (overwrite, but leave any existing `clear-board/config.json` alone — step 5 owns it).
5. **Optional Codex backend**: ask whether the implement and/or review stages should run on an OpenAI model via the Codex CLI instead of Claude (the other stages and the orchestrator always stay Claude).
   - If yes: verify `codex --version` works — if not, say so and skip this step. Copy `templates/shared/agents/sdlc-implementer-codex.md` and/or `sdlc-reviewer-codex.md` → `.claude/agents/` for the chosen stages, ask which model to pass as `-m` (blank = the Codex CLI's configured default), and write `.claude/skills/clear-board/config.json`, e.g. `{"implementer": "sdlc-implementer-codex", "reviewer": "sdlc-reviewer-codex", "codexModel": "gpt-5.1-codex"}` — include only the stage keys being rerouted, and omit `codexModel` if blank.
   - If no but an existing `config.json` reroutes stages: offer to delete it (reverting those stages to the Claude agents).
6. Append `templates/<variant>/conventions/<backend>/issue-tracker-extension.md` to `docs/agents/issue-tracker.md` — idempotent: skip if the file already contains the heading `## SDLC harness extensions` with identical content; if the section exists but differs from the template (including after a backend or variant switch), replace that whole section with the template version.
7. Append `templates/<variant>/conventions/<backend>/triage-labels-extension.md` to `docs/agents/triage-labels.md` — same idempotency rule, marker heading `## SDLC harness statuses`.
8. **`lite` only — Standards.** The stage agents take their whole quality bar from `CLAUDE.md` § Standards, so the harness cannot run without it. If `CLAUDE.md` already has a `## Standards` heading, leave it alone. Otherwise ask the user two things — who uses the app and how many of them, and which two or three risks deserve full care (offer candidates drawn from the codebase: auth, stored user data, anything that spends money) — then fill in `templates/lite/standards.md` with the answers and add it as the first section of `CLAUDE.md` (create the file if needed). Keep the test-bar and over-building paragraphs as written unless the user changes them.
9. **`lite` on `github` only — scripts.** Copy `claim.sh`, `state.sh`, `land.sh` and `labels.sh` from `templates/lite/scripts/github/` → `scripts/sdlc/` (overwrite, keep them executable). Then the two project-owned files, written only if absent:
   - `scripts/sdlc/gates.sh` — start from the template and replace its placeholder with the project's full test command plus any typecheck and lint commands, taken from `CLAUDE.md`, the package manifest, or CI config. Ask if they cannot be determined. Run it once to confirm it passes on main.
   - `scripts/sdlc/setup-worktree.sh` (optional) — whatever a fresh worktree needs before tests can run, usually a dependency install. It receives the main checkout's path as `$1`. Skip it if a fresh checkout needs no setup.
   - If `docs/agents/triage-labels.md` maps a triage role to a different label string, tell the user to export the matching `SDLC_*_LABEL` variable named at the top of `claim.sh` and `labels.sh`.
10. **Labels** (`github`/`gitlab`): create every label the harness uses, so no run trips over a missing one.
    - `lite` on `github`: run `scripts/sdlc/labels.sh`.
    - `lite` on `gitlab`: run the label commands in the stamped `triage-labels-extension`.
    - `full`: offer to create `in-progress` (`gh label create in-progress --color FBCA04 --description "Claimed by the SDLC harness"` / `glab label create --name in-progress --color "#FBCA04" --description "Claimed by the SDLC harness"`) and the optional `sdlc:deep-review` review-tier marker (exact commands in the stamped `triage-labels-extension`). The `ready-for-*` labels already exist from the triage setup.
11. Report what was stamped, for which variant and backend, and which stage backends are in effect, and suggest committing the changes.
