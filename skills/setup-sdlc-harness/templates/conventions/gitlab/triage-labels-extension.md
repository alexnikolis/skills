## SDLC harness statuses

Additional statuses used by `/clear-board`, represented as GitLab labels and issue state:

| Status            | Representation                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| `in-progress`     | label `in-progress` (create once: `glab label create --name in-progress --color "#FBCA04" --description "Claimed by the SDLC harness"`); the harness-state block in the issue description says where |
| `done`            | issue closed; the `### Landed` note has the MR URL                                                 |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `### Failed` note                                |

A ticket is dispatchable when it carries the `ready-for-agent` label (project mapping above) AND has zero open blockers (native blocking links where available, or every issue in a `Blocked by: #a, #b` description line closed).
