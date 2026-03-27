#!/bin/bash
# Decision Guard — UserPromptSubmit Hook
# Fires before every user prompt reaches Claude. Checks if the prompt
# mentions keywords from active decisions. If yes, outputs relevant
# decision summaries as plain text — injected as context automatically.
#
# Input:  JSON on stdin with prompt field
# Output: Plain text to stdout (injected as context) or nothing
# Exit:   Always 0 (inform, never block)

INPUT=$(cat)

# Nothing to check
[ ! -d .decisions ] && exit 0

# Check if any active decisions exist
has_active=false
for f in .decisions/DEC-*.md; do
  [ -f "$f" ] || continue
  status=$(grep '^status:' "$f" | tr -d '\r' | head -1 | sed 's/^status:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')
  if [ "$status" = "active" ]; then
    has_active=true
    break
  fi
done
$has_active || exit 0

# Convert input to lowercase for case-insensitive matching
INPUT_LOWER=$(printf '%s' "$INPUT" | tr '[:upper:]' '[:lower:]')

# Also get recently changed files for scope matching
CHANGED_FILES=""
if [ -d .git ]; then
  CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null)
fi

# Check each active decision for keyword or scope matches
OUTPUT=""
MATCH_COUNT=0

for f in .decisions/DEC-*.md; do
  [ -f "$f" ] || continue

  status=$(grep '^status:' "$f" | tr -d '\r' | head -1 | sed 's/^status:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')
  [ "$status" = "active" ] || continue

  keyword_hits=0
  strong_keyword_hits=0
  scope_hit=false

  # Check keywords against the full input (which contains the prompt)
  # "Strong" keywords (>= 5 chars) are specific enough to match alone.
  # "Weak" keywords (< 5 chars: fix, add, bug, ui) need additional signals.
  in_keywords=false
  while IFS= read -r line; do
    case "$line" in
      keywords:*) in_keywords=true; continue ;;
    esac
    if $in_keywords; then
      case "$line" in
        "  - "*)
          kw="${line#  - }"
          kw="${kw#\"}"   # Strip leading YAML quote
          kw="${kw%\"}"   # Strip trailing YAML quote
          kw_lower=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
          # Word-boundary match: check if keyword appears as a word
          if printf '%s' "$INPUT_LOWER" | grep -qw "$kw_lower" 2>/dev/null; then
            keyword_hits=$((keyword_hits + 1))
            # Keywords >= 5 chars are domain-specific enough to stand alone
            if [ "${#kw_lower}" -ge 5 ]; then
              strong_keyword_hits=$((strong_keyword_hits + 1))
            fi
          fi
          ;;
        *) in_keywords=false ;;
      esac
    fi
  done < <(tr -d '\r' < "$f")

  # Check scope against changed files
  if [ -n "$CHANGED_FILES" ]; then
    in_scope=false
    while IFS= read -r line; do
      case "$line" in
        scope:*) in_scope=true; continue ;;
      esac
      if $in_scope; then
        case "$line" in
          "  - "*)
            scope_path="${line#  - }"
            if printf '%s' "$CHANGED_FILES" | grep -q "$scope_path" 2>/dev/null; then
              scope_hit=true
              break
            fi
            ;;
          *) in_scope=false ;;
        esac
      fi
    done < <(tr -d '\r' < "$f")
  fi

  # Decision is relevant if:
  #   1. 2+ keyword hits (any length), OR
  #   2. 1 keyword + scope hit, OR
  #   3. 1 strong keyword hit (>= 5 chars — domain-specific, not noise)
  # Scope alone is NOT enough (too noisy). Short keywords alone are NOT
  # enough (too generic). But "safety", "button", "design" alone ARE enough.
  relevant=false
  if [ "$keyword_hits" -ge 2 ]; then
    relevant=true
  elif [ "$keyword_hits" -ge 1 ] && $scope_hit; then
    relevant=true
  elif [ "$strong_keyword_hits" -ge 1 ]; then
    relevant=true
  fi

  if $relevant; then
    id=$(grep '^id:' "$f" | tr -d '\r' | head -1 | sed 's/^id:[[:space:]]*//')
    title=$(grep '^title:' "$f" | tr -d '\r' | head -1 | sed 's/^title:[[:space:]]*//' | sed 's/^"//;s/"$//')
    category=$(grep '^category:' "$f" | tr -d '\r' | head -1 | sed 's/^category:[[:space:]]*//' | sed 's/[[:space:]]*#.*//')
    date=$(grep '^date:' "$f" | tr -d '\r' | head -1 | sed 's/^date:[[:space:]]*//')

    # Get scope as comma-separated
    scope_list=$(tr -d '\r' < "$f" | sed -n '/^scope:/,/^[a-z]/{/^  - /s/^  - //p;}' | tr '\n' ',' | sed 's/,$//')

    # Get change warning (first 2 lines)
    warning=$(sed -n '/^## Change Warning$/,/^## /{/^## /d;/^$/d;p;}' "$f" | head -2 | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    OUTPUT="${OUTPUT}${id}: ${title} [${category}, ${date}]"
    [ -n "$scope_list" ] && OUTPUT="${OUTPUT}
  Scope: ${scope_list}"
    [ -n "$warning" ] && OUTPUT="${OUTPUT}
  Warning: ${warning}"
    OUTPUT="${OUTPUT}
"
    MATCH_COUNT=$((MATCH_COUNT + 1))
  fi
done

# Output as plain text (UserPromptSubmit injects plain stdout as context)
if [ "$MATCH_COUNT" -gt 0 ]; then
  printf 'DECISION GUARD — %d active decision(s) relevant to this task:\n\n%s\nIf your plan contradicts any of these, ask the user before proceeding.\n' "$MATCH_COUNT" "$OUTPUT"
fi

exit 0
