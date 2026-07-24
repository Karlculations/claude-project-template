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
- `init` and `--sync` now install and refresh the autonomy layer alongside agents and commands. An existing `settings.json` is merged additively — your own hooks and permissions are always preserved, and new template hooks now reach previously-synced projects too. `--sync` now also widens an existing guard hook to cover any newly-watched tools — merged in, so tools you added yourself are kept and nothing you configured is dropped — and prints which tools the usage guard ends up watching, so an out-of-date guard can't sit unnoticed.

### Fixed
- **The usage guard could be bypassed by ordinary work.** It only ran before subagent, web, and MCP calls, so a long stretch of shell commands and file edits never triggered a check — a session could run straight past its limit with no pause and no handoff to autopilot. The guard now also runs before every shell command (and before starting a workflow). The autopilot handoff command is exempt so the automatic resume still works, and file edits stay exempt so the end-of-session knowledge save can always complete.
- The guard no longer retries an unreachable usage API on every single check — after a failure it backs off for two minutes, so a network problem can't slow a session to a crawl.
- **Workflows could exhaust the window invisibly.** A workflow runs its sub-agents internally, where no guard can reach them — so it could start with almost no window left, lose agents to the limit mid-run, and still return "successfully" with partial results. Starting a workflow is now refused earlier than ordinary work (80% instead of 95%) so there's room to finish it, and when one returns the guard re-checks usage immediately and warns that its results may be incomplete instead of letting them be trusted silently.
- **The context guard fired far too early on large-context models.** It assumed a 200,000-token window, so on a 1M-token model a session that was 18% full was reported as ~89% full and interrupted with an emergency "save your knowledge base now". It now uses the real context percentage Claude Code reports — including your actual window size — and only falls back to estimating when that isn't available (unattended runs), where it still uses the real window size if it has ever seen one.
- **A guard could lock you out instead of getting out of your way.** Reset times arrive in two different formats, and the guard understood only one — so a stale reading whose window had *already reset* was treated as still valid and blocked every prompt indefinitely. Both formats are now handled, and reset times are shown as a readable date rather than a raw number.
