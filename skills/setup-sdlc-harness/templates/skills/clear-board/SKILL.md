---
name: clear-board
description: "Autonomously clear a ticket board: orchestrate parallel agent groups in worktrees through plan → implement → review → land, until the board is clear or hard-blocked."
disable-model-invocation: true
---

# Clear the board

You are the **orchestrator**. You do not write code. You dispatch stage agents, route escalations, land finished work, and keep state on the board. Keep your own context lean: pass file paths, not file contents; read summaries, not diffs.

Arguments: `<feature-slug>` (defaults to the sole directory under `.scratch/` if only one exists). `--plan` = dry-run.

State conventions and status vocabulary: see `docs/agents/issue-tracker.md` § SDLC harness extensions and `docs/agents/triage-labels.md` § SDLC harness statuses.

## Dry-run (`--plan`)

Read the board, print the dependency DAG, the dispatch order/parallelism, the per-stage agent + model assignments, and the caps. Spawn nothing. Stop.

## Board state and git

- The ticket paths you pass to agents are always **absolute paths into the main checkout**. Worktrees contain a stale copy of `.scratch/` — nobody reads or writes it. Ticket branches must never touch `.scratch/`; a branch that commits board changes will conflict with the live board at every landing.
- Ticket files are tracked on main. **Commit board changes to main** (`chore(board): ...`) after each claim and each landing — landing recovery uses `git reset --hard`, which would destroy uncommitted board state.

## Hard limits (per ticket, tracked as header lines in the ticket file)

- **2 whole-ticket attempts** (`Attempts:`). An attempt = one full pipeline pass; a REPLAN verdict consumes the attempt and starts a new one.
- **2 escalations per attempt** (`Escalations:`, reset to 0 on each new attempt; planner and implementer escalations both count). A third in the same attempt means the plan is bad: treat as REPLAN.
- **2 fix rounds per attempt** (`Fix rounds:`, reset on each new attempt) — review → fix → re-review.
- **1 rebase round per landing** — a landing-time rebase-fix is mechanical, not a quality failure, so it does not consume the fix-round cap; but if landing fails again after the rebase round, the ticket is exhausted.
- Increment the counter line (and save) **before** dispatching the agent it counts — counters must survive a crash mid-stage.
- On exhaustion: set `Status: ready-for-human`, append a `## Failed` section explaining what failed and pointing at the preserved worktree/branch, and move on. Never delete a failed ticket's worktree or branch.

## Main loop

Repeat until no ticket is dispatchable and no group is running:

1. **Scan** `.scratch/<feature>/issues/`. A ticket is dispatchable when `Status: ready-for-agent` and every entry in its `## Blocked by` section is `done`. Entries look like `- NN Title` — resolve each by its `NN` prefix to `issues/NN-*.md`; the sentinel `- None ...` means no dependencies.
2. **Dispatch** up to **3 concurrent groups**. For each dispatched ticket:
   - Claim first: set `Status: in-progress`, `Attempts: 1` (or increment), reset `Escalations: 0` and `Fix rounds: 0`.
   - Create a worktree branched from **current main**: `git worktree add ../<repo>-wt-<NN> -b ticket/<NN>-<slug> main` (path may vary; record it). If the branch already exists (crash artifact or earlier attempt), rename it out of the way first (`git branch -m ticket/<NN>-<slug> ticket/<NN>-<slug>-attempt<K>`) — never delete it.
   - Record `Worktree: <path>` and `Branch: <name>`, then commit the board.
   - Run the pipeline (below) as background agents; react to completions as they arrive.
3. **On a group finishing review-approved**, land it (below).
4. **On landing**, re-scan — newly unblocked tickets dispatch immediately.

Also on start: **resume** any ticket already `in-progress` — the counter header lines are authoritative for caps; read its `## Work log` to find the last completed stage and continue from there. No `## Work log` yet means planning never finished: restart from Plan (same attempt). If its worktree is gone, count a new attempt (cap permitting) and restart the pipeline.

## Per-ticket pipeline

Each stage is one sub-agent (Agent tool) given only: ticket path (main checkout), worktree path, feature slug, attempt number — plus the fix-round number, review-round number, or escalation number where the stage calls for it. Run stages in the group's worktree, chained:

1. **Plan** — `subagent_type: sdlc-planner`. If it returns blocking open questions: resolve them yourself if trivial; otherwise this is an escalation — increment `Escalations:`, spawn `sdlc-advisor`, and relay `ANSWER:` back to the *paused planner* via SendMessage so it finalizes the plan (never restart it).
2. **Implement** — `subagent_type: sdlc-implementer`.
   - If it returns `ESCALATION:`: increment `Escalations:`; if over cap → REPLAN path. Otherwise spawn `sdlc-advisor` with the ticket path, worktree path, escalation number, and the question. On `ANSWER:` relay it to the *same paused implementer* via SendMessage (keep its context; never restart it for an answer). On `REPLAN:` abandon the stage, increment `Attempts:`, reset `Escalations:` and `Fix rounds:`, and restart from Plan (cap permitting).
3. **Review** — `subagent_type: sdlc-reviewer`, passing the review round number (first review = round 1). On *needs-fixes*: increment `Fix rounds:` (cap 2), dispatch `sdlc-implementer` again with the review findings as the work order and the fix-round number, then re-review with the next round number. On *approve*: proceed to landing.

## Landing (orchestrator does this itself, strictly serialized)

Never land two branches concurrently. Complete steps 1–4 for one ticket before touching another.

1. Commit any pending board changes on main.
2. `git merge --no-ff ticket/<NN>-<slug>`.
3. Run the full test suite on merged main (the repo's documented test command; if undocumented, the toolchain's standard one, e.g. `go test ./...`).
4. **Success**: set ticket `Status: done`, append `### Landed` to the work log with the merge commit hash (this is the landing artifact), remove the worktree (`git worktree remove`, `--force` if untracked build artifacts block it; keep the branch), commit the board, re-scan.
5. **Merge conflict** (merge did not complete): `git merge --abort`, then the rebase round (below).
6. **Post-merge test failure** (merge commit exists on main): `git reset --hard ORIG_HEAD` to drop the merge commit — safe because board state was committed in step 1 — then the rebase round.
7. **Rebase round** (1 per landing, does not consume fix rounds): dispatch a `sdlc-implementer` into the group's worktree ("rebase onto current main, resolve conflicts, make the suite pass"). Then re-review and retry landing. If landing fails again → exhaustion path.

*(GitHub-remote variant, not v1 default: push the branch, open a PR with `gh`, merge the PR; landing artifact = PR URL.)*

## Finish

When the loop exhausts, write `.scratch/<feature>/run-report.md`: tickets landed (with merge commits), tickets failed (with reasons and worktree pointers), escalation/fix-round tallies, total attempts. Commit the board one final time. Report the same summary to the user.

## Rules

- Everything durable goes in the ticket files — assume you may crash at any point and a fresh session must resume from the board alone.
- Do not resolve merge conflicts or edit code yourself; dispatch an agent.
- Do not exceed any cap for any reason. A failed ticket is a success condition of the harness, not a failure to hide.
