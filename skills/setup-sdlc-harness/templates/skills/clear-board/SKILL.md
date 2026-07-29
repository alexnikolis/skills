---
name: clear-board
description: "Autonomously clear a ticket board: orchestrate parallel agent groups in worktrees through plan → implement → review → land, until the board is clear or hard-blocked."
disable-model-invocation: true
---

# Clear the board

You are the **orchestrator**. You do not write code. You dispatch stage agents, route escalations, land finished work, and keep state on the board. Keep your own context lean: pass ticket references, not ticket contents; read summaries, not diffs.

Arguments: `[scope]` — interpreted per the conventions doc (local board: the feature slug, defaulting to the sole directory under `.scratch/`; GitHub/GitLab: an optional label/milestone filter, defaulting to the whole board). `--plan` = dry-run.

## Board operations

All concrete ticket mechanics are defined in `docs/agents/issue-tracker.md` § SDLC harness extensions (status vocabulary: `docs/agents/triage-labels.md` § SDLC harness statuses). Use exactly the operations it defines — never invent others:

- **list dispatchable tickets** / **read ticket**
- **claim ticket** — mark in-progress, initialize or increment counters, record worktree + branch
- **increment counter**
- **record work-log entry** — stage agents do this; you only read work logs
- **mark done** (with the landing artifact) / **mark failed**
- **land** — the conventions doc's landing procedure

Persist every state change durably at the moment you make it, per the conventions doc — assume you may crash at any point; a fresh session must resume from the board alone.

## Stage agents

Stage → subagent defaults: plan `sdlc-planner`, implement `sdlc-implementer`, review `sdlc-reviewer`, advise `sdlc-advisor`. If `.claude/skills/clear-board/config.json` exists, its `planner` / `implementer` / `reviewer` keys override the subagent name for that stage (e.g. `sdlc-implementer-codex` routes implementation through the Codex CLI). Resolve once at start and use the resolved names everywhere that stage is dispatched — pipeline stages, fix rounds, and the landing rebase round. The escalation flow is unchanged: alternate backends bridge SendMessage internally.

## Dry-run (`--plan`)

Read the board, print the dependency DAG, the dispatch order/parallelism, the per-stage agent + model assignments (as resolved above), and the caps. Spawn nothing. Stop.

## Hard limits (per ticket, tracked as ticket counters — see the conventions doc)

- **2 whole-ticket attempts** (`Attempts:`). An attempt = one full pipeline pass; a REPLAN verdict consumes the attempt and starts a new one.
- **2 escalations per attempt** (`Escalations:`, reset to 0 on each new attempt; planner and implementer escalations both count). A third in the same attempt means the plan is bad: treat as REPLAN.
- **2 fix rounds per attempt** (`Fix rounds:`, reset on each new attempt) — review → fix → re-review.
- **1 rebase round per landing** — a landing-time rebase-fix is mechanical, not a quality failure, so it does not consume the fix-round cap; but if landing fails again after the rebase round, the ticket is exhausted.
- Increment the counter (persisted durably) **before** dispatching the agent it counts — counters must survive a crash mid-stage.
- On exhaustion: mark the ticket failed per the conventions doc (Failed report + `ready-for-human`), and move on. Never delete a failed ticket's worktree or branch.

## Main loop

Repeat until no ticket is dispatchable and no group is running:

1. **Scan**: list dispatchable tickets (`ready-for-agent` and every blocker done, per the conventions doc).
2. **Dispatch** up to **3 concurrent groups**. For each dispatched ticket:
   - Claim first (counters: `Attempts: 1` or increment, reset `Escalations: 0` and `Fix rounds: 0`).
   - Create a worktree branched from **current main**: `git worktree add ../<repo>-wt-<id> -b ticket/<id>-<slug> main` (path may vary; record it; `<id>` is the ticket id from the conventions doc). If the branch already exists (crash artifact or earlier attempt), rename it out of the way first (`git branch -m ticket/<id>-<slug> ticket/<id>-<slug>-attempt<K>`) — never delete it. A new attempt must also start from a clean review surface: where the conventions doc defines one, run its **retry procedure** before dispatching Plan, so this attempt cannot inherit the previous attempt's findings.
   - Record the worktree path and branch on the ticket, and persist the claim.
   - Run the pipeline (below) as background agents; react to completions as they arrive.
3. **On a group finishing review-approved**, land it (below).
4. **On landing**, re-scan — newly unblocked tickets dispatch immediately.

Also on start: **resume** any ticket already `in-progress` — its counters are authoritative for caps; read its work-log entries (per the conventions doc) to find the last completed stage and continue from there. No work-log entries yet means planning never finished: restart from Plan (same attempt). If its worktree is gone, count a new attempt (cap permitting) and restart the pipeline.

## Per-ticket pipeline

Each stage is one sub-agent (Agent tool) given only: ticket reference, worktree path, scope, attempt number — plus the fix-round number, review-round number, or escalation number where the stage calls for it. Run stages in the group's worktree, chained:

1. **Plan** — `subagent_type`: the resolved planner. If it returns blocking open questions: resolve them yourself if trivial; otherwise this is an escalation — increment `Escalations:`, spawn `sdlc-advisor`, and relay `ANSWER:` back to the *paused planner* via SendMessage so it finalizes the plan (never restart it).
2. **Implement** — `subagent_type`: the resolved implementer.
   - If it returns `ESCALATION:`: increment `Escalations:`; if over cap → REPLAN path. Otherwise spawn `sdlc-advisor` with the ticket reference, worktree path, escalation number, and the question. On `ANSWER:` relay it to the *same paused implementer* via SendMessage (keep its context; never restart it for an answer). On `REPLAN:` abandon the stage, increment `Attempts:`, reset `Escalations:` and `Fix rounds:`, and restart from Plan (cap permitting).
3. **Review** — `subagent_type`: the resolved reviewer, passing the review round number (first review = round 1). On *needs-fixes*: increment `Fix rounds:` (cap 2), dispatch the resolved implementer again with the review findings as the work order and the fix-round number, then re-review with the next round number. On *approve*: proceed to landing.

## Landing (orchestrator does this itself, strictly serialized)

Never land two branches concurrently. Fully land one ticket before touching another.

1. Follow the conventions doc's **landing procedure**. Whatever the mechanism (local merge or PR/MR), the land is final only after the full test suite passes against up-to-date main.
2. **On conflict or test/check failure**: one **rebase round** per landing (does not consume fix rounds) — dispatch the resolved implementer into the group's worktree ("rebase onto current main, resolve conflicts, make the suite pass", with the failure output as findings), then re-review and retry the landing procedure. If landing fails again → exhaustion path.
3. **On success**: mark the ticket done with the landing artifact, remove the worktree (`git worktree remove`, `--force` if untracked build artifacts block it; keep the branch), re-scan.

## Finish

When the loop exhausts, write the run report where the conventions doc says: tickets landed (with landing artifacts), tickets failed (with reasons and worktree pointers), escalation/fix-round tallies, total attempts. Report the same summary to the user.

## Rules

- Everything durable goes on the board via the conventions doc's operations — a fresh session must resume from the board alone.
- Do not resolve merge conflicts or edit code yourself; dispatch an agent.
- Do not exceed any cap for any reason. A failed ticket is a success condition of the harness, not a failure to hide.
