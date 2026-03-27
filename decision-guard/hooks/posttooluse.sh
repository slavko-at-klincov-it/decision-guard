#!/bin/bash
# Decision Guard — PostToolUse Hook
# Fires after every Write/Edit. Checks if the change is "obviously
# significant" (new file created, config file modified). If yes,
# outputs a brief nudge reminding Claude to consider logging.
#
# Designed to be highly selective — most edits produce no output.
# A 15-minute cooldown between nudges prevents spam.
#
# Input:  JSON on stdin with tool_name and tool_input.file_path
# Output: JSON with systemMessage (or nothing)
# Exit:   Always 0 (nudge, never block)

INPUT=$(cat)

# --- Guard clauses ---
[ ! -d .decisions ] && exit 0
# Must have at least one active decision (journal is in use)
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

# --- Parse input ---
FILE_PATH=$(printf '%s' "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
TOOL_NAME=$(printf '%s' "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//')

[ -z "$FILE_PATH" ] && exit 0

# Skip changes to .decisions/ itself (that's us)
case "$FILE_PATH" in
  *.decisions/*|.decisions/*) exit 0 ;;
esac

# --- Check if change is "obviously significant" ---
significant=false
action=""

# 1. Config file modified
CONFIG_PATTERN='package\.json$|tsconfig|Dockerfile|docker-compose|\.ya?ml$|CLAUDE\.md$|Makefile$|Cargo\.toml$|pyproject\.toml$|go\.mod$|go\.sum$|\.gemspec$|Gemfile$|requirements\.txt$|setup\.py$|setup\.cfg$|\.eslintrc|\.prettierrc|\.babelrc|webpack\.config|vite\.config|next\.config|\.env\.example$|\.cursorrules$'

if printf '%s' "$FILE_PATH" | grep -qE "$CONFIG_PATTERN"; then
  significant=true
  action="modified config file"
fi

# 2. New file created (Write to a path not tracked by git)
if [ "$TOOL_NAME" = "Write" ] && [ -d .git ]; then
  if ! git ls-files --error-unmatch "$FILE_PATH" >/dev/null 2>&1; then
    significant=true
    action="created new file"
  fi
fi

$significant || exit 0

# --- Cooldown: max one nudge per 15 minutes ---
COOLDOWN_FILE=".decisions/.last_nudge"
if [ -f "$COOLDOWN_FILE" ]; then
  now=$(date +%s)
  if [ "$(uname)" = "Darwin" ]; then
    last_nudge=$(stat -f %m "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  else
    last_nudge=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  fi
  elapsed=$(( now - last_nudge ))
  [ "$elapsed" -lt 900 ] && exit 0
fi

# --- Output nudge ---
filename=$(basename "$FILE_PATH")
touch "$COOLDOWN_FILE"
printf '{"systemMessage":"Decision Guard: You just %s (%s). If this reflects a deliberate choice (not a routine fix), consider logging with /decision-guard:log when done."}\n' "$action" "$filename"
exit 0
