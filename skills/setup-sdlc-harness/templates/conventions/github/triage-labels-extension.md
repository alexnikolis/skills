## SDLC harness statuses

Additional statuses used by `/clear-board`, represented as GitHub labels and issue state:

| Status            | Representation                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| `in-progress`     | label `in-progress` (create once: `gh label create in-progress --color FBCA04 --description "Claimed by the SDLC harness"`); the harness-state block in the issue body says where |
| `done`            | issue closed; the `### Landed` comment has the PR URL                                              |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `### Failed` comment                             |

A ticket is dispatchable when it carries the `ready-for-agent` label (repo mapping above) AND has zero open blockers (native issue dependencies, or every issue in a `Blocked by: #a, #b` body line closed).
