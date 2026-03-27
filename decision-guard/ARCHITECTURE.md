# decision-guard — Architecture Document

## What Was Built

A Claude Code plugin — **Claude's decision journal.** Claude writes it after significant changes, Claude reads it before planning. 4 skills + 3 hooks, zero external dependencies, pure Markdown + Shell.

```
decision-guard/
├── .claude-plugin/plugin.json        # Plugin manifest
├── skills/
│   ├── init/SKILL.md                 # /decision-guard:init
│   ├── log/SKILL.md                  # /decision-guard:log
│   ├── check/SKILL.md                # /decision-guard:check
│   └── review/SKILL.md               # /decision-guard:review
├── hooks/
│   ├── hooks.json                    # Hook manifest
│   ├── session-start.sh              # Full decision injection at session start
│   ├── pretooluse.sh                 # Auto-warn before every Edit/Write
│   ├── posttooluse.sh               # Nudge after significant Write/Edit
│   ├── prompt-check.sh              # Decision context injection per prompt
│   └── stop-reminder.sh             # Smart blocking at session end
├── README.md                         # User-facing documentation
└── ARCHITECTURE.md                   # This file
```

---

## Core Concept

**This is Claude's journal, not a user tool.** The user just works normally — tells Claude what to do. Claude:
1. **Reads** the journal automatically before every task (via hooks)
2. **Writes** to the journal after making significant choices (via CLAUDE.md rule)
3. **Flags conflicts** when a new task would contradict a past decision
4. **Asks the user** only when there's a real conflict — not for routine logging

The user never has to run commands, answer questions, or manage decisions. They just see Claude being smarter about not undoing its own past work.

---

## How Each Skill Works

### init — Project Setup

**What it does:** Creates `.decisions/` directory, a template, and the **Decision Journal** rule in CLAUDE.md.

**The CLAUDE.md rule is the most critical piece.** It tells Claude:
- Before planning: read the journal, flag conflicts, ask before contradicting
- After significant changes: log the decision yourself — the user's prompt is the rationale
- The Change Warning is a note to your future self

The rule is written as instructions to Claude, not to the user. Example: *"If your plan would change, undo, or contradict something in the journal — STOP. Tell the user."*

### log — Decision Capture

**What it does:** Creates a decision file. Claude fills in everything itself.

**How:** Shell commands pre-compute the next ID, today's date, recently changed files, and existing decisions. Claude uses the conversation context (what the user asked, what it just did) to fill in all fields without asking the user.

**Key design choice: Claude writes, not the user.** The old approach asked users structured questions (4 groups, wait for answers). This failed for vibe coders — too much friction. The new approach: Claude has all the context (the prompt IS the rationale, the changed files ARE the scope), so it writes the entry itself. Only exception: if `/decision-guard:log` is called cold (no prior context), Claude asks 2-3 brief questions.

**The Change Warning section** is the most important field. It's written as a note to a future Claude session: *"If someone says X, do NOT do Y. Instead, ask Z."* This is what actually prevents loops.

### check — Conflict Detection (Core Skill)

**What it does:** Deep conflict analysis. Reads all active decisions, compares against a planned task.

**How:** A single shell command injects the **full content** of every active decision before Claude reasons. Claude then performs three-level matching:
1. **Scope match** — file paths in decision vs. files in task/git diff
2. **Keyword match** — YAML keywords vs. task words
3. **Semantic match** — Claude reads decision content and reasons about intent conflict

Severity requires multiple signals — a single keyword match alone is never CONFLICT or CAUTION. This prevents false positives.

**When is it used?** Mostly automatically via hooks. The explicit `/decision-guard:check` is for deep analysis when Claude or the user wants a thorough review before a big change.

### review — Decision Overview

**What it does:** Shows all decisions grouped by status/category, dependency graph, staleness warnings.

**When is it used?** Periodically, to prune stale decisions and verify the journal is healthy. Flags decisions >90 days old, broken dependency references, and scope files that changed since the decision was logged.

---

## How Each Hook Works

Hooks are the **automatic layer** — they fire without anyone calling them.

### SessionStart Hook — Cold-Start Decision Injection

**Trigger:** Fresh session start (`startup`) and after context compaction (`compact`).

Injects **all** active decision summaries unconditionally — no keyword matching, no scope filtering. This solves the cold-start problem: at session start there are no uncommitted changes, so `prompt-check.sh`'s scope matching can't contribute a second signal. This hook ensures Claude always has the full journal context from the first prompt.

Also fires after compaction, when previously injected decision context is lost.

### PreToolUse Hook — Auto-Warn Before Edits

**Trigger:** Every `Edit` or `Write` (matcher: `Edit|Write`).

Extracts `file_path` from tool input. Checks if that file is in any active decision's scope. If yes, injects the decision's title and Change Warning as `additionalContext` — Claude sees it before the edit executes.

**Informs, never blocks.** The hook can't judge intent — it just provides context. Claude decides if the edit is compatible.

### UserPromptSubmit Hook — Decision Context Injection

**Trigger:** Every user prompt.

**This is the deterministic enrichment layer** from RESEARCH.md. Matches the user's prompt against decision keywords and file scope. If relevant decisions are found, outputs their summaries as plain text — automatically injected as context before Claude starts thinking.

Matching thresholds:
- 2+ keywords → match
- 1 keyword + scope overlap → match
- 1 strong keyword alone (≥ 5 chars) → match (e.g., "safety", "button", "design")
- 1 weak keyword alone (< 5 chars: "fix", "add", "ui") → no match (too noisy)
- Scope alone → no match (PreToolUse handles per-file)

### PostToolUse Hook — Nudge After Significant Changes

**Trigger:** Every `Write` or `Edit` (matcher: `Write|Edit`), after the tool executes.

Checks if the change is "obviously significant": a config file was modified, or a brand new file was created (Write to a path not tracked by git). If yes, outputs a brief `systemMessage` nudging Claude to consider logging.

**Highly selective to avoid spam.** Regular code edits produce no output. A 15-minute cooldown between nudges prevents noise during iterative config work. Temp files: `.decisions/.last_nudge` (cooldown marker).

### Stop Hook — Smart Blocking at Session End

**Trigger:** Session end, if `.decisions/` exists AND there are uncommitted changes.

**This is the primary enforcement mechanism.** Analyzes git state and blocks the session (exit 2) if decision-worthy changes are detected without a logged decision. Falls back to a gentle non-blocking reminder for routine changes.

**Decision-worthy heuristics:**
1. New untracked files created (not in `.decisions/`)
2. Files deleted
3. Config files changed (package.json, tsconfig, Dockerfile, CLAUDE.md, etc.)
4. More than 5 files changed (likely refactor)

**Session detection for new DECs:** Checks untracked DEC files, staged DEC files, and recently committed DEC files (`git log --since="4 hours ago"`).

**Escape hatch:** On first block, creates `.decisions/.stop_reminded` marker. On second stop attempt within 10 minutes, allows through and deletes the marker. Prevents infinite blocking while ensuring Claude is confronted with the choice at least once.

---

## How Skills and Hooks Work Together

```
Session starts
       │
       ▼
┌─────────────────────┐
│ SessionStart         │  Hook injects ALL active decisions
│ (session-start.sh)   │  → Claude has full journal from start
└──────────┬──────────┘
           │
           ▼
User types prompt
       │
       ▼
┌─────────────────────┐
│ UserPromptSubmit     │  Hook injects relevant journal entries
│ (prompt-check.sh)   │  → Claude sees them before thinking
└──────────┬──────────┘
           │
           ▼
    Claude reads journal context,
    plans response, flags conflicts
           │
           ▼
┌─────────────────────┐
│ PreToolUse           │  Hook warns if edited file is
│ (pretooluse.sh)      │  governed by a past decision
└──────────┬──────────┘
           │
           ▼
    Claude executes edit
    (informed by journal)
           │
           ▼
┌─────────────────────┐
│ PostToolUse          │  Hook nudges if significant change
│ (posttooluse.sh)     │  (new file, config file)
└──────────┬──────────┘
           │
           ▼
    Task complete → Claude logs
    decision via /decision-guard:log
    (fills in everything itself)
           │
           ▼
┌─────────────────────┐
│ Stop                 │  Hook BLOCKS if decision-worthy
│ (stop-reminder.sh)   │  changes without logged decision
└─────────────────────┘
```

| Layer | When | What |
|-------|------|------|
| `session-start.sh` | Session start + compaction | Inject ALL active decisions (cold-start protection) |
| `prompt-check.sh` | Every prompt | Inject relevant decisions by keyword (strong ≥5 chars match alone) |
| `pretooluse.sh` | Every Edit/Write | Warn if file is governed by decision |
| `posttooluse.sh` | After Write/Edit | Nudge if significant change detected |
| `/decision-guard:check` | On-demand | Deep 3-level conflict analysis + dependency chain traversal |
| `/decision-guard:log` | After significant changes | Claude writes to journal |
| `stop-reminder.sh` | Every response | **Block** if decision-worthy changes without logging |

---

## Key Design Decisions

### Why Claude writes the journal (not the user)

The original design had a structured interview: 4 groups of questions, user answers each one. This was wrong for two reasons:

1. **Friction kills adoption.** Vibe coders won't answer 8 questions about their decision. They'll skip the logging entirely.
2. **Claude has all the context.** The user's prompt IS the rationale. The changed files ARE the scope. The alternatives Claude considered ARE the alternatives. There's nothing the user knows that Claude doesn't already have in the conversation.

The CLAUDE.md rule instructs Claude to log after significant changes, filling in everything from conversation context. The user sees only: `Decision logged: DEC-001 — Design changed to blue`

### Why the Change Warning is the most important field

Every other field (title, scope, keywords) helps with retrieval — finding the right decision. But the Change Warning is the only field that tells a future session **what to do.** It's the direct instruction that prevents the loop:

*"If someone says 'fix the colors' do NOT revert to the old red scheme — the blue was deliberate. Ask first."*

Without this field, Claude would find the decision but might still proceed with the conflicting change. The Change Warning gives explicit instructions: what NOT to do, what to ask, what would break.

### Why a plugin with skills AND hooks

- **Hooks alone:** Can't do interactive Q&A (needed for edge cases in log) or rich formatted output (needed for check/review)
- **Skills alone:** User has to remember to invoke them. The whole point is preventing loops even when nobody remembers to check.
- **Both together:** Hooks provide automatic safety net. Skills provide deep analysis when needed.

### Why Markdown + YAML Frontmatter

- Human-readable AND machine-parseable
- Git-friendly — decisions are versioned with the code
- `grep`/`sed` parseable — no language runtime needed
- Known pattern (Jekyll, Hugo, Obsidian, Claude Code's own SKILL.md)

### Why the Stop hook blocks (smart enforcement)

The original design was "inform, never block" — all hooks exit 0. Testing showed that CLAUDE.md rules are only 60-75% reliable. A gentle systemMessage reminder at session end is easily ignored because the session is ending anyway.

The enhanced Stop hook uses **smart blocking**: it only blocks when git state shows decision-worthy changes (new files, deleted files, config changes, large refactors) AND no DEC file was created this session. Routine work (bug fixes, typos, small edits) passes through with a gentle reminder.

An **escape hatch** prevents infinite blocking: the hook blocks once, then allows through on the second attempt within 10 minutes. This ensures Claude is confronted with the choice without trapping it in a loop.

The PostToolUse nudge complements this by reminding Claude right after an obviously significant change, when the context is still fresh — increasing the chance that Claude logs before the session ends.

### Why full injection (not selective retrieval)

All active decisions are injected into the prompt. No embedding model, no vector store. This works because:
- Typical projects have 5-30 active decisions (~2,500-15,000 tokens)
- Full injection means no retrieval gaps — Claude always sees everything
- The review skill helps prune stale decisions to keep the active set manageable

---

## What Was NOT Built (and Why)

### From RESEARCH.md — "The 5 Things Nobody Has"

| Capability | Status |
|-----------|--------|
| 1. Structured Decision Log with dependencies | **Solved** — YAML frontmatter with depends_on, enables, conflicts_with, supersedes |
| 2. Deterministic Enrichment Layer | **Solved** — UserPromptSubmit hook injects decisions before Claude reasons, on every prompt |
| 3. Conflict Detection | **Solved** — Three-level matching (scope + keyword + semantic) |
| 4. Temporal Awareness | **Partially** — Date tracking, status lifecycle, 90-day staleness. Missing: `valid_until`, evidence decay scoring |
| 5. Automatic Warning | **Solved** — PreToolUse hook (per edit) + UserPromptSubmit hook (per prompt) + check skill (on-demand) |

### What's missing

| Feature | Why not |
|---------|---------|
| Automatic decision extraction from sessions | Claude logs via CLAUDE.md rule instead — higher quality, correct granularity |
| ChromaDB semantic search | Zero-dependency constraint. Full injection works to ~50 active decisions |
| Cross-project dependencies | Each project has its own `.decisions/`. No cross-project linking yet |
| F-G-R Trust Tuples (academic framework) | Too complex. Simple `status` field (active/superseded/reverted/deprecated) covers the practical need |
| `valid_until` timestamps | 90-day staleness heuristic instead — developers won't predict expiry dates |

The plugin covers the core problem: preventing AI coding loops. The remaining gaps are optimizations for scale.

---

## Bugs Found and Fixed During Testing

| Bug | Location | Root Cause | Fix |
|-----|----------|-----------|-----|
| Active decisions invisible on macOS | `check/SKILL.md` | BSD `sed` incompatibility | `grep '^status:'` instead |
| Frontmatter printed twice | `review/SKILL.md` | Overlapping sed ranges | Single range `sed -n '/^---$/,/^---$/p'` |
| Every prompt triggered decisions | `prompt-check.sh` | Scope-only matching was too aggressive | Require at least 1 keyword hit alongside scope |
| Stop reminder on empty journal | `stop-reminder.sh` | Only checked directory existence, not files | Added `ls .decisions/DEC-*.md` check |

All bugs caught during E2E testing.
