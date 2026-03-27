#!/bin/bash
# Decision Guard — PreToolUse Hook
# Fires before every Edit/Write. Checks if the target file is in any
# active decision's scope. If yes, injects decision context so Claude
# is aware before editing.
#
# Input:  JSON on stdin with tool_input.file_path
# Output: JSON with hookSpecificOutput.additionalContext (or nothing)
# Exit:   Always 0 (inform, never block)

INPUT=$(cat)

# Extract file_path — the only field we need
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

# Nothing to check
[ -z "$FILE_PATH" ] && exit 0
[ ! -d .decisions ] && exit 0

# Collect matching decision summaries
MATCHES=""
MATCH_COUNT=0

for f in .decisions/DEC-*.md; do
  [ -f "$f" ] || continue

  # Only active decisions
  status=$(grep '^status:' "$f" | tr -d '\r' | head -1 | sed 's/^status:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')
  [ "$status" = "active" ] || continue

  # Parse scope section, check if file_path matches any scope path
  matched=false
  in_scope=false
  while IFS= read -r line; do
    case "$line" in
      scope:*) in_scope=true; continue ;;
    esac
    if $in_scope; then
      case "$line" in
        "  - "*)
          scope_path="${line#  - }"
          # Match if the scope path appears anywhere in the file path
          case "$FILE_PATH" in
            *"$scope_path"*) matched=true; break ;;
          esac
          ;;
        *)
          # End of scope list (next YAML key or blank line)
          in_scope=false
          ;;
      esac
    fi
  done < <(tr -d '\r' < "$f")

  if $matched; then
    id=$(grep '^id:' "$f" | tr -d '\r' | head -1 | sed 's/^id:[[:space:]]*//')
    title=$(grep '^title:' "$f" | tr -d '\r' | head -1 | sed 's/^title:[[:space:]]*//' | sed 's/^"//;s/"$//')

    # Extract Change Warning (first 3 non-empty lines)
    warning=$(sed -n '/^## Change Warning$/,/^## /{/^## /d;/^$/d;p;}' "$f" | head -3 | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    MATCHES="${MATCHES}[${id}] ${title}."
    [ -n "$warning" ] && MATCHES="${MATCHES} Warning: ${warning}"
    MATCHES="${MATCHES} "
    MATCH_COUNT=$((MATCH_COUNT + 1))
  fi
done

# No matches → silent exit
[ "$MATCH_COUNT" -eq 0 ] && exit 0

# Escape for JSON: backslashes, double quotes, flatten to single line
ESCAPED=$(printf '%s' "$MATCHES" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"DECISION GUARD: This file is governed by %d active decision(s): %s— If your edit contradicts any of these, discuss with the user first."}}\n' "$MATCH_COUNT" "$ESCAPED"
exit 0
