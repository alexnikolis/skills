#!/usr/bin/env bash
#
# Claim a ticket: worktree branched from origin/main, harness-state block,
# in-progress label, worktree setup hook.
#
# Usage: scripts/sdlc/claim.sh <issue> <slug> [worktree-path]
# Prints the worktree path and branch.
#
# Safe to rerun: each step first checks whether it already happened, so a claim
# that died halfway is finished by running the same command again. It never
# touches the counters of an existing state block; a later attempt sets those
# with state.sh, then runs this with a fresh worktree path.

set -euo pipefail

n=${1:?issue number}
slug=${2:?slug}
ready=${SDLC_READY_LABEL:-ready-for-agent}
repo=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
wt=${3:-"$(dirname "$repo")/$(basename "$repo")-wt-$n"}
br="ticket/$n-$slug"
here=$(cd "$(dirname "$0")" && pwd)

# GitHub's API fails transiently; a single failed call must not strand a claim.
retry() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    sleep $((i * 5))
  done
  echo "claim: giving up on: $*" >&2
  return 1
}

git -C "$repo" fetch -q origin
if [ -e "$wt" ]; then
  on=$(git -C "$wt" branch --show-current 2>/dev/null || true)
  if [ "$on" != "$br" ]; then
    echo "claim: $wt exists but is not on $br (found '${on:-no branch}'); pass a different worktree path" >&2
    exit 1
  fi
elif git -C "$repo" show-ref --verify --quiet "refs/heads/$br"; then
  echo "claim: branch $br exists without a worktree at $wt; follow the retry procedure" >&2
  exit 1
else
  git -C "$repo" worktree add -q "$wt" -b "$br" origin/main
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
retry gh issue view "$n" --json body -q .body >"$body"
if grep -q '<!-- sdlc-harness-state -->' "$body"; then
  "$here/state.sh" "$n" set Worktree "$wt" >/dev/null
  "$here/state.sh" "$n" set Branch "$br" >/dev/null
else
  printf '\n<!-- sdlc-harness-state -->\nAttempts: 1\nFix rounds: 0\nWorktree: %s\nBranch: %s\n<!-- /sdlc-harness-state -->\n' "$wt" "$br" >>"$body"
  retry gh issue edit "$n" --body-file "$body" >/dev/null
fi

labels=$(retry gh issue view "$n" --json labels -q '.labels[].name')
if ! grep -qx in-progress <<<"$labels"; then
  retry gh issue edit "$n" --add-label in-progress >/dev/null
fi
if grep -qxF "$ready" <<<"$labels"; then
  retry gh issue edit "$n" --remove-label "$ready" >/dev/null
fi

if [ -x "$here/setup-worktree.sh" ]; then
  (cd "$wt" && "$here/setup-worktree.sh" "$repo")
fi

echo "worktree: $wt"
echo "branch: $br"
