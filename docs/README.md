# Battery CLI Documentation

This directory contains developer documentation and development session notes for the Battery CLI project.

## Directory Structure

```
docs/
├── README.md           # This file
└── sessions/           # Development session summaries
    └── 2025-11-03-granular-logs-and-dev-workflow.md
```

## Session Summaries (`sessions/`)

Development session summaries document significant work sessions, including:
- Features implemented
- Bugs fixed
- Design decisions made
- Technical context and reasoning
- Testing performed
- Follow-up items

**Purpose:** These summaries help future developers (human or AI) understand:
- Why certain decisions were made
- How features evolved over time
- Context that might not be obvious from code or commit messages alone
- Patterns and approaches used in the codebase

**Naming Convention:** `YYYY-MM-DD-brief-description.md`

## Other Documentation

- **[CLAUDE.md](../CLAUDE.md)** - Developer onboarding guide for Claude Code (AI assistant)
  - Project architecture overview
  - Development commands and workflows
  - Platform-specific considerations
  - Common development tasks

- **[CHANGELOG.md](../CHANGELOG.md)** - Chronological list of all changes
  - Follows [Keep a Changelog](https://keepachangelog.com/) format
  - Documents all features, fixes, and breaking changes

- **[README.md](../README.md)** - User-facing documentation
  - Installation instructions
  - Usage examples
  - FAQ and troubleshooting

- **[CONTRIBUTING](../CONTRIBUTING)** - Contributor guidelines
  - How to contribute to the project
  - Code standards and expectations

## For Developers

If you're working on the Battery CLI:

1. **Start here:** Read [CLAUDE.md](../CLAUDE.md) for architecture and development workflow
2. **Check sessions:** Browse `sessions/` to understand recent work and decisions
3. **Follow patterns:** See how similar features were implemented in past sessions
4. **Document your work:** Consider creating a session summary for significant changes

## For AI Assistants (Claude Code)

Session summaries provide valuable context for understanding:
- Recent development patterns and conventions
- Why certain architectural decisions were made
- How to approach similar problems in the future
- Testing strategies used in the project

Read recent session summaries before starting new work to maintain consistency with established patterns.
