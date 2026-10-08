#!/usr/bin/env bash
#
# Read or update one field in a ticket's harness-state block. Only the text
# between the sdlc-harness-state markers is touched; the rest of the issue
# body is written back byte-for-byte.
#
# Usage: scripts/sdlc/state.sh <issue> get  <Field>
#        scripts/sdlc/state.sh <issue> set  <Field> <value>
#        scripts/sdlc/state.sh <issue> incr <Field>
# <Field> is the label before the colon, e.g. "Fix rounds". Prints the
# resulting value.

set -euo pipefail

n=${1:?issue number}
op=${2:?get|set|incr}
field=${3:?field}

# GitHub's API fails transiently; retry rather than leave a counter unwritten.
retry() {
  local i
  for i in 1 2 3; do
    "$@" && return 0
    sleep $((i * 5))
  done
  echo "state: giving up on: $*" >&2
  return 1
}

body=$(mktemp)
trap 'rm -f "$body" "$body.new"' EXIT
retry gh issue view "$n" --json body -q .body >"$body"

current=$(awk -v f="$field" '
  /<!-- sdlc-harness-state -->/ { inside = 1; next }
  /<!-- \/sdlc-harness-state -->/ { inside = 0 }
  inside && index($0, f ": ") == 1 { print substr($0, length(f) + 3); found = 1 }
  END { if (!found) exit 1 }
' "$body") || {
  echo "state: no '$field' in the harness-state block of issue $n" >&2
  exit 1
}

case "$op" in
  get)
    echo "$current"
    exit 0
    ;;
  set) value=${4:?value} ;;
  incr) value=$((current + 1)) ;;
  *)
    echo "state: unknown op '$op'" >&2
    exit 1
    ;;
esac

awk -v f="$field" -v v="$value" '
  /<!-- sdlc-harness-state -->/ { inside = 1 }
  /<!-- \/sdlc-harness-state -->/ { inside = 0 }
  inside && index($0, f ": ") == 1 { print f ": " v; next }
  { print }
' "$body" >"$body.new"

retry gh issue edit "$n" --body-file "$body.new" >/dev/null
echo "$value"
