#!/bin/bash
# Decision Guard — SessionStart Hook
# Fires at the start of every fresh session and after context compaction.
# Injects all active decision summaries so Claude has full journal context
# from the start — independent of prompt keywords or file scope.
#
# This solves the cold-start problem: at session start there are no
# uncommitted changes, so prompt-check.sh's scope matching can't help.
# This hook ensures Claude always knows the full journal state.
#
# Input:  JSON on stdin (not parsed)
# Output: Plain text to stdout (injected as context)
# Exit:   Always 0 (inform, never block)

[ ! -d .decisions ] && exit 0

OUTPUT=""
COUNT=0

for f in .decisions/DEC-*.md; do
  [ -f "$f" ] || continue

  status=$(grep '^status:' "$f" | tr -d '\r' | head -1 | sed 's/^status:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')
  [ "$status" = "active" ] || continue

  id=$(grep '^id:' "$f" | tr -d '\r' | head -1 | sed 's/^id:[[:space:]]*//')
  title=$(grep '^title:' "$f" | tr -d '\r' | head -1 | sed 's/^title:[[:space:]]*//' | sed 's/^"//;s/"$//')
  category=$(grep '^category:' "$f" | tr -d '\r' | head -1 | sed 's/^category:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')

  # Get scope as comma-separated
  scope_list=$(tr -d '\r' < "$f" | sed -n '/^scope:/,/^[a-z]/{/^  - /s/^  - //p;}' | tr '\n' ',' | sed 's/,$//')

  # Get change warning (first 2 lines)
  warning=$(sed -n '/^## Change Warning$/,/^## /{/^## /d;/^$/d;p;}' "$f" | head -2 | tr '\n' ' ' | sed 's/[[:space:]]*$//')

  OUTPUT="${OUTPUT}${id}: ${title} [${category}]"
  [ -n "$scope_list" ] && OUTPUT="${OUTPUT}
  Scope: ${scope_list}"
  [ -n "$warning" ] && OUTPUT="${OUTPUT}
  Warning: ${warning}"
  OUTPUT="${OUTPUT}
"
  COUNT=$((COUNT + 1))
done

[ "$COUNT" -eq 0 ] && exit 0

printf 'DECISION GUARD — %d active decision(s) in this project:\n\n%s\nReview these before making changes. If your task contradicts any, ask the user before proceeding.\n' "$COUNT" "$OUTPUT"
exit 0
