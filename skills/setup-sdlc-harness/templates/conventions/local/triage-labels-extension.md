## SDLC harness statuses

Additional `Status:` values used by `/clear-board`:

| Status            | Meaning                                                            |
| ----------------- | ------------------------------------------------------------------ |
| `in-progress`     | Claimed by an agent group; `Worktree:`/`Branch:` lines say where   |
| `done`            | Landed on main; `### Landed` in the work log has the artifact      |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `## Failed` section |

A ticket is dispatchable when `Status: ready-for-agent` and every `## Blocked by` entry is `done` (a `- None ...` sentinel entry means no dependencies).

### Review tier marker

An optional `Review tier: deep` header line, sitting alongside `Status:` near the top of the issue file, runs the review stage's standards pass at the `high` tier instead of the default `medium`. Any other value, or no line at all, means the default.

Triage owns this line; the harness only reads it — unlike the `Attempts:` / `Escalations:` / `Fix rounds:` counter lines, which the orchestrator owns. Because it is board state rather than orchestrator judgement, `/clear-board` re-derives the tier from the file every time it dispatches review, so a resumed run and a `--plan` dry-run report the same tier the original run used.
