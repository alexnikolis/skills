---
name: sdlc-code-review
description: "Code review of a diff: finds defects worth raising, verifies them, and reports each with file:line, a concrete failure scenario, and the fix. Use when a review of changed code is explicitly requested — including by a stage agent delegating its standards axis. Tier `high` deepens verification. Reports findings only: posts nothing, edits nothing, runs no builds or tests."
argument-hint: "[low|medium|high] [target]"
allowed-tools: "Read, Grep, Glob, Agent, Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git merge-base:*), Bash(git rev-parse:*), Bash(git status:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(glab mr diff:*)"
---

# Code review

Arguments: `$ARGUMENTS`

You review a diff and report findings you can defend. Findings are the whole product — the caller decides what to do with them. The working tree ends exactly as you found it: no source edits, no comments posted, no builds, typechecks, or test runs. Those belong to whoever invoked you.

If the first argument is `low`, `medium`, or `high`, it names the tier and everything after it is the **target**; otherwise the whole argument string is the target. `high` deepens verification (below); the other tiers run identically.

## Scope

Resolve the target into one diff command:

- **empty** → the branch against its merge-base: `git diff <default-branch>...HEAD` (three dots), preferring `@{upstream}` where the branch tracks a remote. If the tree is dirty, also read `git diff HEAD`.
- **PR/MR number or URL** → `gh pr diff <n>` (`glab mr diff <n>` on GitLab).
- **ref or range** (`main...HEAD`, `abc123..def456`) → use it verbatim.
- **path** → the default range restricted with `-- <path>`.
- **anything else** → scope guidance: narrow the default range to match it.

An empty diff ends the review: report that nothing is in scope and stop. Then read the standards governing the changed files — the CLAUDE.md chain (`~/.claude/CLAUDE.md`, the repo root, any `CLAUDE.md` / `CLAUDE.local.md` above a changed file) and the repo's standards docs for the changed area (`CONTEXT.md`, `docs/`).

## Review

Read the full diff and enough surrounding code to judge it — at least the function enclosing each hunk, and the callers wherever a signature, return shape, or contract changed. How you hunt is your call; you know how code breaks. What qualifies as a finding is not:

- It carries `file`, `line` (new side), a one-line summary, and a **failure scenario**: the user-visible consequence — wrong output, crash, data loss, a named cost — not an intermediate state ("the value goes stale" is not a failure). No defensible failure scenario, no finding.
- It clears the bar a competent senior reviewer applies: correctness findings they would block the merge over; cleanup and efficiency findings only when the cost is concrete and worth an extra round. A standards violation is a finding only when you can quote the exact rule and name the doc — a rule you cannot quote is a style preference.

Never report:

- defects on lines the diff neither touched nor re-exposed
- anything a linter, typechecker, or compiler already catches
- nitpicks a senior engineer would let through
- behaviour changes that are the point of the diff
- rules silenced in place with an explicit ignore comment

## Verify

Send the **whole finding list to one verifier subagent** in a single message: the diff command, the findings numbered `[0]`, `[1]`, …, and the instruction to judge each independently and flag any that name the same defect. Per finding it returns one verdict:

- **CONFIRMED** — names the inputs or state that trigger it and the wrong output, crash, or cost. Quotes the line.
- **PLAUSIBLE** — the mechanism is real, the trigger is uncertain (timing, environment, config). States what would confirm it.
- **REFUTED** — the code disproves it: factually wrong (quote the actual line), impossible by type/constant/invariant, or already guarded (cite the guard). Realistic-but-uncommon state — races, rare-but-reachable paths, boundaries, falsy zeroes — is PLAUSIBLE, not REFUTED.

At tier `high`, run three whole-list verifiers instead of one, a lens each — **correctness** (is the mechanism real?), **blast radius** (does something outside the hunk prevent it?), **reproduction** (name the exact trigger) — and drop a finding only when two of the three refute it.

When the `Agent` tool is absent, verify each finding yourself against the code and say in the report that verification ran inline.

Drop what was refuted, merge duplicates keeping the most concrete, rank correctness above cleanup and CONFIRMED above PLAUSIBLE.

## Report

Output exactly this shape:

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
- `path/to/other.ts:17` — <finding> (<the line that disproves it>)

<k> files reviewed · <c> candidates → <n> reported · verification ran <in N subagents | inline>
```

Every finding keeps its `path:line` on the diff's new side, so a caller can post it as an inline comment without re-deriving the location. Omit the `Refuted` section when nothing was refuted; say `### Findings (0)` plainly when nothing survived.
