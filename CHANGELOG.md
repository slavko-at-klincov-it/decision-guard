# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-27

### Added

- **4 Skills**: init, log, check, review
- **5 Hooks**: session-start, prompt-check, pretooluse, posttooluse, stop-reminder
- **Smart enforcement**: Stop hook blocks session end when decision-worthy changes detected without logging, with escape hatch to prevent infinite blocking
- **Cold-start protection**: SessionStart hook injects all active decisions at session start and after context compaction
- **Strong keyword matching**: Keywords >= 5 characters match alone in prompt-check; short keywords need additional signals (2+ hits or scope overlap)
- **PostToolUse nudge**: Non-blocking reminder after config file changes or new file creation, with 15-minute cooldown
- **Transitive dependency analysis**: Check skill follows depends_on/enables/conflicts_with chains
- **CRLF-safe parsing**: All hooks handle Windows line endings
- **YAML quote stripping**: Quoted keywords are matched correctly
- **Decision lifecycle**: active, superseded, reverted, deprecated status with 90-day staleness detection
- **Three-level conflict detection**: Scope + Keyword + Semantic matching with precision rules
