---
name: log
description: "Log a decision. Called by Claude automatically after significant changes, or manually by user. Use when you just made a design choice, architecture change, or deliberate removal that a future session needs to know about."
argument-hint: "[optional: brief description of what was decided]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
version: 1.0.0
---

# Log a Decision

## Current State

- Decisions directory: !`test -d .decisions && echo "READY" || echo "NOT_INITIALIZED — run /decision-guard:init first"`
- Today's date: !`date +%Y-%m-%d`
- ID components: !`echo "YEAR=$(date +%Y) MMDD=$(date +%m%d) COUNT=$(ls .decisions/DEC-$(date +%Y)-$(date +%m%d)-*.md 2>/dev/null | wc -l | tr -d ' ')"`
- Recently changed files: !`git diff --name-only HEAD~5 2>/dev/null | head -20 || echo "no git history"`
- Existing decisions: !`ls .decisions/DEC-*.md 2>/dev/null | sed 's|.decisions/||' || echo "none yet"`

## Instructions

If the decisions directory is NOT_INITIALIZED, tell the user to run `/decision-guard:init` first and stop.

Context: $ARGUMENTS

### ID Generation

Using the ID components above:
- Take COUNT, add 1, zero-pad to 3 digits → that is NNN
- The new ID is: `DEC-{YEAR}-{MMDD}-{NNN}`

### How to Log

**Default: You fill in everything yourself.** You just made changes — you know what was decided, why, and which files were affected. Do NOT interview the user with questions. Just write the decision file.

Use the conversation context (what the user asked, what you did, which files you changed) to fill in all fields:

- **title**: Short summary of the decision (what changed and why in <10 words)
- **category**: Pick one — `design` (visual/UX), `architecture` (structure), `implementation` (how it's built), `tooling` (tools/libs), `convention` (naming/style rules), `security`
- **scope**: The files you just changed or that are affected by this decision
- **keywords**: 3-6 words that someone would use when working in this area in a future session. Think: what prompt would trigger a conflict with this decision?
- **Decision section**: 1-2 sentences. What is now true.
- **Rationale section**: The user's original request — quote or paraphrase their prompt. This IS the "why".
- **Alternatives Considered**: Only if you actually considered and rejected alternatives during this session. Otherwise write "None — direct implementation of user request."
- **Consequences**: What this means going forward. What files/areas are affected.
- **Change Warning**: The most important section. Write this as a note to your future self — a future Claude session that has no memory of this conversation. What should that future you know? What would it be tempted to do that would be wrong? What should it ask the user before changing? Be specific and direct, e.g.: "If someone says 'fix the colors' do NOT revert to the old red scheme — the blue was a deliberate choice. Ask first."

**Exception: If the user runs `/decision-guard:log` manually without prior context** (cold start, no recent changes), THEN ask brief questions: "What did you just decide? Which files?" — but keep it minimal, 2-3 questions max.

### Generate the Decision File

Create: `.decisions/DEC-{YEAR}-{MMDD}-{NNN}-{slug}.md`

**Slug**: title → lowercase → spaces/special chars to hyphens → truncate 50 chars.

```markdown
---
id: {generated ID}
title: "{short title}"
status: active
date: {today's date}
category: {category}
scope:
  - {each affected file}
depends_on: [{existing DEC IDs if related}]
enables: []
conflicts_with: []
supersedes: [{existing DEC IDs if this replaces them}]
keywords:
  - {keyword}
---

## Decision

{What is now true. 1-2 sentences.}

## Rationale

{Why — paraphrase the user's request/prompt that led to this.}

## Alternatives Considered

{Only if relevant. Otherwise: "None — direct implementation of user request."}

## Consequences

{What this means for future work. Which files/areas are now governed by this decision.}

## Change Warning

{Instructions to a future Claude session. Be specific:
- "If someone asks to [X], do [Y] instead"
- "This file was deliberately [removed/changed/structured this way] because [reason]"
- "Check with the user before [specific action]"}
```

### After Writing

Print a brief confirmation:
```
Decision logged: {ID} — {title}
```

Do not suggest next steps or additional commands. Keep it brief.
