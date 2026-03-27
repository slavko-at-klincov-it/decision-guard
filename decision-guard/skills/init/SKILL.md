---
name: init
description: "Initialize decision tracking in the current project. Use when the user asks to 'set up decision-guard', 'initialize decision tracking', 'create .decisions folder', 'start tracking decisions', or runs /decision-guard:init."
argument-hint: (no arguments needed)
allowed-tools: [Read, Write, Edit, Bash, Glob]
version: 1.0.0
---

# Initialize Decision Guard

## Current Project State

- Decision directory: !`test -d .decisions && echo "EXISTS — .decisions/ already present" || echo "MISSING — will create .decisions/"`
- CLAUDE.md: !`test -f CLAUDE.md && echo "EXISTS — will append Decision Awareness rule" || echo "MISSING — will create with Decision Awareness rule"`
- Git repo: !`test -d .git && echo "YES — git repository detected" || echo "NO — not a git repo (that's fine)"`

## Instructions

Based on the project state above, perform these steps:

### Step 1: Create `.decisions/` directory

If the directory already EXISTS, inform the user and ask if they want to re-initialize (recreate template, update CLAUDE.md rule). If they decline, stop.

If MISSING, create the `.decisions/` directory.

### Step 2: Create the decision template

Write the following file to `.decisions/_template.md`:

```markdown
---
id: DEC-YYYY-MMDD-NNN
title: "Title of the decision"
status: active          # active | superseded | reverted | deprecated
date: YYYY-MM-DD
category: architecture  # design | architecture | implementation | tooling | convention | security
scope:                  # Files/paths this decision governs
  - path/to/file
depends_on: []          # Decision IDs this depends on
enables: []             # Decision IDs this makes possible
conflicts_with: []      # Decision IDs that contradict this
supersedes: []          # Decision IDs this replaces
keywords:               # Terms that should trigger a check
  - keyword1
  - keyword2
---

## Decision

What was decided. State it clearly and concretely.

## Rationale

Why it was decided. What problem did it solve? What constraints drove this choice?

## Alternatives Considered

What was rejected and why.

- **Alternative A:** Description. Rejected because...
- **Alternative B:** Description. Rejected because...

## Consequences

What this means going forward. What changed, what is now true.

## Change Warning

If someone wants to modify or revert this decision:
- What should be asked before proceeding?
- What would break if this were reverted?
- Who or what depends on this?
```

### Step 3: Add Decision Journal rule to CLAUDE.md

If CLAUDE.md exists, check whether it already contains a "## Decision Journal" section (or the older "## Decision Awareness" section). If it does, skip this step and inform the user. If it does not, append the following block at the end of the file (with a blank line before it):

If CLAUDE.md does not exist, create it with this content:

```markdown
## Decision Journal

`.decisions/` is your journal. You write it, you read it. It prevents you from going in circles.

### WHY this exists:
You have no memory between sessions. Without this journal, you will accidentally undo deliberate changes — recreating deleted files, reverting design choices, breaking things that were fixed on purpose. This journal is how you remember WHY things are the way they are.

### WHEN PLANNING — read the journal first:
1. Before you make a plan, read the decisions the hooks inject into your context
2. If your plan would change, undo, or contradict something in the journal — STOP
3. Tell the user: "I see we decided X because of Y. My plan would change Y. Should I proceed?"
4. Example: The journal says "design changed to blue because user wanted unified color scheme." The user now says "make the button like yesterday." Yesterday the button was red. Your plan should NOT make it red — it should make it the OLD SHAPE in the CURRENT blue. If unclear, ask.
5. Never silently undo a journal entry. Always flag the conflict.

### AFTER COMPLETING A TASK — write to the journal:
When you just made a change that involves a CHOICE (not a fix, not a tweak — a choice), log it by running `/decision-guard:log`. Fill in everything yourself:
- The user's prompt is the rationale — quote it
- The files you changed are the scope
- The keywords are what a future you would search for
- The Change Warning is the most important part: write instructions to your future self about what NOT to do and what to ask before changing

### What to log:
- Design direction changes ("everything blue", "cards not tables")
- Architecture choices (consolidating, splitting, removing files)
- Tool/library choices ("use Tailwind", "switch to Postgres")
- Deliberate removals or rejections ("deleted X because Y", "chose A over B")

### What NOT to log:
- Bug fixes, typo fixes, minor tweaks
- Adding content that follows an existing decision
- Routine work that doesn't involve a choice
```

### Step 4: Confirm

Print a short summary of what was created:

```
Decision Guard initialized:
  .decisions/             — decision log directory
  .decisions/_template.md — decision format template
  CLAUDE.md               — Decision Journal rule added

Decisions will be logged automatically when you make significant changes.
```

If this is a git repository, mention that `.decisions/` should be committed to version control so decisions are shared with the team.
