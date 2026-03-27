---
name: Bug report
about: Something isn't working as expected
labels: bug
---

**Describe the bug**
A clear description of what went wrong.

**To reproduce**
1. Decision file content (if relevant)
2. The prompt or action that triggered the issue
3. What happened vs what you expected

**Environment**
- OS: [e.g., macOS 15, Ubuntu 24.04, WSL2]
- Bash version: [output of `bash --version`]
- Claude Code version: [output of `claude --version`]

**Hook output**
If applicable, test the hook directly:
```bash
echo '{"prompt":"your prompt"}' | bash decision-guard/hooks/prompt-check.sh
echo $?
```
