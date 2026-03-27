#!/bin/bash
# Decision Guard — Stop Hook (Enhanced)
# Fires when Claude is about to end a session. Analyzes git state to
# determine if decision-worthy changes were made without logging.
#
# Behavior:
#   - If decision-worthy changes detected AND no new DEC logged → BLOCK (exit 2)
#   - If changes exist but aren't decision-worthy → gentle reminder (exit 0)
#   - Escape hatch: blocks once, allows through on second attempt
#
# Input:  JSON on stdin (not parsed — we only check project state)
# Output: stderr message (blocking) or JSON systemMessage (non-blocking)
# Exit:   0 = allow, 2 = block

# --- Guard clauses ---
[ ! -d .decisions ] && exit 0
ls .decisions/DEC-*.md >/dev/null 2>&1 || exit 0
[ ! -d .git ] && exit 0

# --- Escape hatch: allow through on second stop attempt ---
MARKER=".decisions/.stop_reminded"
if [ -f "$MARKER" ]; then
  # Check age — only honor recent markers (< 10 minutes)
  now=$(date +%s)
  if [ "$(uname)" = "Darwin" ]; then
    marker_time=$(stat -f %m "$MARKER" 2>/dev/null || echo 0)
  else
    marker_time=$(stat -c %Y "$MARKER" 2>/dev/null || echo 0)
  fi
  age=$(( now - marker_time ))
  if [ "$age" -lt 600 ]; then
    # Recent marker — allow through, clean up
    rm -f "$MARKER"
    printf '{"systemMessage":"Decision Guard: Acknowledged. If you made significant decisions, consider logging them next session."}\n'
    exit 0
  fi
  # Stale marker (>10 min) — remove and continue with normal check
  rm -f "$MARKER"
fi

# --- Gather git state ---
# Handle repos with no commits (fresh init)
if git rev-parse HEAD >/dev/null 2>&1; then
  changed_files=$(git diff --name-only HEAD 2>/dev/null)
  staged_files=$(git diff --cached --name-only 2>/dev/null)
  deleted_files=$(git diff --name-only --diff-filter=D HEAD 2>/dev/null)
else
  changed_files=""
  staged_files=$(git diff --cached --name-only 2>/dev/null)
  deleted_files=""
fi
untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.decisions/')

all_changes=$(printf '%s\n%s\n%s' "$changed_files" "$staged_files" "$untracked_files" | sort -u | grep -v '^$')

# No changes at all → nothing to check
[ -z "$all_changes" ] && exit 0

# --- Check if a new DEC was logged this session ---
# Untracked DEC files (just created, not yet staged)
new_dec_untracked=$(git ls-files --others --exclude-standard .decisions/ 2>/dev/null | grep 'DEC-.*\.md$' | head -1)

# Staged DEC files (added but not committed)
new_dec_staged=$(git diff --cached --name-only 2>/dev/null | grep '\.decisions/DEC-.*\.md$' | head -1)

# Recently committed DEC files (committed during this session)
new_dec_committed=$(git log --since="4 hours ago" --diff-filter=A --name-only --pretty=format: -- '.decisions/DEC-*.md' 2>/dev/null | grep -v '^$' | head -1)

if [ -n "$new_dec_untracked" ] || [ -n "$new_dec_staged" ] || [ -n "$new_dec_committed" ]; then
  # Decision was logged this session — all good
  exit 0
fi

# --- Decision-worthy heuristics ---
decision_worthy=false
evidence=""

# 1. New files created (untracked, not in .decisions/)
if [ -n "$untracked_files" ]; then
  new_count=$(printf '%s\n' "$untracked_files" | wc -l | tr -d ' ')
  new_sample=$(printf '%s\n' "$untracked_files" | head -3 | tr '\n' ', ' | sed 's/,$//')
  if [ "$new_count" -gt 0 ]; then
    decision_worthy=true
    evidence="${evidence}\n- ${new_count} new file(s) created (${new_sample})"
  fi
fi

# 2. Files deleted
if [ -n "$deleted_files" ]; then
  del_count=$(printf '%s\n' "$deleted_files" | wc -l | tr -d ' ')
  del_sample=$(printf '%s\n' "$deleted_files" | head -3 | tr '\n' ', ' | sed 's/,$//')
  decision_worthy=true
  evidence="${evidence}\n- ${del_count} file(s) deleted (${del_sample})"
fi

# 3. Config files changed
CONFIG_PATTERN='package\.json$|tsconfig|Dockerfile|docker-compose|\.ya?ml$|CLAUDE\.md$|Makefile$|Cargo\.toml$|pyproject\.toml$|go\.mod$|go\.sum$|\.gemspec$|Gemfile$|requirements\.txt$|setup\.py$|setup\.cfg$|\.eslintrc|\.prettierrc|\.babelrc|webpack\.config|vite\.config|next\.config|\.env\.example$|\.cursorrules$'

config_matches=$(printf '%s\n' "$all_changes" | grep -E "$CONFIG_PATTERN" | head -5)
if [ -n "$config_matches" ]; then
  config_list=$(printf '%s\n' "$config_matches" | tr '\n' ', ' | sed 's/,$//')
  decision_worthy=true
  evidence="${evidence}\n- Config file(s) modified (${config_list})"
fi

# 4. Many files changed (>5 = likely refactor)
change_count=$(printf '%s\n' "$all_changes" | wc -l | tr -d ' ')
if [ "$change_count" -gt 5 ]; then
  decision_worthy=true
  evidence="${evidence}\n- ${change_count} files changed total"
fi

# --- Act on results ---
if $decision_worthy; then
  # BLOCK: Create escape hatch marker and exit 2
  touch "$MARKER"
  printf 'Decision Guard — Session blocked: significant changes detected without a logged decision.\n\nDetected:%b\n\n→ Run /decision-guard:log to record your decisions.\n→ Or end the session again to bypass this check.\n' "$evidence" >&2
  exit 2
else
  # Non-decision-worthy changes — gentle non-blocking reminder
  printf '{"systemMessage":"Decision Guard: If significant choices were made in this session (design changes, architecture decisions, deliberate removals), log them with /decision-guard:log before ending."}\n'
  exit 0
fi
