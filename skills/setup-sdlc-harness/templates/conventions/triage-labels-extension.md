## SDLC harness statuses

Additional `Status:` values used by `/clear-board`:

| Status            | Meaning                                                            |
| ----------------- | ------------------------------------------------------------------ |
| `in-progress`     | Claimed by an agent group; `Worktree:`/`Branch:` lines say where   |
| `done`            | Landed on main; `### Landed` in the work log has the artifact      |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `## Failed` section |

A ticket is dispatchable when `Status: ready-for-agent` and every `## Blocked by` entry is `done` (a `- None ...` sentinel entry means no dependencies).
