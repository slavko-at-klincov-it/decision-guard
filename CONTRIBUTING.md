# Contributing to decision-guard

## Development Setup

```bash
# Clone the repo
git clone https://github.com/slavko-at-klincov-it/decision-guard.git
cd decision-guard

# Run Claude Code with the plugin loaded
claude --plugin-dir ./decision-guard
```

## Project Structure

```
decision-guard/           # Plugin root
  .claude-plugin/         # Plugin manifest
  skills/                 # Skill definitions (SKILL.md files)
  hooks/                  # Hook scripts (bash) + hooks.json manifest
```

## Testing Hooks

Each hook can be tested standalone by piping JSON to stdin:

```bash
cd /tmp && mkdir test-project && cd test-project
git init && git commit --allow-empty -m "init"
mkdir .decisions

# Create a test decision
cat > .decisions/DEC-2026-0101-001-test.md << 'EOF'
---
id: DEC-2026-0101-001
title: "Test decision"
status: active
date: 2026-01-01
category: design
scope:
  - src/app.ts
keywords:
  - testing
  - design
---
## Decision
Test decision.
## Change Warning
Do not change without asking.
EOF

# Test each hook
HOOKS=/path/to/decision-guard/hooks

echo '{}' | bash "$HOOKS/session-start.sh"
echo '{"prompt":"change the design"}' | bash "$HOOKS/prompt-check.sh"
echo '{"tool_input":{"file_path":"src/app.ts"}}' | bash "$HOOKS/pretooluse.sh"
echo '{"tool_name":"Edit","tool_input":{"file_path":"package.json"}}' | bash "$HOOKS/posttooluse.sh"
echo '{}' | bash "$HOOKS/stop-reminder.sh"
```

Exit codes: `0` = allow/inform, `2` = block (stop-reminder.sh only).

## Guidelines

### Shell Scripts

- Target **bash 3.2+** (macOS default) — no bash 4+ features (associative arrays, `readarray`, etc.)
- Use `grep`/`sed`/`tr` for YAML parsing, not `jq` or `yq` (zero-dependency constraint)
- Always handle CRLF: pipe through `tr -d '\r'` when reading decision files
- Strip YAML quotes from values: `kw="${kw#\"}"; kw="${kw%\"}"`
- All hooks must exit 0 on missing `.decisions/` or `.git` (graceful degradation)
- Keep hook execution under 5 seconds — they run on every tool call or prompt

### Skills

- Follow the SKILL.md format with proper frontmatter
- Use `!`backtick`` for shell preprocessing (current state injection)
- Claude fills in decision content from conversation context — don't prompt the user with questions unless there's no context (cold start)

### Decisions

- YAML frontmatter fields must match what hooks parse (see `hooks/prompt-check.sh` for the canonical list)
- Keywords should be 3-6 words, chosen for what a future prompt would contain
- The `## Change Warning` section is the most important — it's what prevents loops

## Pull Requests

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Test your changes with the hook testing method above
4. Run `shellcheck decision-guard/hooks/*.sh` if available
5. Submit a PR with a clear description of what and why

## Reporting Issues

When reporting a bug, include:
- Your OS (macOS / Linux / WSL)
- Bash version (`bash --version`)
- The decision file content (if relevant)
- The exact input that triggered the issue
