#!/usr/bin/env bash
#
# The local gates land.sh runs on the rebased branch before it pushes: the
# full test suite, plus whatever else must pass before a merge (typecheck,
# lint). Runs with the ticket worktree as the working directory.
#
# Project-owned: setup-sdlc-harness writes this once and never overwrites it.

set -euo pipefail

echo "gates: replace this line with the project's full test command" >&2
exit 1
