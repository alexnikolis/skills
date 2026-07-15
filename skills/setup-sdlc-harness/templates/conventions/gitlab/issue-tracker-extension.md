## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs. Defines the concrete board operations for the **GitLab Issues** tracker. All operations use the `glab` CLI; heredocs for multi-line text. GitLab calls comments "notes", and numbers issues (`#n`) and merge requests (`!n`) separately — always say which.

### Ticket identity and scope

- A ticket is an open GitLab issue; its id is the issue number `<n>`.
- The `/clear-board` scope argument is an optional `--label` or `--milestone` filter passed to the scan; default is the whole project.
- Ticket branch: `ticket/<n>-<slug>` (slug derived from the issue title).

### Durability

Tracker writes are already durable — there is no board to commit to main and no stale-copy problem. Ticket branches must never contain board or ticket state (there is none to commit).

### Scan

`glab issue list --label "<ready-for-agent label>" -F json` (label string from `docs/agents/triage-labels.md`), then drop any issue with an open blocker (see Dependencies). On start, also `glab issue list --label in-progress -F json` — those are resume candidates: read the harness-state block for caps and the issue notes for the last completed stage.

### Claim and counters — harness-state block in the issue description

Claiming = swap labels and append the state block to the issue description:

- `glab issue update <n> --label in-progress --unlabel "<ready-for-agent>"`
- Append to the description (preserving all existing content):

```
<!-- sdlc-harness-state -->
Attempts: 1
Escalations: 0
Fix rounds: 0
Worktree: <path>
Branch: ticket/<n>-<slug>
<!-- /sdlc-harness-state -->
```

The orchestrator is the **sole editor** of the description; stage agents only post notes. To update a counter: `glab issue view <n> -F json` (take `.description`), replace only the text between the markers, write back with `glab issue update <n> --description "$(cat <tempfile>)"`. Never rewrite anything outside the markers (the spec and any `Blocked by:` line live there). Counters are updated **before** dispatching the stage they count.

Caps (enforced by `/clear-board`): `Attempts:` hard cap 2; `Escalations:` hard cap 2 per attempt (reset on new attempt); `Fix rounds:` hard cap 2 per attempt (reset on new attempt; landing rebase rounds do not count).

### Dependencies

GitLab **native blocking links** are canonical where available — written with the `/blocked_by #<blocker>` quick action posted as a note, read via `glab api projects/:id/issues/<n>/links`: blocked iff any link has `link_type == "is_blocked_by"` and that issue's `state == "opened"`. **Blocking links are a Premium/Ultimate feature** — the guaranteed path on any tier is a `Blocked by: #a, #b` line at the top of the description: unblocked when every listed issue is closed (`glab issue view <a> -F json`, check `.state`). A blocker closed as won't-fix still counts as done. The harness only reads edges; whoever populates the board writes them.

### Work-log entries

Each stage entry is an **issue note** whose first line is the stage heading — post with `glab issue note <n> --message "$(cat <<'EOF' ... EOF)"`:
`### Plan (attempt N)`, `### Implementation (attempt N)` — or `### Implementation (attempt N, fix round K)` for a fix round — `### Review (attempt N, round K)` (first review = round 1), `### Escalation N`, `### Landed` (the landing artifact).

To resume, `glab issue view <n> --comments` and find the latest stage heading; no stage notes yet means planning never finished.

### Landing procedure (MR flow)

Recovery happens **before** the merge — a merged MR cannot be cheaply undone:

1. In the worktree: `git fetch origin && git rebase origin/main`, then run the full test suite locally on the rebased branch.
2. Rebase conflict or suite failure → the orchestrator's rebase round, then retry step 1.
3. Clean: `git push -u origin ticket/<n>-<slug>` (`--force-with-lease` after a rebase), then `glab mr create --source-branch ticket/<n>-<slug> --title "..." --description "Closes #<n> ..."` (capture the MR `!<m>` / URL), then merge: if the project runs CI pipelines, `glab mr merge <m> --when-pipeline-succeeds`; otherwise `glab mr merge <m>`. Never delete the source branch — failed tickets keep their branches, and cleanup is the human's call.
4. A failed pipeline is the MR-flow equivalent of a post-merge test failure: do not merge; go to the rebase round with the failing job output as findings.

The landing artifact is the **MR URL**. Caveat: a project whose merge rules require human approval will hard-block the harness at merge — surface that as a failure, don't wait indefinitely.

### Mark done

The merged MR's `Closes #<n>` normally closes the issue; if it didn't, post the note first, then `glab issue close <n>` (close takes no comment). Then `glab issue update <n> --unlabel in-progress` and post the `### Landed` note with the MR URL. Done = issue closed **and** `### Landed` note present (a closed issue without one is a mid-crash artifact — finish the bookkeeping on resume).

### Mark failed

Post a note starting `### Failed` (what failed, what was tried, pointer to the preserved worktree/branch), then `glab issue update <n> --unlabel in-progress --label "<ready-for-human>"`. The issue stays open.

### Run report

No `.scratch/` exists; write an untracked local file `sdlc-run-report-<UTC timestamp>.md` at the repo root and report the same summary to the user. (Swappable alternative: a note on a tracking issue, if the project keeps one.)
