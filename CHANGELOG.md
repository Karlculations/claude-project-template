# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Autonomy layer.** Every initialized project now installs guard hooks that make a session aware of its two hard limits and react before either truncates work:
  - A **status line** showing live plan usage (5-hour and 7-day windows with reset times).
  - A **usage guard** that pauses new work when the 5-hour window passes a threshold (default 95%) and tells you when it resets, so a task is never cut off mid-thought by hitting the cap.
  - A **context guard** that prompts the session to save its knowledge base before the context window fills — so nothing is lost to compaction.
  - A **compaction brief** that re-orients the session from its knowledge base after a compaction.
  - **`autopilot.sh`**, an unattended runner that works a task in turns, waits out the usage window when it's spent, and automatically resumes when the window resets.
- Guards are configurable (thresholds via env vars), fail safe (an internal error never blocks your work), and can be turned off with `CLAUDE_AUTONOMY=off`.

- **Hands-off task continuity.** Once you give a task the go-ahead, no manual restarts are needed:
  - When the usage window runs out mid-task, the session now hands the remaining work to autopilot automatically (unless you asked it to wait), so it finishes on its own after the reset.
  - Sessions remember what they were doing: an unfinished task is recorded on session end and injected into your next session — your first message resumes the work instead of re-explaining it.
  - Autopilot now stops early and tells you when a task needs your input, instead of spending its remaining turns stuck.

- **Tooling stack picker.** `init` now offers a curated catalog of plugins, skills, and MCP servers to install per project (`--capture` refreshes the catalog from your own machine; `--sync` keeps a project's vendored skills current) — selections are written additively into `.claude/settings.json`, `.mcp.json`, and `.claude/skills/`, with matching claude.ai connectors recommended alongside.

### Changed
- `init` and `--sync` now install and refresh the autonomy layer alongside agents and commands. An existing `settings.json` is merged additively — your own hooks and permissions are always preserved, and new template hooks now reach previously-synced projects too.
