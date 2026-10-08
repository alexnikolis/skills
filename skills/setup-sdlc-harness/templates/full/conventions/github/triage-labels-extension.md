## SDLC harness statuses

Additional statuses used by `/clear-board`, represented as GitHub labels and issue state:

| Status            | Representation                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| `in-progress`     | label `in-progress` (create once: `gh label create in-progress --color FBCA04 --description "Claimed by the SDLC harness"`); the harness-state block in the issue body says where |
| `done`            | issue closed; the `### Landed` comment has the PR URL                                              |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `### Failed` comment                             |

A ticket is dispatchable when it carries the `ready-for-agent` label (repo mapping above) AND has zero open blockers (native issue dependencies, or every issue in a `Blocked by: #a, #b` body line closed).

### Review tier marker

`sdlc:deep-review` is an optional label, set at triage, that runs the review stage's standards pass at the `high` tier instead of the default `medium`. Create it once:

`gh label create "sdlc:deep-review" --color 5319E7 --description "Review this ticket at the high sdlc-code-review tier"`

Read it with the scan (`--json number,title,labels`). The harness only reads it — triage owns whether a ticket carries it. Because it is board state rather than orchestrator judgement, `/clear-board` re-derives the tier from the label every time it dispatches review, so a resumed run and a `--plan` dry-run report the same tier the original run used.
