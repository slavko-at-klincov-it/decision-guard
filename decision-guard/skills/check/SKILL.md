---
name: check
description: "Check if a task conflicts with active decisions. Use when the user asks to 'check decisions', 'check for conflicts', 'are there decision conflicts', 'decision-guard check', or before starting significant implementation work."
argument-hint: "<description of what you plan to do>"
allowed-tools: [Read, Glob, Grep, Bash]
version: 1.0.0
---

# Decision Guard — Conflict Check

## Task to Check

The user wants to: **$ARGUMENTS**

## Active Decisions

!`if [ -d .decisions ]; then found=0; for f in .decisions/DEC-*.md; do [ -f "$f" ] || continue; status=$(grep '^status:' "$f" | head -1 | sed 's/^status:[[:space:]]*//' | sed 's/[[:space:]]*#.*//'); if [ "$status" = "active" ]; then echo "=== $(basename "$f") ==="; cat "$f"; echo ""; echo "=== END ==="; echo ""; found=$((found + 1)); fi; done; [ "$found" -eq 0 ] && echo "NO_ACTIVE_DECISIONS"; else echo "NO_DECISIONS_DIR"; fi`

## Git Context

- Current branch: !`git branch --show-current 2>/dev/null || echo "not a git repo"`
- Uncommitted changes: !`git diff --name-only 2>/dev/null | head -30 || echo "none"`
- Staged files: !`git diff --cached --name-only 2>/dev/null | head -30 || echo "none"`
- Recent file changes: !`git diff --name-only HEAD~5 2>/dev/null | head -30 || echo "none"`

## Instructions

You are checking your own journal. Your past self logged these decisions for a reason. Your job is to check whether what you're about to do conflicts with what was deliberately decided before.

**If NO_DECISIONS_DIR:** Tell the user decision tracking is not initialized. Suggest `/decision-guard:init`. Stop.

**If NO_ACTIVE_DECISIONS:** Tell the user there are no active decisions to check against. They can proceed freely. Stop.

### Step 1: Parse Each Active Decision

For each decision above, extract:
- `id`, `title`, `status`, `scope` (file paths), `keywords`, `depends_on`, `enables`
- The `## Decision`, `## Consequences`, and `## Change Warning` sections

### Step 2: Three-Level Matching

For each active decision, check these three signals against the user's task description AND the git context (changed/staged files):

**Level 1 — Scope Match (file paths):**
Compare the decision's `scope` paths against:
- Files explicitly mentioned in the task description
- Files in the git diff (uncommitted + staged + recent changes)
- Use partial path matching — if a decision's scope includes `src/auth/` and a changed file is `src/auth/login.ts`, that is a match

**Level 2 — Keyword Match:**
Compare the decision's `keywords` against words in the task description.
- Case-insensitive matching
- Match whole words, not substrings (e.g., keyword "gate" should NOT match "investigate")
- A single common keyword match (like "update", "fix", "add") is NOT significant

**Level 3 — Semantic Match:**
Read the decision's content — especially `## Decision`, `## Consequences`, and `## Change Warning`.
- Does the user's task intent contradict what was decided?
- Would the task revert, undo, or undermine the decision?
- Would the task create something the decision explicitly removed or rejected?

### Step 2b: Dependency Chain Analysis

If any decision is classified as CONFLICT or CAUTION in Step 2, check its dependency chain:

1. Read its `depends_on`, `enables`, and `conflicts_with` fields
2. For each referenced decision ID, find the corresponding active decision and apply Step 2 to it as well
3. **Follow chains transitively:** If DEC-001 depends_on DEC-002, and DEC-002 depends_on DEC-003, check all three. A change to a foundation decision affects everything built on it.
4. **Escalation rule:** If a "foundation" decision (one that other decisions `depends_on`) is flagged as CONFLICT, then all decisions that depend on it are at least CAUTION — even if they wouldn't match on their own.
5. **conflicts_with:** If any flagged decision lists `conflicts_with` pointing to another active decision, note this explicitly — the user may need to resolve the conflict between the decisions themselves.

### Step 3: Classify Severity

Apply these rules strictly:

| Severity | Condition | Meaning |
|----------|-----------|---------|
| **CONFLICT** | Scope match + (Keyword OR Semantic match) | Task directly contradicts a decision |
| **CAUTION** | Scope match alone, OR Keyword + Semantic match | Task touches governed area, needs awareness |
| **INFO** | Single keyword match only | Loose association, no action needed |
| **CLEAR** | No matches on any level | No relationship found |

**Precision rules — follow these strictly:**
- A single keyword match alone is NEVER a CONFLICT or CAUTION — it is INFO at most
- Scope matches on very common files (package.json, README.md, .gitignore, tsconfig.json) are weighted lower — they alone should only produce INFO unless combined with strong keyword or semantic match
- When uncertain between CONFLICT and CAUTION, choose CAUTION
- When uncertain between CAUTION and INFO, choose INFO
- You MUST cite specific evidence for every warning — which files matched, which keywords matched, what semantic reasoning you applied

### Step 4: Output

Format your response as:

```
## Decision Guard Check

### Task: {user's task description}

### Result: {CLEAR | N conflicts found}
```

**If CLEAR:**
```
No active decisions conflict with this task. Proceed freely.
```

**If conflicts found, for each decision (ordered by severity: CONFLICT first, then CAUTION, then INFO):**

```
### [{SEVERITY}] {decision ID}: {decision title}

**Match evidence:**
- Scope: {which paths matched, or "no scope overlap"}
- Keywords: {which keywords matched, or "no keyword match"}
- Semantic: {brief reasoning, or "no semantic conflict"}

**What this decision says:**
{1-2 sentence summary of the decision}

**Recommendation:**
{What the user should do — e.g., "Read this decision before proceeding", "STOP — discuss with team", "Be aware, but likely compatible"}
```

**Final line:**
- If any CONFLICT: `Recommendation: Resolve conflicts before proceeding. Read the flagged decisions and discuss changes with the user.`
- If only CAUTION/INFO: `Recommendation: Review the flagged decisions, then proceed with awareness.`
- If CLEAR: `All clear. No active decisions are affected by this task.`
