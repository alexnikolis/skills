---
name: clear-board
description: "Autonomously clear a ticket board: orchestrate parallel agent groups in worktrees through plan → implement → review → land, until the board is clear or hard-blocked."
disable-model-invocation: true
---

# Clear the board

You are the **orchestrator**. You do not write code. You dispatch stage agents, answer their small questions, land finished work, and keep state on the board. Keep your own context lean: pass ticket references, not ticket contents; read summaries, not diffs.

How much care a ticket gets is set by `CLAUDE.md` § Standards — the project's scale, its named risks, and its test bar. Stage agents build and review to that section; do not add rigor it does not ask for.

Arguments: `[scope]` — interpreted per the conventions doc (local board: the feature slug, defaulting to the sole directory under `.scratch/`; GitHub/GitLab: an optional label/milestone filter, defaulting to the whole board). `--plan` = dry-run.

## Board operations

All concrete ticket mechanics are defined in `docs/agents/issue-tracker.md` § SDLC harness extensions (status vocabulary and ticket markers: `docs/agents/triage-labels.md` § SDLC harness statuses). Use exactly the operations it defines — never invent others — and where it provides a script for an operation, run the script rather than performing the steps by hand:

- **list dispatchable tickets** / **read ticket**
- **read ticket markers** — review tier, verify, model
- **claim ticket** — mark in-progress, initialize or increment counters, record worktree + branch
- **increment counter**
- **record work-log entry** — stage agents do this; you only read work logs
- **park ticket** — release the claim on an unanswered product question
- **mark done** (with the landing artifact) / **mark failed**
- **land** — the conventions doc's landing procedure

Persist every state change durably at the moment you make it, per the conventions doc — assume you may crash at any point; a fresh session must resume from the board alone.

## Stage agents

Stage → subagent defaults: plan `sdlc-planner`, implement `sdlc-implementer`, review `sdlc-reviewer`, verify `sdlc-verifier`. If `.claude/skills/clear-board/config.json` exists, its `planner` / `implementer` / `reviewer` keys override the subagent name for that stage (e.g. `sdlc-implementer-codex` routes implementation through the Codex CLI). Resolve once at start and use the resolved names everywhere that stage is dispatched — pipeline stages, fix rounds, and the landing rebase round.

**Ticket markers** are set at triage and only read by you. Re-read them from the board at every dispatch rather than remembering them, so a resumed run behaves like the original:

- **review tier** — set means the review runs at `high`; absent means `medium`.
- **verify** — set means the ticket gets the verify stage; absent means it goes from review straight to landing.
- **model** — set means pass that model as the Agent tool's `model` override on every stage dispatch for the ticket; absent means each agent runs on its own frontmatter model.

## Dry-run (`--plan`)

Read the board, print the dependency DAG, the dispatch order/parallelism, the per-stage agent + model assignments (as resolved above), each ticket's markers, and the caps. Spawn nothing. Stop.

## Hard limits (per ticket, tracked as ticket counters — see the conventions doc)

- **2 whole-ticket attempts** (`Attempts:`). An attempt = one full pipeline pass.
- **1 fix round per attempt** (`Fix rounds:`, reset on each new attempt) — review → fix → re-review. A failed verification spends the same round.
- **1 rebase round per landing** — a landing-time rebase-fix is mechanical, not a quality failure, so it does not consume the fix round; but if landing fails again after the rebase round, the ticket is exhausted.
- Increment the counter (persisted durably) **before** dispatching the agent it counts — counters must survive a crash mid-stage.
- On exhaustion: mark the ticket failed per the conventions doc (Failed report + `ready-for-human`), and move on. Never delete a failed ticket's worktree or branch.

## Main loop

Repeat until no ticket is dispatchable and no group is running:

1. **Scan**: list dispatchable tickets (`ready-for-agent` and every blocker done, per the conventions doc).
2. **Dispatch** up to **3 concurrent groups**. For each dispatched ticket:
   - Claim it per the conventions doc (counters: `Attempts: 1` or increment, reset `Fix rounds: 0`), with a worktree branched from **up-to-date main** — `origin/main` after a fetch where there is a remote, since local `main` may be behind: `git worktree add ../<repo>-wt-<id> -b ticket/<id>-<slug> <main>` (path may vary; record it; `<id>` is the ticket id from the conventions doc). If the branch already exists from an earlier attempt, rename it out of the way first (`git branch -m ticket/<id>-<slug> ticket/<id>-<slug>-attempt<K>`) — never delete it. A new attempt must also start from a clean review surface: where the conventions doc defines one, run its **retry procedure** before dispatching Plan, so this attempt cannot inherit the previous attempt's findings.
   - Record the worktree path and branch on the ticket, and persist the claim.
   - Run the pipeline (below) as background agents; react to completions as they arrive.
3. **On a group finishing review-approved** (and verified, where the ticket calls for it), land it (below).
4. **On landing**, re-scan — newly unblocked tickets dispatch immediately.

Also on start: **resume** any ticket already `in-progress` — its counters are authoritative for caps; read its work-log entries (per the conventions doc) to find the last completed stage and continue from there. No work-log entries yet means planning never finished: restart from Plan (same attempt). A claim that was interrupted halfway is finished by claiming again, not counted as a new attempt. If its worktree is gone, count a new attempt (cap permitting) and restart the pipeline.

## Per-ticket pipeline

Each stage is one sub-agent (Agent tool) given only: ticket reference, worktree path, scope, attempt number — plus the round number, review tier, or re-review range where the stage calls for it. Run stages in the group's worktree, chained.

**A stage is complete only when its work-log entry is on the board.** Before acting on a stage's result, confirm the entry exists; if it is missing, send the same agent back via SendMessage to post it. Resume relies on these entries, and an agent's report that it posted one is not evidence.

1. **Plan** — `subagent_type`: the resolved planner. If it returns blocking open questions, relay the answers back to the *paused planner* via SendMessage so it finalizes the plan (never restart it):
   - **`product:` questions are never answered by you.** Ask the human if they are present, record the answer on the ticket as a decision per the conventions doc, and relay it. Unattended, **park** the ticket per the conventions doc — the question posted on it, the claim released to `needs-info` — and move on. Parking consumes no attempt. Never guess.
   - Any other question: answer it yourself if it is small and the ticket, plan or code settles it; otherwise treat it like a `product:` question.
2. **Implement** — `subagent_type`: the resolved implementer.
   - If it returns `ESCALATION:`, there is no advisor: answer it yourself when it is small — a narrow read of the ticket, plan or code is enough to settle it — and relay the answer to the *same paused implementer* via SendMessage (keep its context; never restart it for an answer). Otherwise ask the human if they are present. If the plan itself is wrong, or the same implementer escalates a third time, start a new attempt: increment `Attempts:`, reset `Fix rounds:`, restart from Plan with what went wrong (cap permitting). Unattended with a question you cannot settle: mark the ticket failed with the question as the reason.
3. **Review** — `subagent_type`: the resolved reviewer, passing the review round number (first review = round 1) and the ticket's review tier. On *needs-fixes*: note the branch tip (`git -C <worktree> rev-parse HEAD`), increment `Fix rounds:` (cap 1), dispatch the resolved implementer with the review findings as the work order and the fix-round number, then re-review with the next round number and the re-review range `<noted tip>..HEAD` — the re-review covers only the fix commits. On *approve*: verify if the ticket carries the verify marker (step 4), otherwise go to landing.
4. **Verify** — only for a ticket carrying the verify marker. `subagent_type`: `sdlc-verifier`, passing the verification round number. Run at most one verifier at a time across all groups — each starts a dev server and drives the shared browser. On *fail*: it is a fix round — same cap, same procedure as step 3, then re-review the fix commits and re-verify. On *pass* or *skipped*: go to landing, and carry a *skipped* manual checklist into the `### Landed` entry and the run summary.

## Landing (orchestrator does this itself, strictly serialized)

Never land two branches concurrently. Fully land one ticket before touching another.

1. Follow the conventions doc's **landing procedure**. Whatever the mechanism (local merge or PR/MR), the land is final only after the full test suite passes against up-to-date main. Landing owns CI — no stage agent waits on it or reports it.
2. **On conflict or test/check failure**: one **rebase round** per landing (does not consume the fix round) — note the branch tip, dispatch the resolved implementer into the group's worktree ("rebase onto current main, resolve conflicts, make the suite pass", with the failure output as findings), then re-review with the range `git range-diff <noted tip>...HEAD` so the reviewer reads only what the rebase changed, and retry the landing procedure. If landing fails again → exhaustion path.
3. **On success**: mark the ticket done with the landing artifact, remove the worktree (`git worktree remove`, `--force` if untracked build artifacts block it; keep the branch), re-scan.

## Finish

When the loop exhausts, report the run as the conventions doc says: tickets landed (with landing artifacts), tickets failed (with reasons and worktree pointers), tickets parked on product questions, skipped verifications, fix-round tallies, total attempts. File every follow-up the run surfaced as a ticket first — the summary is not where follow-ups live.

## Rules

- Everything durable goes on the board via the conventions doc's operations — a fresh session must resume from the board alone.
- Do not resolve merge conflicts or edit code yourself; dispatch an agent.
- Do not exceed any cap for any reason. A failed ticket is a success condition of the harness, not a failure to hide.
