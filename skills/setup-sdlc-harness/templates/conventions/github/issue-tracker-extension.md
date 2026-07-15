## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs. Defines the concrete board operations for the **GitHub Issues** tracker. All operations use the `gh` CLI; heredocs for multi-line bodies.

### Ticket identity and scope

- A ticket is an open GitHub issue; its id is the issue number `<n>`.
- The `/clear-board` scope argument is an optional `--label` or `--milestone` filter passed to the scan; default is the whole repo.
- Ticket branch: `ticket/<n>-<slug>` (slug derived from the issue title).

### Durability

Tracker writes are already durable — there is no board to commit to main and no stale-copy problem. Ticket branches must never contain board or ticket state (there is none to commit).

### Scan

`gh issue list --state open --label "<ready-for-agent label>" --json number,title` (label string from `docs/agents/triage-labels.md`), then drop any issue with an open blocker (see Dependencies). On start, also `gh issue list --state open --label in-progress --json number,title` — those are resume candidates: read the harness-state block for caps and the issue comments for the last completed stage.

### Claim and counters — harness-state block in the issue body

Claiming = swap labels and append the state block to the issue body:

- `gh issue edit <n> --remove-label "<ready-for-agent>" --add-label in-progress`
- Append to the issue body (preserving all existing content):

```
<!-- sdlc-harness-state -->
Attempts: 1
Escalations: 0
Fix rounds: 0
Worktree: <path>
Branch: ticket/<n>-<slug>
<!-- /sdlc-harness-state -->
```

The orchestrator is the **sole editor** of the issue body; stage agents only comment. To update a counter: `gh issue view <n> --json body -q .body`, replace only the text between the markers, write back with `gh issue edit <n> --body-file <tempfile>`. Never rewrite anything outside the markers (the spec and any `Blocked by:` line live there). Counters are updated **before** dispatching the stage they count.

Caps (enforced by `/clear-board`): `Attempts:` hard cap 2; `Escalations:` hard cap 2 per attempt (reset on new attempt); `Fix rounds:` hard cap 2 per attempt (reset on new attempt; landing rebase rounds do not count).

### Dependencies

GitHub **native issue dependencies** are canonical. Read the live gate with `gh api repos/{owner}/{repo}/issues/<n> --jq '.issue_dependencies_summary.blocked_by'` — it counts **open** blockers only; `0` means unblocked. Where dependencies aren't enabled, fall back to a `Blocked by: #a, #b` line at the top of the issue body: unblocked when every listed issue is closed (`gh issue view <a> --json state`). A blocker closed as not-planned still counts as done. The harness only reads edges; whoever populates the board writes them (`gh api --method POST repos/{owner}/{repo}/issues/<child>/dependencies/blocked_by -F issue_id=<blocker database id>` — database id via `--jq .id`, not the `#number`).

### Work-log entries

Each stage entry is an **issue comment** whose first line is the stage heading — post with `gh issue comment <n> --body "$(cat <<'EOF' ... EOF)"`:
`### Plan (attempt N)`, `### Implementation (attempt N)` — or `### Implementation (attempt N, fix round K)` for a fix round — `### Review (attempt N, round K)` (first review = round 1), `### Escalation N`, `### Landed` (the landing artifact).

To resume, `gh issue view <n> --comments` and find the latest stage heading; no stage comments yet means planning never finished.

### Landing procedure (PR flow)

Recovery happens **before** the merge — a merged PR cannot be cheaply undone:

1. In the worktree: `git fetch origin && git rebase origin/main`, then run the full test suite locally on the rebased branch.
2. Rebase conflict or suite failure → the orchestrator's rebase round, then retry step 1.
3. Clean: `git push -u origin ticket/<n>-<slug>` (`--force-with-lease` after a rebase), then `gh pr create --head ticket/<n>-<slug> --title "..." --body "Closes #<n> ..."` (capture the URL), then merge: if the repo has required checks, `gh pr checks <url> --watch` first; then `gh pr merge <url> --merge` (or the repo's documented merge method). Never `--delete-branch` — failed tickets keep their branches, and cleanup is the human's call.
4. A failed required check is the PR-flow equivalent of a post-merge test failure: do not merge; go to the rebase round with the failing check output as findings.

The landing artifact is the **PR URL**. Caveat: a repo whose branch protection requires human PR approval will hard-block the harness at merge — surface that as a failure, don't wait indefinitely.

### Mark done

The merged PR's `Closes #<n>` normally closes the issue; if it didn't, `gh issue close <n>`. Then `gh issue edit <n> --remove-label in-progress` and post the `### Landed` comment with the PR URL. Done = issue closed **and** `### Landed` comment present (a closed issue without one is a mid-crash artifact — finish the bookkeeping on resume).

### Mark failed

Post a comment starting `### Failed` (what failed, what was tried, pointer to the preserved worktree/branch), then `gh issue edit <n> --remove-label in-progress --add-label "<ready-for-human>"`. The issue stays open.

### Run report

No `.scratch/` exists; write an untracked local file `sdlc-run-report-<UTC timestamp>.md` at the repo root and report the same summary to the user. (Swappable alternative: a comment on a tracking issue, if the repo keeps one.)
