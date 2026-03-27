# decision-guard

**A decision journal for Claude Code — written by Claude, read by Claude.**

Prevents AI coding loops where Claude accidentally undoes deliberate changes because it has no memory between sessions.

---

## The Problem

Claude Code has no memory. Every session starts from zero. This causes loops:

**Session A:** You tell Claude "change everything to blue." Claude does it.

**Session B (next day):** You say "make the button like yesterday." Yesterday the button was red and round. Claude makes it red and round — silently undoing the blue design decision from Session A.

**Session C:** You say "why is this button red? Everything should be blue." Claude changes it to blue. The loop continues.

The root cause: Claude doesn't know *why* things are the way they are. It sees state, not intent. decision-guard gives Claude a journal to remember.

> For the full research — academic sources, market analysis, why no tool solves this — see [RESEARCH.md](../RESEARCH.md).

---

## How It Works

**Claude writes the journal. Claude reads the journal.** The user doesn't need to do anything extra.

1. **After significant changes** — Claude logs what it decided and why, as a note to its future self
2. **Before every prompt** — Hooks automatically inject relevant journal entries into Claude's context
3. **Before every file edit** — Hooks warn Claude if the file is governed by a past decision
4. **When planning** — Claude reads the journal and flags conflicts before executing

### Skills

| Skill | Purpose |
|-------|---------|
| `/decision-guard:init` | Initialize the journal in a project |
| `/decision-guard:log` | Claude logs a decision (fills in everything itself) |
| `/decision-guard:check` | Deep conflict analysis against all active decisions |
| `/decision-guard:review` | Overview of all decisions, dependencies, staleness |

### Hooks (automatic, no user action needed)

| Hook | Trigger | What it does |
|------|---------|-------------|
| SessionStart | Session start + compaction | Injects all active decisions (cold-start protection) |
| PreToolUse | Every Edit/Write | Warns Claude if the file is governed by a decision |
| PostToolUse | After Write/Edit | Nudges Claude when config files or new files are created |
| UserPromptSubmit | Every prompt | Injects relevant decisions as context before Claude thinks |
| Stop | Every response | **Blocks** if decision-worthy changes detected without logging |

#### How the Stop Hook enforces logging

The Stop hook analyzes git state when Claude tries to end a session. If it detects **decision-worthy changes** (new files created, files deleted, config files modified, or >5 files changed) and **no new decision was logged**, it blocks the session with a specific message telling Claude what was detected.

Claude can either log the decision with `/decision-guard:log` or end the session a second time to bypass the check. This prevents infinite blocking while ensuring Claude is confronted with the choice at least once.

---

## Installation

```bash
# From Claude Code
/plugin install decision-guard

# For development/testing
claude --plugin-dir ./decision-guard
```

---

## Quick Start

### 1. Initialize

```
/decision-guard:init
```

Creates `.decisions/` journal directory and adds a **Decision Journal** rule to `CLAUDE.md` that instructs Claude to read and write the journal as part of its workflow.

### 2. Work normally

Just talk to Claude as you always do:

> "Change the complete design to blue. Everything should be a unified blue palette."

Claude makes the changes. Then, because the CLAUDE.md rule says so, Claude automatically runs `/decision-guard:log` and writes:

```
Decision logged: DEC-2026-0326-001 — Design changed to unified blue palette
```

No questions asked. Claude fills in the scope (which files it changed), the keywords (design, color, blue, theme, button), and most importantly the **Change Warning** — a note to its future self:

> *"If someone says 'fix the colors' or 'make it like before' — do NOT revert to the old color scheme. The blue was a deliberate choice. Ask if they mean the shape/layout or the actual color."*

### 3. Next session — the journal prevents the loop

Next day, you say:

> "Make the button like it was yesterday"

The **UserPromptSubmit hook** fires. "Button" matches keywords from DEC-001. Claude sees:

```
DECISION GUARD — 1 active decision(s) relevant to this task:
DEC-2026-0326-001: Design changed to unified blue palette [design]
  Warning: Do NOT revert to old color scheme. Ask first.
```

Claude now knows: yesterday the button was red and round. But blue was deliberate. So instead of blindly reverting, Claude asks:

> "I see we changed the design to blue as a deliberate choice. The button yesterday was red and round. Should I make it the **old round shape** but keep the **current blue**?"

The loop is prevented.

---

## Decision Format

Each journal entry is a Markdown file with YAML frontmatter:

```yaml
---
id: DEC-2026-0326-001
title: "Design changed to unified blue palette"
status: active          # active | superseded | reverted | deprecated
date: 2026-03-26
category: design        # design | architecture | implementation | tooling | convention | security
scope:
  - src/styles/variables.css
  - src/components/Button.tsx
depends_on: []
enables: []
conflicts_with: []
supersedes: []
keywords:
  - design
  - color
  - blue
  - theme
  - button
---

## Decision
Complete color scheme changed to unified blue palette.

## Rationale
User requested: "Change the complete design to blue."

## Alternatives Considered
None — direct implementation of user request.

## Consequences
All UI components use the blue palette from variables.css.

## Change Warning
If someone says "fix the colors" or "make it like before" — do NOT
revert to old colors. The blue was deliberate. Ask if they mean
shape/layout or actual color.
```

---

## How Conflict Detection Works

The `/decision-guard:check` skill uses **three-level matching**:

| Level | Signal | What It Checks |
|-------|--------|----------------|
| **Scope** | File paths | Do the task's files overlap with a decision's `scope`? |
| **Keyword** | Term matching | Do the task's words match a decision's `keywords`? |
| **Semantic** | Intent analysis | Does the task contradict what a decision states? |

Severity requires multiple signals:

| Severity | Condition |
|----------|-----------|
| **CONFLICT** | Scope + Keyword or Semantic — direct contradiction |
| **CAUTION** | Scope alone, or Keyword + Semantic — needs awareness |
| **INFO** | Single keyword match — loose association |
| **CLEAR** | No matches |

A single keyword match alone never triggers CONFLICT or CAUTION. Precision over noise.

---

## Decision Lifecycle

```
         ┌──────────┐
         │  ACTIVE   │
         └─────┬─────┘
               │
    ┌──────────┼──────────┐
    v          v          v
┌──────────┐ ┌────────┐ ┌──────────┐
│SUPERSEDED│ │REVERTED│ │DEPRECATED│
└──────────┘ └────────┘ └──────────┘
 Replaced by   Consciously  Outdated,
 a newer       undone       not yet
 decision                   replaced
```

---

## Requirements

- **Claude Code** (CLI, desktop app, or IDE extension)
- No Python, no Node, no database, no external dependencies
- Works on macOS, Linux, and Windows (WSL)
- Works with or without Git

---

## Why This Matters

No AI coding assistant has a decision journal:

| Tool | Memory | Knows WHY code is the way it is |
|------|--------|---------------------------------|
| Claude Code | CLAUDE.md + Memory | No |
| Cursor | .cursor/rules | No |
| Copilot | Repo context | No |
| Aider | LanceDB memory | No |

**decision-guard** is the first tool that gives an AI coding assistant the ability to say: *"I see that was done on purpose. Let me ask before I undo it."*

---

## License

MIT
