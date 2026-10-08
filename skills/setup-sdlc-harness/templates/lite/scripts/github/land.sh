#!/usr/bin/env bash
#
# Land a review-approved ticket PR: rebase onto origin/main, run the project's
# local gates, push, wait for CI on the pushed sha, merge.
#
# Usage: scripts/sdlc/land.sh <pr> <worktree>
# Exit codes: 0 merged; 2 rebase conflict (rebase aborted); 3 local gates
# failed; 4 CI failed or never registered. 2-4 are the orchestrator's cue for
# the landing rebase round.
#
# SDLC_CI=wait|skip overrides the CI detection below.
# SDLC_MERGE_METHOD=merge|squash|rebase picks the merge method (default merge).

set -euo pipefail

pr=${1:?pr number}
wt=${2:?worktree path}
here=$(cd "$(dirname "$0")" && pwd)
cd "$wt"

git fetch -q origin
if ! git rebase -q origin/main; then
  git rebase --abort
  echo "land: rebase onto origin/main conflicted" >&2
  exit 2
fi

if [ ! -x "$here/gates.sh" ]; then
  echo "land: $here/gates.sh is missing; it must run the project's full test suite" >&2
  exit 1
fi
"$here/gates.sh" || {
  echo "land: local gates failed on the rebased branch" >&2
  exit 3
}

git push -q --force-with-lease -u origin HEAD
sha=$(git rev-parse HEAD)
gh pr ready "$pr" >/dev/null 2>&1 || true

# Wait on CI only when a workflow runs on pull requests; a repo without one
# has nothing to wait for and lands on the local gates alone.
ci=${SDLC_CI:-}
if [ -z "$ci" ]; then
  if grep -lsq pull_request .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null; then
    ci=wait
  else
    ci=skip
  fi
fi

if [ "$ci" = wait ]; then
  # `gh pr checks --watch` returns success immediately when no check run exists
  # yet for the pushed sha, so wait for one to register before watching.
  registered=0
  for _ in $(seq 1 60); do
    registered=$(gh api "repos/{owner}/{repo}/commits/$sha/check-runs" -q .total_count || echo 0)
    [ "$registered" -gt 0 ] && break
    sleep 10
  done
  if [ "$registered" -eq 0 ]; then
    echo "land: no CI check registered for $sha after 10 minutes" >&2
    exit 4
  fi
  if ! gh pr checks "$pr" --watch --fail-fast --interval 15; then
    echo "land: CI failed for $sha" >&2
    exit 4
  fi
fi

gh pr merge "$pr" "--${SDLC_MERGE_METHOD:-merge}"
echo "land: merged $pr at $sha"
