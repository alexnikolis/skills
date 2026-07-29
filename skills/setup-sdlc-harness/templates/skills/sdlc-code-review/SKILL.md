---
name: sdlc-code-review
description: "Tiered code review of a diff: finds defects, verifies them, and reports each with file:line, a concrete failure scenario, and the fix. Use when a review of changed code is explicitly requested — including by a stage agent delegating its standards axis. Tiers `low` / `medium` / `high` trade cost for verification depth. Reports findings only: posts nothing, edits nothing, runs no builds or tests."
argument-hint: "[low|medium|high] [target]"
allowed-tools: "Read, Grep, Glob, Agent, Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git merge-base:*), Bash(git rev-parse:*), Bash(git status:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(glab mr diff:*)"
---

# Tiered code review

Arguments: `$ARGUMENTS`

You review a diff and report **candidates** you can defend. Findings are the whole product — the caller decides what to do with them. The working tree ends exactly as you found it: no source edits, no comments posted, no builds, typechecks, or test runs. Those belong to whoever invoked you.

## Tier

The first argument sets the **tier** when it is `low`, `medium`, or `high`; otherwise the tier is `medium`. Everything after it is the **target**.

|          | reading depth                                  | angles                          | verify                       | cap |
| -------- | ---------------------------------------------- | ------------------------------- | ---------------------------- | --- |
| `low`    | changed hunks only                             | A                               | self-check, no subagents     | 4   |
| `medium` | + the enclosing function of each hunk          | A–E, cleanup, standards, tests  | 1 verifier per location      | 8   |
| `high`   | + callers, callees, history of touched lines   | same, plus a gap sweep          | 3-lens panel per location    | 12  |

## Phase 0 — Scope

1. Resolve the target into one diff command:
   - **empty** → the branch against its merge-base: `git diff <default-branch>...HEAD` (three dots), preferring `@{upstream}` where the branch tracks a remote. If the tree is dirty, also read `git diff HEAD`.
   - **PR/MR number or URL** → `gh pr diff <n>` (`glab mr diff <n>` on GitLab).
   - **ref or range** (`main...HEAD`, `abc123..def456`) → use it verbatim.
   - **path** → the default range restricted with `-- <path>`.
   - **anything else** → scope guidance: narrow the default range to match it.
2. Run the command. An empty diff ends the review: report that nothing is in scope and stop.
3. List the changed files.
4. Read the standards governing them — `medium` and `high` only, since `low` skips that angle: the CLAUDE.md chain (`~/.claude/CLAUDE.md`, the repo root, and any `CLAUDE.md` / `CLAUDE.local.md` in a directory above a changed file), plus the repo's own standards docs for the changed area (`CONTEXT.md`, `docs/`).

Done when you hold a diff command that produced a non-empty diff, the changed-file list, and the standards those files answer to.

## Phase 1 — Find candidates

Work the angles yourself, in this context. The fan-out is verification, not reading — cost tracks the findings you produce rather than the readers you hire.

Every candidate carries `file`, `line` (new side), a one-line `summary`, and a `failure_scenario`: the user-visible consequence — wrong output, crash, data loss, a named cost — not an intermediate state ("the value goes stale", "the set grows"). A candidate you cannot give a failure scenario to is not a candidate.

At `low`, work angle A over the hunks alone, skip test and fixture files (`test/`, `spec/`, `__tests__/`, `*_test.*`, `*.test.*`, `fixtures/`, `testdata/`), and go straight to Phase 4.

### Correctness

- **A — hunk scan.** Read every changed line, then the function enclosing it (a bug on an untouched line of a touched function is in scope: the diff re-exposes it). For each, ask what input, state, timing, or platform makes it wrong. Inverted condition, off-by-one, null/undefined deref where adjacent lines show the value can be absent, falsy-zero check, missing `await`, wrong-variable copy-paste, error swallowed in a `catch` that should propagate, unescaped regex metachar.
- **B — removed behaviour.** For every line the diff deletes or replaces, name the invariant it enforced, then find where the new code re-establishes it. A guard, error path, validation, or covering test with no successor is a candidate.
- **C — blast radius.** For each changed signature, return shape, precondition, thrown error, or ordering dependency, Grep the callers and check each site against the new contract. Then check callees the same diff touched: does a parallel change make an existing call unsafe?
- **D — language pitfalls.** The classic traps of the diff's language and framework — JS falsy-zero, `==` coercion, closure-captured loop vars; Python mutable default args, late-binding closures; Go nil-map writes, range-var capture; SQL injection; timezone/DST drift; float equality.
- **E — wrapper correctness.** For a new or modified cache, proxy, decorator, or adapter: every method routes to the wrapped instance rather than back through a registry, session, or global (a caching provider resolving via `session.get(...)` instead of `delegate.get(...)` re-enters itself), and the wrapper forwards every method its callers use.

### Cleanup, standards, and tests (`medium` and `high`)

State the concrete cost in `failure_scenario` — what is duplicated, wasted, harder to change, or which rule is broken.

- **Reuse.** New code re-implementing something the repo already has. Grep shared and adjacent modules; name the existing helper to call instead.
- **Simplification.** Complexity the diff adds: derivable state stored, copy-paste with variation, deep nesting, dead code left behind. Name the simpler form that does the same job.
- **Efficiency.** Wasted work the diff introduces: repeated I/O, independent operations run sequentially, blocking work added to startup or a hot path, long-lived objects built from closures that pin their whole enclosing scope. Name the cheaper alternative.
- **Altitude.** Special cases layered on shared infrastructure where generalizing the mechanism is the real fix.
- **Standards.** Clear violations of the docs read in Phase 0. Quote the exact rule and the exact line that breaks it, and name the doc — a rule you cannot quote is a style preference, not a finding.
- **Tests.** New or changed tests that assert nothing about the behaviour under test (asserting on a mock, a snapshot with no claim, a call that cannot fail), and behaviour the diff adds that the repo's own docs say must be covered.

Carry every candidate with a nameable failure scenario into verification. Half-believed candidates dropped here never get a verdict, and that silent drop is the main source of misses.

## Phase 2 — Verify

Group candidates by `file:line` — one verification per location, covering every candidate there. Rank groups correctness-first and verify at most 12 (`medium`) or 8 (`high`); anything past that cap is reported as unverified rather than dropped.

- **`low`** — re-read each candidate against the diff yourself and keep only what you can still defend.
- **`medium`** — one verifier subagent per group. Give it the diff command, the file, and the group's candidates numbered `[0]`, `[1]`, …; it returns one verdict and its evidence per index, judging each claim independently.
- **`high`** — three verifiers per group, one lens each: **correctness** (is the mechanism real?), **blast radius** (does something outside the hunk already prevent it, or make it worse?), and **reproduction** (name the exact input or state that triggers it). Keep the candidate unless two of the three refute it.

Spawn verifiers in batches of at most 8 per message so they run concurrently.

Each verifier returns exactly one verdict per candidate:

- **CONFIRMED** — names the inputs or state that trigger it and the wrong output, crash, or cost. Quotes the line.
- **PLAUSIBLE** — the mechanism is real, the trigger is uncertain (timing, environment, config). States what would confirm it.
- **REFUTED** — the code disproves it: factually wrong (quote the actual line), impossible by type/constant/invariant (show it), already guarded (cite the guard), or pure style with no observable effect.

Refute only what the code disproves. Realistic-but-uncommon state is PLAUSIBLE, not REFUTED: concurrency races, a nil on a rare-but-reachable path (error handler, cold cache, absent optional field), falsy-zero treated as missing, a boundary the code does not exclude, retry storms and partial failures, a regex or allowlist that lost an anchor.

When the `Agent` tool is absent from your tool set, verify each candidate yourself against the diff and the enclosing file, and say in the report that verification ran inline — whoever reads it should know what actually ran.

## Phase 3 — Sweep (`high`)

Re-read the diff yourself holding the verified list, hunting only for what is not on it: moved or extracted code that dropped a guard or anchor, setup/teardown asymmetry in tests, config defaults flipped, second-tier footguns (a default evaluated once at definition time, hash non-determinism, a lock scope quietly narrowed, a predicate method with side effects). Verify anything new the same way. An empty sweep is a valid result — padding it costs the caller trust.

## Phase 4 — Report

Drop before ranking:

- defects on lines the diff did not touch and does not re-expose
- anything a linter, typechecker, or compiler already catches
- nitpicks a senior engineer would let through
- behaviour changes that are the point of the diff
- rules silenced in place with an explicit ignore comment

Merge candidates naming the same defect at the same place, keeping the most concrete. Rank correctness above cleanup, CONFIRMED above PLAUSIBLE, and keep the tier's cap. Then output exactly this shape:

```markdown
## Code review — <tier> tier

<2–3 sentences: what the diff does, and what the review found>

### Findings (<n>)

#### 1. `path/to/file.ts:42` — CONFIRMED · correctness
**Wrong:** one sentence.
**Failure:** concrete inputs or state → wrong output, crash, or cost.
**Evidence:** the quoted line, or the guard that makes this reachable.
**Fix:** the concrete change.

### Refuted
- `path/to/other.ts:17` — <candidate> (<the line that disproves it>)

<k> files reviewed at <tier> tier · <c> candidates → <v> verified → <n> reported · verification ran <in N subagents | inline>
```

Every finding keeps its `path:line` on the diff's new side, so a caller can post it as an inline comment without re-deriving the location. Omit the `Refuted` section when nothing was refuted; say `### Findings (0)` plainly when nothing survived. If the location cap left candidates unverified, list them under a `### Unverified` section — a capped review that reads as an exhaustive one is worse than a smaller honest one.
