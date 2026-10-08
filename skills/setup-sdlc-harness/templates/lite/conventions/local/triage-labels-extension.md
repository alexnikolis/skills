## SDLC harness statuses

Additional `Status:` values used by `/clear-board`:

| Status            | Meaning                                                            |
| ----------------- | ------------------------------------------------------------------ |
| `in-progress`     | Claimed by an agent group; `Worktree:`/`Branch:` lines say where   |
| `done`            | Landed on main; `### Landed` in the work log has the artifact      |
| `ready-for-human` | (existing label, reused) caps exhausted — see the `## Failed` section |
| `needs-info`      | (existing label, reused) parked on a product question — see `### Parked` in the work log |

A ticket is dispatchable when `Status: ready-for-agent` and every `## Blocked by` entry is `done` (a `- None ...` sentinel entry means no dependencies).

**`ready-for-agent` means no product questions are open.** A ticket that needs a product decision first — it offers options, says "needs a design call", or would remove or replace something a user can do — stays `needs-triage` until the decision is written into its `## Decisions` section. A ticket the harness parks on a `product:` question moves to `needs-info`; the human adds the decision to `## Decisions`, then sets `Status: ready-for-agent`.

### Ticket markers

Optional header lines, sitting alongside `Status:` near the top of the issue file. Triage owns them and the harness only reads them — unlike the `Attempts:` / `Fix rounds:` counter lines, which the orchestrator owns. `/clear-board` re-derives them from the file at every dispatch, so a resumed run and a `--plan` dry-run report what the original run used. Any other value, or no line at all, means the default.

| Line | Effect |
| --- | --- |
| `Verify: browser` | Adds the browser verification stage (`sdlc-verifier`) after review. For a change a user would notice on screen that the test suite cannot see: layout, focus, static-asset routing. Without it, a ticket goes from review straight to landing. |
| `Review tier: deep` | Runs the review's standards pass at the `high` tier (verifier subagents) instead of the default `medium` (findings verified inline). For a ticket touching one of the project's named risks. |
| `Model: <alias>` | Runs every stage of this ticket on that model — `<alias>` is an Agent tool model alias (`opus`, `sonnet`, `haiku`, `fable`). Without it, each stage agent uses its own frontmatter model. |
