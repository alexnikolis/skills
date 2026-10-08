#!/usr/bin/env bash
#
# Create every label the SDLC harness reads or writes that the repo does not
# have yet. Existing labels are left exactly as they are, so this is safe to
# rerun.
#
# Usage: scripts/sdlc/labels.sh
# Set SDLC_*_LABEL where docs/agents/triage-labels.md maps a triage role to a
# different label string.

set -euo pipefail

existing=$(gh label list --limit 500 --json name -q '.[].name')

ensure() {
  if grep -qxF "$1" <<<"$existing"; then
    return 0
  fi
  gh label create "$1" --color "$2" --description "$3"
}

ensure "${SDLC_TRIAGE_LABEL:-needs-triage}" D4C5F9 "Maintainer needs to evaluate this issue"
ensure "${SDLC_INFO_LABEL:-needs-info}" D93F0B "Waiting on an answer before work can start"
ensure "${SDLC_READY_LABEL:-ready-for-agent}" 0E8A16 "Fully specified, ready for an AFK agent"
ensure "${SDLC_HUMAN_LABEL:-ready-for-human}" B60205 "Requires human implementation"
ensure in-progress FBCA04 "Claimed by the SDLC harness"
ensure sdlc:verify 1D76DB "Run the browser verification stage for this ticket"
ensure sdlc:deep-review 5319E7 "Review this ticket at the high sdlc-code-review tier"
for alias in opus sonnet haiku fable; do
  ensure "sdlc:model-$alias" C2E0C6 "Run this ticket's SDLC stages on $alias"
done
