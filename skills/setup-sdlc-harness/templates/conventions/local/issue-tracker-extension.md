## SDLC harness extensions

Used by `/clear-board` for autonomous multi-agent runs. Defines the concrete board operations for the **local markdown** tracker.

### Ticket identity and scope

- A ticket is a file at `.scratch/<feature>/issues/<NN>-<slug>.md`; its id is the `NN` filename prefix.
- The `/clear-board` scope argument is the feature slug (defaults to the sole directory under `.scratch/` if only one exists).
- Ticket branch: `ticket/<NN>-<slug>`.

### Durability — the board lives on main

All edits to a ticket file happen at its path in the **main checkout** — the copy of `.scratch/` inside a worktree is stale and must never be read, edited, or committed on a ticket branch; a branch that commits board changes will conflict with the live board at every landing. Ticket files are tracked on main: **commit board changes to main** (`chore(board): ...`) after each claim and each landing — landing recovery uses `git reset --hard`, which would destroy uncommitted board state.

### Scan

List `.scratch/<feature>/issues/*.md` and read each `Status:` line. A ticket is dispatchable when `Status: ready-for-agent` and every `## Blocked by` entry is `done`. On start, any ticket with `Status: in-progress` is a resume candidate: its counter header lines are authoritative for caps, and its `## Work log` shows the last completed stage.

### Claim and counters (extra header lines near the top of an issue file)

Claiming = set `Status: in-progress`, write/update the header lines below, commit the board. Counters are incremented (and the file saved + committed) before dispatching the stage they count.

- `Attempts: N` — whole-pipeline attempts consumed (hard cap 2)
- `Escalations: N` — escalations this attempt (hard cap 2; reset to 0 on each new attempt)
- `Fix rounds: N` — review fix rounds this attempt (hard cap 2; reset to 0 on each new attempt; landing rebase rounds do not count here)
- `Worktree: <path>` — the group's git worktree while in progress
- `Branch: <name>` — the ticket branch (`ticket/<NN>-<slug>`); preserved even on failure

### Dependencies — `## Blocked by`

Dependency list, one entry per line as `- NN Title` (resolved by the `NN` prefix to `issues/NN-*.md`). The sentinel `- None — can start immediately` means no dependencies. A ticket is dispatchable when every listed ticket is `done`.

### Work-log entries — `## Work log`

Appended per stage by the stage agents, one subsection each:
`### Plan (attempt N)`, `### Implementation (attempt N)` — or `### Implementation (attempt N, fix round K)` for a fix round — `### Review (attempt N, round K)` (first review = round 1), `### Escalation N`, `### Landed` (the landing artifact).

### Review surface

None — a local board has no PR. Review findings go in full inside the reviewer's `### Review (attempt N, round K)` work-log entry, and the orchestrator carries them to the fix round as the work order. Agents that would otherwise post to a review surface write to the work log instead.

### Landing procedure

Lands via local merge on main in the main checkout:

1. Commit any pending board changes on main.
2. `git merge --no-ff ticket/<NN>-<slug>`.
3. Run the full test suite on merged main (the repo's documented test command; if undocumented, the toolchain's standard one, e.g. `go test ./...`).
4. **Merge conflict** (merge did not complete): `git merge --abort`, then the orchestrator's rebase round.
5. **Post-merge test failure** (merge commit exists on main): `git reset --hard ORIG_HEAD` to drop the merge commit — safe because board state was committed in step 1 — then the rebase round.

The landing artifact is the **merge commit hash**.

### Mark done

Set `Status: done`, append `### Landed` to the work log with the merge commit hash, commit the board.

### Mark failed — `## Failed`

Written by the orchestrator when a ticket exhausts its caps: what failed, what was tried, pointer to the preserved worktree/branch. Status moves to `ready-for-human`. Commit the board. (Named `Failed`, not `Blocked`, to avoid colliding with `## Blocked by`.)

### Run report

Write `.scratch/<feature>/run-report.md` and commit it with the final board commit.
