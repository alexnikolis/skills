## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs. Defines the concrete board operations for the **GitLab Issues** tracker. All operations use the `glab` CLI; heredocs for multi-line text. GitLab calls comments "notes", and numbers issues (`#n`) and merge requests (`!n`) separately — always say which.

### Ticket identity and scope

- A ticket is an open GitLab issue; its id is the issue number `<n>`.
- The `/clear-board` scope argument is an optional `--label` or `--milestone` filter passed to the scan; default is the whole project.
- Ticket branch: `ticket/<n>-<slug>` (slug derived from the issue title).
- Ticket shape: besides the spec, a ticket carries a `## Decisions` section in the issue description — the product decisions triage already made (what a user sees, what is removed or replaced, layout and copy calls). The planner raises a `product:` question only for something that section does not settle. A decision made later is appended there by the orchestrator, or by a maintainer answering a parked ticket.

### Durability

Tracker writes are already durable — there is no board to commit to main and no stale-copy problem. Ticket branches must never contain board or ticket state (there is none to commit).

### Scan

`glab issue list --label "<ready-for-agent label>" -F json` (label string from `docs/agents/triage-labels.md`), then drop any issue with an open blocker (see Dependencies). `labels` also carries the ticket markers. On start, also `glab issue list --label in-progress -F json` — those are resume candidates: read the harness-state block for caps and the issue notes for the last completed stage.

### Claim and counters — harness-state block in the issue description

Claiming = create the worktree from `origin/main` after a `git fetch origin` (never local `main`, which may be behind), append the state block to the issue description, then swap labels — in that order, each step first checking whether it already happened, so **a claim that died halfway is finished by claiming again** rather than repaired by hand:

- Append to the description (preserving all existing content), unless the markers are already there:

```
<!-- sdlc-harness-state -->
Attempts: 1
Fix rounds: 0
Worktree: <path>
Branch: ticket/<n>-<slug>
<!-- /sdlc-harness-state -->
```

- `glab issue update <n> --label in-progress --unlabel "<ready-for-agent>"`

The orchestrator is the **sole editor** of the description; stage agents only post notes. To update a counter: `glab issue view <n> -F json` (take `.description`), replace only the text between the markers, write back with `glab issue update <n> --description "$(cat <tempfile>)"`. Never rewrite anything outside the markers (the spec, `## Decisions` and any `Blocked by:` line live there) except to append a decision to `## Decisions`. Counters are updated **before** dispatching the stage they count.

Caps (enforced by `/clear-board`): `Attempts:` hard cap 2; `Fix rounds:` hard cap 1 per attempt (reset on new attempt; landing rebase rounds do not count).

### Dependencies

GitLab **native blocking links** are canonical where available — written with the `/blocked_by #<blocker>` quick action posted as a note, read via `glab api projects/:id/issues/<n>/links`: blocked iff any link has `link_type == "is_blocked_by"` and that issue's `state == "opened"`. **Blocking links are a Premium/Ultimate feature** — the guaranteed path on any tier is a `Blocked by: #a, #b` line at the top of the description: unblocked when every listed issue is closed (`glab issue view <a> -F json`, check `.state`). A blocker closed as won't-fix still counts as done. The harness only reads edges; whoever populates the board writes them.

### Work-log entries

Each stage entry is an **issue note** whose first line is the stage heading — post with `glab issue note <n> --message "$(cat <<'EOF' ... EOF)"`:
`### Plan (attempt N)`, `### Implementation (attempt N)` — or `### Implementation (attempt N, fix round K)` for a fix round — `### Review (attempt N, round K)` (first review = round 1), `### Verification (attempt N, round K)`, `### Landed` (the landing artifact).

To resume, `glab issue view <n> --comments` and find the latest stage heading; no stage notes yet means planning never finished.

**Confirm an entry exists** before acting on a stage's result — an agent can report posting one that is not there: re-read the notes and find the stage heading.

### Review surface

None defined. The MR is created at landing, so there is no review surface while review runs: findings go in full inside the reviewer's `### Review (attempt N, round K)` work-log note, and the orchestrator carries them to the fix round as the work order. (GitLab MR discussions with a `position` object are the direct analogue of GitHub's resolvable review threads — this backend simply has not been wired for them yet.)

### Landing procedure (MR flow)

Recovery happens **before** the merge — a merged MR cannot be cheaply undone:

1. In the worktree: `git fetch origin && git rebase origin/main`, then run the full test suite locally on the rebased branch.
2. Rebase conflict or suite failure → the orchestrator's rebase round, then retry step 1.
3. Clean: `git push -u origin ticket/<n>-<slug>` (`--force-with-lease` after a rebase), then `glab mr create --source-branch ticket/<n>-<slug> --title "..." --description "Closes #<n> ..."` (capture the MR `!<m>` / URL), then merge: if the project runs CI pipelines, first confirm a pipeline has actually **started** for the pushed sha (`glab ci status --branch ticket/<n>-<slug>`; poll for up to 10 minutes) — merging before one exists merges unchecked — then `glab mr merge <m> --when-pipeline-succeeds`; otherwise `glab mr merge <m>`. Landing is the only thing that waits on CI; stage agents neither wait on it nor report it. Never delete the source branch — failed tickets keep their branches, and cleanup is the human's call.
4. A failed pipeline is the MR-flow equivalent of a post-merge test failure: do not merge; go to the rebase round with the failing job output as findings.

The landing artifact is the **MR URL**. Caveat: a project whose merge rules require human approval will hard-block the harness at merge — surface that as a failure, don't wait indefinitely.

### Mark done

The merged MR's `Closes #<n>` normally closes the issue; if it didn't, post the note first, then `glab issue close <n>` (close takes no comment). Then `glab issue update <n> --unlabel in-progress` and post the `### Landed` note with the MR URL. Done = issue closed **and** `### Landed` note present (a closed issue without one is a mid-crash artifact — finish the bookkeeping on resume).

### Mark failed

Post a note starting `### Failed` (what failed, what was tried, pointer to the preserved worktree/branch), then `glab issue update <n> --unlabel in-progress --label "<ready-for-human>"`. The issue stays open.

### Park (unanswered product question)

Used when the planner raises a `product:` question and no human is present. Post the question as a note starting `### Parked`, then `glab issue update <n> --unlabel in-progress --label "<needs-info>"`, and leave the worktree, branch and state block in place. No attempt is consumed. A maintainer answers by adding the decision to `## Decisions` and relabelling the issue `<ready-for-agent>`; the next run claims it again and plans from the start.

When a human answers in the session instead, the orchestrator appends the answer to `## Decisions` in the description before relaying it.

### Run report

No file. The board already holds the durable record: plans, reviews and findings in each issue's work log, and the landing artifact in `### Landed`. A report file would only duplicate it and go stale.

- File each follow-up the run surfaced as an issue labelled `<needs-triage>`, before reporting.
- Report the summary to the user in the session.
