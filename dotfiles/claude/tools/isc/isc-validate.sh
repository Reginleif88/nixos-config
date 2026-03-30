#!/usr/bin/env bash
# ISC validation hook for Claude Code Stop event
# Non-blocking: reports progress as additionalContext

ISC_FILE="$HOME/.claude/MEMORY/Work/current-isc.json"

# No ISC active, nothing to do
if [ ! -f "$ISC_FILE" ] || [ ! -s "$ISC_FILE" ]; then
  exit 0
fi

# Check if valid JSON with rows
ROW_COUNT=$(jq '.rows | length' "$ISC_FILE" 2>/dev/null)
if [ -z "$ROW_COUNT" ] || [ "$ROW_COUNT" = "0" ]; then
  exit 0
fi

PENDING=$(jq '[.rows[] | select(.status == "PENDING")] | length' "$ISC_FILE" 2>/dev/null)
ACTIVE=$(jq '[.rows[] | select(.status == "ACTIVE")] | length' "$ISC_FILE" 2>/dev/null)
DONE=$(jq '[.rows[] | select(.status == "DONE")] | length' "$ISC_FILE" 2>/dev/null)
BLOCKED=$(jq '[.rows[] | select(.status == "BLOCKED")] | length' "$ISC_FILE" 2>/dev/null)
REQUEST=$(jq -r '.request // "unknown"' "$ISC_FILE" 2>/dev/null)
PHASE=$(jq -r '.phase // "unknown"' "$ISC_FILE" 2>/dev/null)

if [ "$DONE" != "$ROW_COUNT" ]; then
  echo "ISC [$PHASE]: \"$REQUEST\" — ${DONE}/${ROW_COUNT} done, ${PENDING} pending, ${ACTIVE} active, ${BLOCKED} blocked"
fi

exit 0
