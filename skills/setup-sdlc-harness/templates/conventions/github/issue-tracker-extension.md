## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs. Defines the concrete board operations for the **GitHub Issues** tracker. All operations use the `gh` CLI; heredocs for multi-line bodies.

### Ticket identity and scope

- A ticket is an open GitHub issue; its id is the issue number `<n>`.
- The `/clear-board` scope argument is an optional `--label` or `--milestone` filter passed to the scan; default is the whole repo.
- Ticket branch: `ticket/<n>-<slug>` (slug derived from the issue title).
- Ticket PR: a **draft** PR opened by the implementer at the end of stage 2, body `Closes #<n>`. Review findings (standards and spec) are comments on it; the fix round reads its unresolved threads; landing takes it out of draft. One PR per attempt — a new attempt gets a new PR (see Retry procedure).

### Retry procedure (new attempt)

Run by `/clear-board` when it increments `Attempts:`, after renaming the local branch to `ticket/<n>-<slug>-attempt<K>` and before dispatching Plan. Purpose: attempt K+1 must not inherit attempt K's PR or its review threads, and its first push must not collide with a stale remote ref.

1. Preserve the old work under its new name: `git push origin ticket/<n>-<slug>-attempt<K>` (skip if the old branch was never pushed).
2. Close the old PR if one is open: `gh pr close <url> --comment "Superseded by attempt <K+1>."` Never pass `--delete-branch`.
3. Retire the stale remote ref so the fresh branch pushes cleanly and gets its own PR: `git push origin --delete ticket/<n>-<slug>`. This deletes a remote ref — only safe because step 1 preserved those commits under the attempt-suffixed ref, so never run it before that push succeeds.

The superseded PR stays closed-but-readable, so its review history survives for the human.

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

### Review surface (draft PR)

Findings live on the ticket PR as **inline review threads**, which are individually resolvable — that resolution state is what carries the work order from review to fix round. The issue work log records the verdict and a PR link, not the findings themselves.

**Open or find it** (implementer, end of stage 2). Push first: `gh pr create` fails on a branch with no commits ahead of base.

```bash
git push -u origin ticket/<n>-<slug>          # --force-with-lease if history was rewritten
URL=$(gh pr list --head ticket/<n>-<slug> --state open --json url --jq '.[0].url')
[ -n "$URL" ] || URL=$(gh pr create --draft --head ticket/<n>-<slug> \
  --title "<title>" --body "Closes #<n>")
```

**Post findings** — one batched review, not a call per finding. Build the JSON with `jq`, never string-interpolation: finding bodies carry quotes, backticks and newlines that break a hand-written heredoc.

```bash
jq -n --arg body "<summary line>" --argjson comments "$(cat "$TMP/comments.json")" \
  '{event:"COMMENT", body:$body, comments:$comments}' > "$TMP/review.json"
gh api --method POST repos/{owner}/{repo}/pulls/<pr>/reviews --input "$TMP/review.json"
```

Each entry in `comments` is `{"path": "...", "line": 42, "side": "RIGHT", "body": "..."}`, where `line` is a line on the diff's **new** side. The API returns **422** when `line` is not part of the diff — retry that entry as a file-level comment (`{"path": "...", "subject_type": "file", "body": "..."}`), and if that also fails, fold it into the review `body` naming the location in prose. Never drop a finding because its anchor would not attach.

Spec findings use the same surface, each prefixed `spec:`.

**List open findings** — the fix round's work order:

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
      reviewThreads(first:100){ nodes{
        id isResolved isOutdated path line
        comments(first:10){ nodes{ databaseId body } }
      }}}}}' \
  -f owner=<owner> -f repo=<repo> -F pr=<pr> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)'
```

Thread ids come back as `PRRT_…`. `isOutdated` marks a thread whose anchor a force-push invalidated — still open, still the work order, just no longer pinned to a line.

**Close a finding** — reply with the fixing sha, then resolve. The reply needs the `databaseId` of the thread's first comment; the resolve needs the thread's `PRRT_` node id:

```bash
gh api --method POST repos/{owner}/{repo}/pulls/<pr>/comments/<databaseId>/replies -f body="Fixed in <sha>."
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }' -f id=<PRRT_…>
```

A finding deliberately not fixed stays **unresolved** with a reply giving the reason, so the reviewer judges it rather than re-filing it.

### Landing procedure (PR flow)

Recovery happens **before** the merge — a merged PR cannot be cheaply undone:

1. In the worktree: `git fetch origin && git rebase origin/main`, then run the full test suite locally on the rebased branch.
2. Rebase conflict or suite failure → the orchestrator's rebase round, then retry step 1.
3. Clean: `git push -u origin ticket/<n>-<slug>` (`--force-with-lease` after a rebase), then take the branch's existing draft PR out of draft — the implementer opened it in stage 2 and review commented on it: `gh pr ready <url>` (create it here only if it is somehow missing). Then merge: if the repo has required checks, `gh pr checks <url> --watch` first; then `gh pr merge <url> --merge` (or the repo's documented merge method). Never `--delete-branch` — failed tickets keep their branches, and cleanup is the human's call.
4. A failed required check is the PR-flow equivalent of a post-merge test failure: do not merge; go to the rebase round with the failing check output as findings.

The landing artifact is the **PR URL**. Caveat: a repo whose branch protection requires human PR approval will hard-block the harness at merge — surface that as a failure, don't wait indefinitely.

### Mark done

The merged PR's `Closes #<n>` normally closes the issue; if it didn't, `gh issue close <n>`. Then `gh issue edit <n> --remove-label in-progress` and post the `### Landed` comment with the PR URL. Done = issue closed **and** `### Landed` comment present (a closed issue without one is a mid-crash artifact — finish the bookkeeping on resume).

### Mark failed

Post a comment starting `### Failed` (what failed, what was tried, pointer to the preserved worktree/branch), then `gh issue edit <n> --remove-label in-progress --add-label "<ready-for-human>"`. The issue stays open.

### Run report

No `.scratch/` exists; write an untracked local file `sdlc-run-report-<UTC timestamp>.md` at the repo root and report the same summary to the user. (Swappable alternative: a comment on a tracking issue, if the repo keeps one.)
