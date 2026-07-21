# Established Patterns
# Auto-maintained by Claude during sessions. Last updated: 2026-07-21
# These are conventions agreed on for THIS project. Follow them without being asked.

---

## How to Read This File

These are not generic best practices — they are decisions made specifically for this project.
When a pattern exists here, follow it by default. If you think a pattern should change, say so explicitly.

---

### Sensor / Actuator Split for Harness Limits

**Established**: 2026-07-21
**Applies to**: Anything that needs plan-usage or context data inside hooks

**The Pattern**:
The statusline script is the only official receiver of `rate_limits` data — it caches a normalized JSON state file; guard hooks only ever read that cache. The undocumented OAuth endpoint is a headless-only fallback.

**Why**:
No polling, no credentials in the interactive path, one place to normalize two data shapes.

**Do NOT**:
Call the OAuth endpoint from interactive-path hooks, or parse `/usage` UI output.

---

### Guards Fail Open

**Established**: 2026-07-21
**Applies to**: All `.claude/hooks/` scripts

**The Pattern**:
Missing jq, unreadable state, malformed transcript, curl failure → exit 0 / stay silent. A guard bug must never lock the user out of their own session. Test seams via env overrides (`CLAUDE_USAGE_OVERRIDE`, `CLAUDE_CONTEXT_OVERRIDE`), bypass via `CLAUDE_AUTONOMY=off`.

**Do NOT**:
Add `set -e` to a hook, or make a guard's error path block anything.

---

### Distribution Ownership Rule

**Established**: 2026-06-26 (extended 2026-07-21)
**Applies to**: `init-claude-project.sh` full init and `--sync`

**The Pattern**:
- **Template-owned** → overwritten on sync: agent bodies (installed set only), commands (all), hooks, autopilot.
- **User-owned** → merged or never touched: `settings.json` (keys added only when missing; an existing `hooks` key is sacred), changelogs (append `[Unreleased]` only), knowledge base (never touched by sync), custom CLAUDE.md content outside anchors.
- Shipped file stubs live in `templates/` (e.g. `templates/knowledge/`), never doubling as this repo's own live files.

**Do NOT**:
jq-deep-merge into a user's existing `hooks` key, or hardcode single-file copies in full init when a `sync_*` function exists.

---

### Test Style

**Established**: 2026-06-29
**Applies to**: `tests/*.test.sh`

**The Pattern**:
Self-contained bash, no framework, no network. `fail`/`assert_*` helpers + `PASS_COUNT`, `mktemp -d` fixture projects with trap cleanup, exercise the real `init-claude-project.sh`. Print `PASS` at the end.

---

<!-- Add new patterns above this line -->
