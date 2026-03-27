# decision-guard

**A decision journal for Claude Code — written by Claude, read by Claude.**

Prevents AI coding loops where Claude accidentally undoes deliberate changes because it has no memory between sessions.

## The Problem

Claude Code has no memory. Every session starts from zero. This causes loops:

**Session A:** You tell Claude "change everything to blue." Claude does it.

**Session B (next day):** You say "make the button like yesterday." Yesterday the button was red and round. Claude makes it red and round — silently undoing the blue design decision from Session A.

**Session C:** You say "why is this button red? Everything should be blue." The loop continues.

The root cause: Claude doesn't know *why* things are the way they are. It sees state, not intent. decision-guard gives Claude a journal to remember.

## How It Works

**Claude writes the journal. Claude reads the journal.** You don't need to do anything extra.

1. **After significant changes** — Claude logs what it decided and why, as a note to its future self
2. **Before every prompt** — Hooks inject relevant journal entries into Claude's context
3. **Before every file edit** — Hooks warn Claude if the file is governed by a past decision
4. **At session start** — All active decisions are injected so Claude has full context from the first prompt
5. **At session end** — If decision-worthy changes were made without logging, Claude is blocked until it logs or acknowledges

### Example

You say: *"Make the button like it was yesterday"*

Without decision-guard, Claude reverts to the old red button. With decision-guard, Claude sees:

```
DECISION GUARD — 1 active decision(s) relevant to this task:
DEC-2026-0326-001: Design changed to unified blue palette [design]
  Warning: Do NOT revert to old color scheme. Ask first.
```

Claude asks: *"The button was red yesterday, but we deliberately changed to blue. Should I make it the old round shape but keep the current blue?"*

## Quick Start

```bash
# Install the plugin
claude --plugin-dir ./decision-guard

# Initialize in your project
/decision-guard:init

# Work normally — Claude logs decisions automatically
```

### Skills

| Skill | Purpose |
|-------|---------|
| `/decision-guard:init` | Initialize the journal in a project |
| `/decision-guard:log` | Claude logs a decision (fills in everything itself) |
| `/decision-guard:check` | Deep conflict analysis against all active decisions |
| `/decision-guard:review` | Overview of all decisions, dependencies, staleness |

### Hooks (automatic)

| Hook | When | What |
|------|------|------|
| SessionStart | Session start + compaction | Injects all active decisions (cold-start protection) |
| UserPromptSubmit | Every prompt | Injects keyword-matched decisions as context |
| PreToolUse | Before Edit/Write | Warns if file is governed by a decision |
| PostToolUse | After Write/Edit | Nudges on config changes or new files |
| Stop | Every response | Blocks if decision-worthy changes without logging |

## Architecture

- **4 skills + 5 hooks**, zero external dependencies
- Pure Markdown + YAML frontmatter + Shell
- Git-aware (scope matching, change detection, session heuristics)
- Works on macOS, Linux, and Windows (WSL)
- CRLF-safe parsing

Decisions are stored as `.decisions/DEC-*.md` files — human-readable, git-versioned, grep-parseable.

For the full technical architecture, see [ARCHITECTURE.md](decision-guard/ARCHITECTURE.md).

For the academic research and market analysis behind this, see [RESEARCH.md](RESEARCH.md).

## Why This Matters

No AI coding assistant has a decision journal:

| Tool | Memory | Knows WHY code is the way it is |
|------|--------|---------------------------------|
| Claude Code | CLAUDE.md + Memory | No |
| Cursor | .cursor/rules | No |
| Copilot | Repo context | No |
| Aider | LanceDB memory | No |

**decision-guard** is the first tool that gives an AI coding assistant the ability to say: *"I see that was done on purpose. Let me ask before I undo it."*

## License

MIT
