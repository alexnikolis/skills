## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs.

All edits to a ticket file happen at its path in the **main checkout** — the copy of `.scratch/` inside a worktree is stale and must never be read, edited, or committed on a ticket branch. The orchestrator commits board changes to main after each claim and each landing.

### Extra header lines (near the top of an issue file)

- `Attempts: N` — whole-pipeline attempts consumed (hard cap 2)
- `Escalations: N` — escalations this attempt (hard cap 2; reset to 0 on each new attempt)
- `Fix rounds: N` — review fix rounds this attempt (hard cap 2; reset to 0 on each new attempt; landing rebase rounds do not count here)
- `Worktree: <path>` — the group's git worktree while in progress
- `Branch: <name>` — the ticket branch (`ticket/<NN>-<slug>`); preserved even on failure

### `## Blocked by`

Dependency list, one entry per line as `- NN Title` (resolved by the `NN` prefix to `issues/NN-*.md`). The sentinel `- None — can start immediately` means no dependencies. A ticket is dispatchable when every listed ticket is `done`.

### `## Work log`

Appended per stage by the stage agents, one subsection each:
`### Plan (attempt N)`, `### Implementation (attempt N)` — or `### Implementation (attempt N, fix round K)` for a fix round — `### Review (attempt N, round K)` (first review = round 1), `### Escalation N`, `### Landed` (merge commit hash or PR URL — the landing artifact).

### `## Failed`

Written by the orchestrator when a ticket exhausts its caps: what failed, what was tried, pointer to the preserved worktree/branch. Status moves to `ready-for-human`. (Named `Failed`, not `Blocked`, to avoid colliding with `## Blocked by`.)

### Landing

v1 lands via local `git merge --no-ff` to main; the merge commit hash in `### Landed` is the proof of work. Repos using a GitHub board may substitute a PR flow: push branch, open PR with `gh`, record the PR URL instead.
