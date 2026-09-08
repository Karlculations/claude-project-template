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
The statusline script is the only official receiver of harness telemetry — it caches normalized JSON state files; guard hooks only ever read those caches. The undocumented OAuth endpoint is a headless-only fallback.

Two sensors, two caches (2026-07-24):
- `rate_limits.*` → `usage-state.json` → `usage-guard.sh`
- `context_window.{used_percentage,context_window_size}` → `context-state-<session_id>.json` → `context-guard.sh`

**Cache scope must match the metric's scope.** Usage is account-wide → one shared file is correct. Context belongs to a single session → the cache must be keyed by `session_id`, or two concurrent sessions clobber each other and the guard reads someone else's number. Copying the usage cache's shape for context was wrong for exactly this reason.

**Why**:
No polling, no credentials in the interactive path, one place to normalize two data shapes. Separate files because an API-key user has no `rate_limits` but still has a context window, and `usage-guard.sh` rewrites the usage file from its own API fallback (a shared file would clobber the context reading).

**Before adding a hook that needs a number, check whether the statusline payload already carries it.** `context-guard.sh` spent its whole life *estimating* context from transcript tokens over an assumed 200k window while `context_window.used_percentage` sat in the payload one script over — reading ~89% on a 1M-context model at 18% real usage (MISTAKE-012). The payload also carries `model.id` (with the `[1m]` suffix the transcript drops), `version`, `cost`, and `exceeds_200k_tokens`.

**Do NOT**:
Call the OAuth endpoint from interactive-path hooks, or parse `/usage` UI output. Do not infer window size from the model id in the transcript — it records `claude-opus-5`, not `claude-opus-5[1m]`.

---

### Guards Fail Open

**Established**: 2026-07-21
**Applies to**: All `.claude/hooks/` scripts

**The Pattern**:
Missing jq, unreadable state, malformed transcript, curl failure → exit 0 / stay silent. A guard bug must never lock the user out of their own session. Test seams via env overrides (`CLAUDE_USAGE_OVERRIDE`, `CLAUDE_CONTEXT_OVERRIDE`), bypass via `CLAUDE_AUTONOMY=off`.

**Do NOT**:
Add `set -e` to a hook, or make a guard's error path block anything.

**Corollary (2026-07-24)**: a parse fallback must be the SAFE value, not a neutral-looking one. `date -d "$X" || echo 0` looks harmless, but the 0 then fails a `> 0` guard and disables the expiry check entirely — turning "unreadable timestamp" into "blocks forever" (MISTAKE-011). Wherever a fallback feeds a safety condition, pick the value that fails open.

---

### Guarding an Operation You Cannot Interrupt

**Established**: 2026-07-24
**Applies to**: `usage-guard.sh`; any hook-based control over fan-out tools

**The Pattern**:
Hooks fire on main-loop tool calls. A fan-out tool (`Workflow`) spawns its agents through its own runtime, so **no hook fires for them and nothing can halt it once running** — and it returns partial results reporting success when they die. A guard that only checks "am I over the limit right now" is useless against it. Guard the edges instead:
1. **Before — reserve headroom.** Refuse to *start* it at a *lower* threshold than the work-stop one (`CLAUDE_USAGE_FANOUT_THRESHOLD` 80% vs `CLAUDE_USAGE_THRESHOLD` 95%). The gap is deliberate: between the two, ordinary guarded work continues and only the unguardable call is refused. Say so in the deny reason, and name the guarded alternative (do it inline).
2. **After — re-measure, forcing freshness.** On its PostToolUse, bypass the state cache (`FETCH_TTL=0`): cached state can be a whole workflow out of date, and this is the first trustworthy reading since before the call. Over threshold → exit 2 so stderr reaches Claude (the tool already ran; nothing to deny), stating that results are PARTIAL.

Prefer re-measuring over parsing the tool's output for "limit" strings — a review workflow legitimately *discusses* rate limits, and the meter is unambiguous.

**Do NOT**:
Claim the blind spot is closed. The window during the run is irreducible with hooks alone; only entry and exit are controllable.

---

### Distribution Ownership Rule

**Established**: 2026-06-26 (extended 2026-07-21)
**Applies to**: `init-claude-project.sh` full init and `--sync`

**The Pattern**:
- **Template-owned** → overwritten on sync: agent bodies (installed set only), commands (all), hooks, autopilot.
- **User-owned** → merged, additive-only, or never touched: `settings.json` (statusLine added only when missing; hook entries appended per-event ONLY when no existing entry references the same script basename; for an entry that DOES reference the same template script, its `matcher` is unioned with the template's — a matcher is a regex alternation, so this is set-union over the `|` alternatives, additive by construction: the template can widen what a guard watches but never narrow it, and a project's own alternatives always survive (2026-07-24; without it a widened guard never reached an already-synced project while `--sync` reported "up to date") — never removes an existing entry, and every merge is idempotent), changelogs (append `[Unreleased]` only), knowledge base (never touched by sync), custom CLAUDE.md content outside anchors.
- Shipped file stubs live in `templates/` (e.g. `templates/knowledge/`), never doubling as this repo's own live files.
- Policy change 2026-07-21: the old "existing `hooks` key is sacred, warn and skip" rule silently orphaned new template hooks in previously-synced projects (script copied, never wired). Additive entry-level merge fixed that; the sanctioned opt-out for a guard is `CLAUDE_AUTONOMY=off`, since deleting its entry means the next `--sync` re-adds it.

**Do NOT**:
modify or remove existing entries in a user's `hooks` key (append-only, keyed by script basename), or hardcode single-file copies in full init when a `sync_*` function exists.

---

### Test Style

**Established**: 2026-06-29
**Applies to**: `tests/*.test.sh`

**The Pattern**:
Self-contained bash, no framework, no network. `fail`/`assert_*` helpers + `PASS_COUNT`, `mktemp -d` fixture projects with trap cleanup, exercise the real `init-claude-project.sh`. Print `PASS` at the end.

---

<!-- Add new patterns above this line -->
