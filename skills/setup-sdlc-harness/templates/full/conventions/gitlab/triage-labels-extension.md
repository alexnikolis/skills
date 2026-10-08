## SDLC harness statuses

Additional statuses used by `/clear-board`, represented as GitLab labels and issue state:

| Status            | Representation                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| `in-progress`     | label `in-progress` (create once: `glab label create --name in-progress --color "#FBCA04" --description "Claimed by the SDLC harness"`); the harness-state block in the issue description says where |
| `done`            | issue closed; the `### Landed` note has the MR URL                                                 |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `### Failed` note                                |

A ticket is dispatchable when it carries the `ready-for-agent` label (project mapping above) AND has zero open blockers (native blocking links where available, or every issue in a `Blocked by: #a, #b` description line closed).

### Review tier marker

`sdlc:deep-review` is an optional label, set at triage, that runs the review stage's standards pass at the `high` tier instead of the default `medium`. Create it once:

`glab label create --name "sdlc:deep-review" --color "#5319E7" --description "Review this ticket at the high sdlc-code-review tier"`

Single colon, so it is a plain label rather than a GitLab scoped (`key::value`) one — no Premium tier needed. Read it with the scan (`-F json` includes `labels`). The harness only reads it — triage owns whether a ticket carries it. Because it is board state rather than orchestrator judgement, `/clear-board` re-derives the tier from the label every time it dispatches review, so a resumed run and a `--plan` dry-run report the same tier the original run used.
