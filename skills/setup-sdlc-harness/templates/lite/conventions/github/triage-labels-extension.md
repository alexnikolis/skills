## SDLC harness statuses

Additional statuses used by `/clear-board`, represented as GitHub labels and issue state:

| Status            | Representation                                                                                     |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| `in-progress`     | label `in-progress`; the harness-state block in the issue body says where |
| `done`            | issue closed; the `### Landed` comment has the PR URL                                              |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `### Failed` comment                             |
| `needs-info`      | (existing label, reused) parked on a product question — see the `### Parked` comment               |

A ticket is dispatchable when it carries the `ready-for-agent` label (repo mapping above) AND has zero open blockers (native issue dependencies, or every issue in a `Blocked by: #a, #b` body line closed).

**`ready-for-agent` means no product questions are open.** A ticket that needs a product decision first — it offers options, says "needs a design call", or would remove or replace something a user can do — stays `needs-triage` until the decision is written into its `## Decisions` section. A ticket the harness parks on a `product:` question moves to `needs-info`; a maintainer adds the decision to `## Decisions`, then relabels it `ready-for-agent`.

`scripts/sdlc/labels.sh` creates every label named in this file that the repo does not have yet, triage labels included. Rerun it whenever a label goes missing.

### Ticket markers

Optional labels, set at triage. The harness only reads them — triage owns whether a ticket carries one — and `/clear-board` re-derives them from the board at every dispatch, so a resumed run and a `--plan` dry-run report what the original run used. Read them with the scan (`--json number,title,labels`).

| Label | Effect |
| --- | --- |
| `sdlc:verify` | Adds the browser verification stage (`sdlc-verifier`) after review. For a change a user would notice on screen that the test suite cannot see: layout, focus, static-asset routing. Without it, a ticket goes from review straight to landing. |
| `sdlc:deep-review` | Runs the review's standards pass at the `high` tier (verifier subagents) instead of the default `medium` (findings verified inline). For a ticket touching one of the project's named risks. |
| `sdlc:model-<alias>` | Runs every stage of this ticket on that model — `<alias>` is an Agent tool model alias (`opus`, `sonnet`, `haiku`, `fable`). Without it, each stage agent uses its own frontmatter model. More than one on a ticket is a triage error: the harness parks the ticket rather than guessing. |
