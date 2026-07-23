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

**Established**: 2026-06-26 (extended 2026-07-21, 2026-07-22)
**Applies to**: `init-claude-project.sh` full init and `--sync`

**The Pattern**:
- **Template-owned** → overwritten on sync: agent bodies (installed set only), commands (all), hooks, autopilot, vendored skill bodies under `.claude/skills/` (refreshed to match `templates/skills/` on sync, never added — a project only gets a skill it already selected).
- **User-owned** → merged, additive-only, or never touched: `settings.json` (statusLine added only when missing; hook entries appended per-event ONLY when no existing entry references the same script basename, `enabledPlugins`/`extraKnownMarketplaces` appended-only from the stack picker — none of these ever modify or remove an existing entry, and every merge is idempotent), `.mcp.json` (`mcpServers` appended-only — an existing server id always wins over the catalog's), changelogs (append `[Unreleased]` only), knowledge base (never touched by sync), custom CLAUDE.md content outside anchors.
- Shipped file stubs live in `templates/` (e.g. `templates/knowledge/`, `templates/catalog.json`, `templates/skills/`), never doubling as this repo's own live files.
- Plugins and MCP servers referenced in the stack catalog are never vendored (installs are native to Claude Code, triggered by the config the picker writes) — only skill bodies are copied into the repo.
- Credentials are redacted at the source: `capture_stack()` rewrites MCP `env`/`headers` values to `${SERVERID_KEY}` placeholders before they ever reach `templates/catalog.json` — a literal credential must never be committed.
- Policy change 2026-07-21: the old "existing `hooks` key is sacred, warn and skip" rule silently orphaned new template hooks in previously-synced projects (script copied, never wired). Additive entry-level merge fixed that; the sanctioned opt-out for a guard is `CLAUDE_AUTONOMY=off`, since deleting its entry means the next `--sync` re-adds it.

**Do NOT**:
modify or remove existing entries in a user's `hooks` key (append-only, keyed by script basename), an existing `enabledPlugins`/`extraKnownMarketplaces`/`mcpServers` entry, or hardcode single-file copies in full init when a `sync_*` function exists. Never write a literal credential value into `templates/catalog.json` — redact at capture, not later.

---

### Test Style

**Established**: 2026-06-29
**Applies to**: `tests/*.test.sh`

**The Pattern**:
Self-contained bash, no framework, no network. `fail`/`assert_*` helpers + `PASS_COUNT`, `mktemp -d` fixture projects with trap cleanup, exercise the real `init-claude-project.sh`. Print `PASS` at the end.

---

<!-- Add new patterns above this line -->
