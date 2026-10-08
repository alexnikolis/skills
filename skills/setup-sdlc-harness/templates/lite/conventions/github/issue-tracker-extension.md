## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs. Defines the concrete board operations for the **GitHub Issues** tracker. All operations use the `gh` CLI; heredocs for multi-line bodies.

### Ticket identity and scope

- A ticket is an open GitHub issue; its id is the issue number `<n>`.
- The `/clear-board` scope argument is an optional `--label` or `--milestone` filter passed to the scan; default is the whole repo.
- Ticket branch: `ticket/<n>-<slug>` (slug derived from the issue title).
- Ticket shape: besides the spec, a ticket carries a `## Decisions` section in the issue body — the product decisions triage already made (what a user sees, what is removed or replaced, layout and copy calls). The planner raises a `product:` question only for something that section does not settle. A decision made later is appended there by the orchestrator, or by a maintainer answering a parked ticket.
- Ticket PR: a **draft** PR opened by the implementer at the end of stage 2, body `Closes #<n>`. Review findings (standards and spec) are comments on it; the fix round reads its open findings; landing takes it out of draft. One PR per attempt — a new attempt gets a new PR (see Retry procedure).

### Retry procedure (new attempt)

Run by `/clear-board` when it increments `Attempts:`, after renaming the local branch to `ticket/<n>-<slug>-attempt<K>` and before dispatching Plan. Purpose: attempt K+1 must not inherit attempt K's PR or its review threads, and its first push must not collide with a stale remote ref.

1. Preserve the old work under its new name: `git push origin ticket/<n>-<slug>-attempt<K>` (skip if the old branch was never pushed).
2. Close the old PR if one is open: `gh pr close <url> --comment "Superseded by attempt <K+1>."` Never pass `--delete-branch`.
3. Retire the stale remote ref so the fresh branch pushes cleanly and gets its own PR: `git push origin --delete ticket/<n>-<slug>`. This deletes a remote ref — only safe because step 1 preserved those commits under the attempt-suffixed ref, so never run it before that push succeeds.

The superseded PR stays closed-but-readable, so its review history survives for the human.

### Durability

Tracker writes are already durable — there is no board to commit to main and no stale-copy problem. Ticket branches must never contain board or ticket state (there is none to commit).

### Scan

`gh issue list --state open --label "<ready-for-agent label>" --json number,title,labels` (label string from `docs/agents/triage-labels.md`), then drop any issue with an open blocker (see Dependencies). `labels` also carries the ticket markers. On start, also `gh issue list --state open --label in-progress --json number,title,labels` — those are resume candidates: read the harness-state block for caps and the issue comments for the last completed stage.

### Claim and counters — harness-state block in the issue body

Run `scripts/sdlc/claim.sh <n> <slug>`. It fetches, creates the worktree from `origin/main` (never local `main`, which may be behind), appends the state block to the issue body, swaps `<ready-for-agent>` for `in-progress`, runs `scripts/sdlc/setup-worktree.sh` if the project has one (dependency install and the like), and prints the worktree path and branch. Every step checks whether it already happened, so **a claim that died halfway is finished by running the same command again** — never repair a half-claimed ticket by hand.

```
<!-- sdlc-harness-state -->
Attempts: 1
Fix rounds: 0
Worktree: <path>
Branch: ticket/<n>-<slug>
<!-- /sdlc-harness-state -->
```

The orchestrator is the **sole editor** of the issue body; stage agents only comment. Read and update fields with `scripts/sdlc/state.sh <n> get|set|incr <Field> [value]` (e.g. `state.sh 37 incr "Fix rounds"`). It rewrites only the matching line between the markers, so the spec, `## Decisions` and any `Blocked by:` line are untouched. Never hand-edit the block. Counters are updated **before** dispatching the stage they count.

A later attempt keeps the block: after the retry procedure, `state.sh <n> incr Attempts`, `state.sh <n> set "Fix rounds" 0`, then `claim.sh <n> <slug> <new worktree path>` — the previous attempt's worktree stays where it is.

Caps (enforced by `/clear-board`): `Attempts:` hard cap 2; `Fix rounds:` hard cap 1 per attempt (reset on new attempt; landing rebase rounds do not count).

### Dependencies

GitHub **native issue dependencies** are canonical. Read the live gate with `gh api repos/{owner}/{repo}/issues/<n> --jq '.issue_dependencies_summary.blocked_by'` — it counts **open** blockers only; `0` means unblocked. Where dependencies aren't enabled, fall back to a `Blocked by: #a, #b` line at the top of the issue body: unblocked when every listed issue is closed (`gh issue view <a> --json state`). A blocker closed as not-planned still counts as done. The harness only reads edges; whoever populates the board writes them (`gh api --method POST repos/{owner}/{repo}/issues/<child>/dependencies/blocked_by -F issue_id=<blocker database id>` — database id via `--jq .id`, not the `#number`).

### Work-log entries

Each stage entry is an **issue comment** whose first line is the stage heading — post with `gh issue comment <n> --body "$(cat <<'EOF' ... EOF)"`:
`### Plan (attempt N)`, `### Implementation (attempt N)` — or `### Implementation (attempt N, fix round K)` for a fix round — `### Review (attempt N, round K)` (first review = round 1), `### Verification (attempt N, round K)`, `### Landed` (the landing artifact).

To resume, `gh issue view <n> --comments` and find the latest stage heading; no stage comments yet means planning never finished.

**Confirm an entry exists** before acting on a stage's result — an agent can report posting one that is not there: `gh issue view <n> --json comments --jq '[.comments[].body | select(startswith("<stage heading>"))] | length'` must be at least 1.

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

Each entry in `comments` is `{"path": "...", "line": 42, "side": "RIGHT", "body": "..."}`, where `line` is a line on the diff's **new** side. The API returns **422 `Line could not be resolved`** when `line` is not part of the diff.

Fall back to a **file-level comment**, which needs a different endpoint — `subject_type` is not a field on this endpoint's comment type, so adding it here fails with `Field is not defined on DraftPullRequestReviewComment`. Post the unanchorable entry on its own, and note that `commit_id` is required:

```bash
gh api --method POST repos/{owner}/{repo}/pulls/<pr>/comments \
  -f path=<path> -f subject_type=file -f commit_id="$(git rev-parse HEAD)" -f body=<body>
```

That still creates a resolvable review thread, so it stays part of the work order like any other finding. A finding about a file the diff does not touch cannot be attached at all — GitHub has nowhere to put it — so post it as a **PR comment** whose first line is `finding:` followed by the location in prose (`gh pr comment <pr> --body ...`). Never drop a finding because its anchor would not attach.

Spec findings use the same surface, each prefixed `spec:`.

**List open findings** — the fix round's work order. It has two parts, and the fix round reads both. Unresolved review threads:

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

Thread ids come back as `PRRT_…`. `isOutdated` marks a thread whose anchor a force-push invalidated — still open, still the work order, just no longer pinned to a line. A force-push does not invalidate anchors by itself: where the anchored content merely moved, GitHub re-anchors it and `line` shifts while `originalLine` keeps the position it was filed against.

And the findings that could not be attached to a line, which live as PR comments and have no resolved state — one is open until a later PR comment answers it by quoting its first line:

```bash
gh pr view <pr> --json comments --jq '.comments[] | select(.body | startswith("finding:")) | {url, body}'
```

Do not read the threads query immediately after a push — it can serve pre-push line numbers for a few seconds while REST already reports the new ones. Read it before pushing, or re-read to confirm.

**Close a finding** — reply with the fixing sha, then resolve. The reply needs the `databaseId` of the thread's first comment; the resolve needs the thread's `PRRT_` node id:

```bash
gh api --method POST repos/{owner}/{repo}/pulls/<pr>/comments/<databaseId>/replies -f body="Fixed in <sha>."
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }' -f id=<PRRT_…>
```

A `finding:` PR comment has no thread to resolve: close it with a PR comment that quotes its first line and gives the fixing sha.

A finding deliberately not fixed stays **unresolved** with a reply giving the reason, so the reviewer judges it rather than re-filing it.

### Landing procedure (PR flow)

Recovery happens **before** the merge — a merged PR cannot be cheaply undone. Run `scripts/sdlc/land.sh <pr> <worktree>`. It runs the whole procedure and exits non-zero rather than merging when any step fails:

1. `git fetch origin && git rebase origin/main`. On conflict it aborts the rebase and exits 2.
2. Runs `scripts/sdlc/gates.sh` — the project's full test suite and other local gates — on the rebased branch. Any failure exits 3.
3. Pushes with `--force-with-lease` and takes the draft PR out of draft.
4. Where a workflow runs on pull requests, waits for a CI check to **register** on the pushed sha, then watches it. `gh pr checks --watch` returns success immediately when no check exists yet, which is how a PR gets merged before CI has run. No check within 10 minutes, or a failed one, exits 4. A repo with no such workflow lands on the local gates alone.
5. `gh pr merge --merge`. It never passes `--delete-branch`: failed tickets keep their branches, and cleanup is the human's call.

Exit 2, 3 or 4 → the orchestrator's rebase round, with the script's output as findings, then rerun the script. The script is the only thing that waits on CI; stage agents neither wait on it nor report it.

To skip CI work for docs-only changes, do it **inside** a job that still reports a check (an early step that detects a docs-only diff and skips the rest). A workflow-level `paths-ignore` registers no check at all, and the script then times out waiting for one.

The landing artifact is the **PR URL**. Caveat: a repo whose branch protection requires human PR approval will hard-block the harness at merge — surface that as a failure, don't wait indefinitely.

### Mark done

The merged PR's `Closes #<n>` normally closes the issue; if it didn't, `gh issue close <n>`. Then `gh issue edit <n> --remove-label in-progress` and post the `### Landed` comment with the PR URL. Done = issue closed **and** `### Landed` comment present (a closed issue without one is a mid-crash artifact — finish the bookkeeping on resume).

### Mark failed

Post a comment starting `### Failed` (what failed, what was tried, pointer to the preserved worktree/branch), then `gh issue edit <n> --remove-label in-progress --add-label "<ready-for-human>"`. The issue stays open.

### Park (unanswered product question)

Used when the planner raises a `product:` question and no human is present. Post the question as a comment starting `### Parked`, then `gh issue edit <n> --remove-label in-progress --add-label "<needs-info>"`, and leave the worktree, branch and state block in place. No attempt is consumed. A maintainer answers by adding the decision to `## Decisions` and relabelling the issue `<ready-for-agent>`; the next run claims it again with the same `claim.sh` command and plans from the start.

When a human answers in the session instead, the orchestrator appends the answer to `## Decisions` in the issue body before relaying it.

### Run report

No file. The board already holds the durable record: plans and reviews in each issue's work log, findings on each PR, and the landing artifact in `### Landed`. A report file would only duplicate it and go stale.

- File each follow-up the run surfaced as an issue labelled `<needs-triage>`, before reporting.
- Report the summary to the user in the session.
