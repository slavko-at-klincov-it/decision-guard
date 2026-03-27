---
name: review
description: "Review all tracked decisions, show dependency graph, and flag stale decisions. Use when the user asks to 'review decisions', 'list decisions', 'show all decisions', 'decision status', 'decision overview', or runs /decision-guard:review."
argument-hint: "[optional: filter — 'active', 'deprecated', 'architecture', etc.]"
allowed-tools: [Read, Glob, Grep, Bash]
version: 1.0.0
---

# Decision Guard — Review

## Filter

The user requested: $ARGUMENTS

## All Decisions (Frontmatter)

!`if [ -d .decisions ]; then found=0; for f in .decisions/DEC-*.md; do [ -f "$f" ] || continue; echo "=== $(basename "$f") ==="; sed -n '/^---$/,/^---$/p' "$f" | head -40; echo "=== END ==="; echo ""; found=$((found + 1)); done; [ "$found" -eq 0 ] && echo "NO_DECISIONS_FOUND"; else echo "NO_DECISIONS_DIR — run /decision-guard:init first"; fi`

## Git Activity (last 90 days)

!`git log --oneline --since="90 days ago" --name-only 2>/dev/null | head -150 || echo "no git history available"`

## Today's Date

!`date +%Y-%m-%d`

## Instructions

**If NO_DECISIONS_DIR:** Tell the user to run `/decision-guard:init` first. Stop.

**If NO_DECISIONS_FOUND:** Tell the user there are no decisions yet. Suggest `/decision-guard:log`. Stop.

### Step 1: Parse All Decisions

From the frontmatter above, extract for each decision:
- `id`, `title`, `status`, `date`, `category`, `scope`, `depends_on`, `enables`, `conflicts_with`, `supersedes`, `keywords`

If the user provided a filter in `$ARGUMENTS`, apply it:
- Status filter: "active", "deprecated", "superseded", "reverted" — show only matching status
- Category filter: "architecture", "implementation", "tooling", "convention", "security" — show only matching category
- If no filter, show everything

### Step 2: Summary Table

```
## Decision Guard Review

### Summary
- Total: N decisions
- Active: N | Superseded: N | Deprecated: N | Reverted: N
```

### Step 3: Decisions by Status

Show active decisions first (most important), then others.

Within each status group, sub-group by category.

For each decision, show a compact row:

```
### Active Decisions

#### Architecture (N)

| ID | Title | Date | Scope | Keywords |
|----|-------|------|-------|----------|
| DEC-2026-0326-001 | Safety consolidated | 2026-03-26 | gates.py, session.py | safety, gates |

#### Implementation (N)
...
```

If there are superseded or reverted decisions, show them in a collapsed section:

```
### Inactive Decisions

| ID | Title | Status | Date | Superseded By / Reason |
|----|-------|--------|------|----------------------|
```

### Step 4: Dependency Graph

Show relationships between decisions as a text tree. Only show decisions that have at least one relationship (depends_on, enables, conflicts_with, supersedes).

```
### Dependency Graph

DEC-001: Safety consolidated
  enables → DEC-002: Permission Model

DEC-002: Permission Model
  depends_on → DEC-001: Safety consolidated
```

**Flag problems:**
- Broken references: a `depends_on` or `enables` that points to an ID that does not exist → mark as `[BROKEN REF]`
- Circular dependencies: A depends on B which depends on A → mark as `[CIRCULAR]`
- Orphaned supersedes: a `supersedes` pointing to a decision that is still marked `active` (it should be `superseded`) → mark as `[STATUS MISMATCH]`

### Step 5: Staleness Warnings

Check each **active** decision for staleness:

1. **Age check:** Compare the decision's `date` to today's date. If older than 90 days, flag it:
   `[STALE?] DEC-xxx is N days old — consider reviewing if still current`

2. **Scope drift:** Check the git activity above. If files listed in a decision's `scope` have been modified in the git log but the decision has not been updated, flag it:
   `[SCOPE CHANGED] DEC-xxx governs {file} which was modified on {date} — verify decision still applies`

3. **Dependency health:** If a decision depends on another decision that is no longer `active`, flag it:
   `[DEPENDENCY INACTIVE] DEC-xxx depends on DEC-yyy which is now {status}`

```
### Staleness Warnings

- [STALE?] DEC-2026-0101-003: 85 days old. Consider reviewing.
- [SCOPE CHANGED] DEC-2026-0201-001: scope file `src/auth.ts` modified 12 days ago.
- [DEPENDENCY INACTIVE] DEC-2026-0315-002: depends on DEC-2026-0101-001 which is now `reverted`.
```

If no warnings, print: `No staleness warnings. All active decisions appear current.`

### Step 6: Recommendations

Based on the review, suggest actions if appropriate:
- Decisions that should be marked as superseded or deprecated
- Broken references that need fixing
- Stale decisions that need review
- Missing decisions (areas of recent heavy git activity with no decisions tracking them — mention this only if very obvious)
