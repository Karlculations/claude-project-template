# Component Registry
# Auto-maintained by Claude during sessions. Last updated: 2026-07-21
# Format: Add entries as components are created or modified.

---

## How to Read This File

Each entry covers one module, component, service, or significant function.
Claude reads this file at the start of every session to avoid rebuilding what already exists.

---

## Autonomy Layer — Guard Hooks

**Type**: Hook scripts (template payload, shipped to every project)
**Location**: `.claude/hooks/{statusline,usage-guard,context-guard,session-compact-brief}.sh`
**Added**: 2026-07-21
**Last Modified**: 2026-07-21

**What it does**:
Makes sessions aware of their two hard limits and react before either truncates work.
- `statusline.sh` — SENSOR. Claude Code pipes official `rate_limits` (5h/7d % + reset times, Pro/Max CC≥2.1) to the statusline; the script renders it and caches a normalized copy to `${CLAUDE_USAGE_STATE:-$XDG_RUNTIME_DIR/claude-usage-state-$(id -u).json}`.
- `usage-guard.sh` — ACTUATOR. UserPromptSubmit: exit 2 blocks prompts at ≥95% (`CLAUDE_USAGE_THRESHOLD`). PreToolUse (matcher `Task|WebFetch|WebSearch|mcp__.*`): JSON `permissionDecision: deny` whose reason instructs Claude to run /end-session, then — ONLY with a standing user go-ahead for unattended continuation — background-launch autopilot (`nohup .claude/autopilot.sh "continue: <summary>" &`) before stopping, so the task self-resumes after reset. Bash is deliberately NOT in the matcher: the handoff command stays executable at trip time. Also a CLI: `--status` / `--json`. Headless fallback: undocumented `GET api.anthropic.com/api/oauth/usage` (needs `claude-code/*` User-Agent or it 429s).
- `context-guard.sh` — Stop hook. Estimates context from the transcript's last `message.usage`; at ≥80% (`CLAUDE_CONTEXT_THRESHOLD`) blocks the stop ONCE per session (marker file keyed by session_id) demanding /end-session Steps 1–4. Respects `stop_hook_active`.
- `session-compact-brief.sh` — SessionStart(matcher `compact`). Injects `additionalContext` telling the session to re-read `.claude/knowledge/` after compaction.
- `session-start-brief.sh` — SessionStart(matcher `startup|clear`). Auto-resume: if `.claude/knowledge/active-task.md` exists (written by /end-session Step 4 when a task is unfinished, deleted on completion), injects it (4KB cap, jq-escaped, whitespace-only = no task) with an instruction to continue the task immediately — exceptions: marker says blocked-on-user-input, or autopilot already running (`pgrep -f autopilot.sh`). When `CLAUDE_AUTOPILOT=1` (set by autopilot for its own headless turns) the pgrep exception is dropped — otherwise autopilot's child would see its parent and refuse its own job — and the brief points at the `AUTOPILOT_TASK_BLOCKED` sentinel instead. Silent + fail open when no marker/jq. Interactive sessions still need ONE user message to take a turn — the brief makes any first message resume the task.

**Key dependencies**:
- `jq` — all parsing; every guard fails OPEN without it or on any error
- `.claude/settings.json` — wiring (hook events + statusLine, `$CLAUDE_PROJECT_DIR` paths)

**Notes / Caveats**:
- `CLAUDE_AUTONOMY=off` bypasses every guard (checked BEFORE any state fetch in hook mode — no latency when disabled).
- Transcript JSONL parsing is documented-unstable; context-guard treats any parse miss as 0% (fail open).
- GNU `date` assumed for reset-time formatting; BSD/macOS shows the raw ISO string.
- **Fail-open covers missing, malformed, AND expired data**: a reading whose `resets_at` is already past is blanked (never blocks); TTL-stale readings still act but carry a "reading is Nm old" note.
- **Security-hardened** (2026-07-21 review): all file/env values are regex-checked before reaching `(( ))` (no arithmetic injection); state lives in a private `${XDG_RUNTIME_DIR:-$HOME/.cache}/claude-autonomy/` dir, not bare /tmp; the OAuth token goes to curl via a `-K` config fd, never argv; atomic writes use a `$$`-suffixed tmp so concurrent sessions don't race.
- CLI `--status`/`--json` print an explicit error when jq is missing (never silent).

---

## Autopilot Runner

**Type**: Shell script (template payload)
**Location**: `.claude/autopilot.sh`
**Added**: 2026-07-21

**What it does**:
Unattended headless runner: `.claude/autopilot.sh "task" [max_turns]`. Before each turn checks the 5h window via `usage-guard.sh --json`; at ≥ threshold sleeps until the known `resets_at` (+120s, blind 15-min poll if unknown), then resumes the SAME session with `claude -p --continue`, re-orienting from `session-log.md`. Exports `CLAUDE_AUTOPILOT=1` so hooks in its turns know they ARE the autopilot run. Stops on the whole-line `AUTOPILOT_TASK_COMPLETE` sentinel (exit 0), the whole-line `AUTOPILOT_TASK_BLOCKED` sentinel (exit 1 — task needs user input; don't burn remaining turns), or max turns (exit 1).

**Notes / Caveats**:
- Does not evade limits — stops early (95% default) and waits for Anthropic's own reset.
- Grants no permissions; pass `AUTOPILOT_CLAUDE_ARGS` for unattended permission modes.

---

## sync_autonomy() — Distribution

**Type**: Function in `init-claude-project.sh`
**Location**: `init-claude-project.sh` (after `sync_commands`), called from full init AND `--sync`
**Added**: 2026-07-21

**What it does**:
Copies hooks + autopilot into the target (template-owned: always overwritten, chmod +x). `settings.json` is conservative: created if absent; if present, `hooks`/`statusLine` keys are jq-merged only when missing; an existing `hooks` key is never touched (warns to merge manually).

**Notes / Caveats**:
- Full init now reuses `sync_commands` instead of a hardcoded end-session.md copy.
- Knowledge stubs ship from `templates/knowledge/` (moved 2026-07-21 so this repo can keep a real knowledge base).

---

## Autonomy Layer Tests

**Type**: Test suite
**Location**: `tests/autonomy-layer.test.sh` (house style: self-contained bash, `assert_*` helpers, temp dirs)
**Added**: 2026-07-21

**What it does**:
78 assertions, no network (override/state-file seams only): syntax, sensor render+cache, all guard paths (block/pass/bypass/threshold/cache-read), context-guard (block/once-per-session/stop_hook_active/fail-open), compaction brief, and three `--sync` distribution scenarios (fresh install, merge, hooks-conflict).

---

## Stack Catalog — capture/picker/distribution

**Type**: Three functions in `init-claude-project.sh` + shipped catalog
**Location**: `capture_stack()` / `pick_stack()` / `sync_stack()` in `init-claude-project.sh`; data in `templates/catalog.json` + `templates/skills/`
**Added**: 2026-07-22

**What it does**:
- `capture_stack()` (`--capture` only, run on the maintainer's own machine) reads this machine's user-level Claude Code config and writes `templates/catalog.json` + vendors `templates/skills/*` bodies: enabled plugins from `~/.claude/settings.json`'s `enabledPlugins`, marketplaces (source ref only) from `~/.claude/plugins/known_marketplaces.json`, MCP servers from `~/.claude.json`, skill catalog entries (description scraped from frontmatter) + bodies from `~/.claude/skills/*`.
- `pick_stack()` (full init only) prompts per catalog group ([a]ll/[n]one/[p]ick, "ungrouped" last), fills `STACK_SEL_{PLUGINS,SKILLS,MCPS,GROUPS}`, then recommends any claude.ai connectors whose `group` matches a selected group (or ungrouped connectors, always) — connectors are never installed, only printed as a note.
- `sync_stack()` (full init AND `--sync`) writes the selection into the target: plugins → `.claude/settings.json` (`enabledPlugins` + `extraKnownMarketplaces`, additive), MCP servers → `.mcp.json` (`mcpServers`, existing keys win), skills → vendored copy into `.claude/skills/` (template-owned, always overwritten). No installs are scripted — opening Claude Code in the project triggers its own trust/install prompts.

**Env seams** (all overridable for tests):
- `CLAUDE_USER_DIR` (default `$HOME/.claude`) — source of `settings.json`, `plugins/known_marketplaces.json`, `skills/`
- `CLAUDE_USER_CONFIG` (default `$HOME/.claude.json`) — source of `mcpServers`
- `CLAUDE_STACK_CATALOG` (default `$TEMPLATE_DIR/templates/catalog.json`) — capture target / picker source
- `CLAUDE_STACK_SKILLS_DIR` (default `$TEMPLATE_DIR/templates/skills`) — vendored skill bodies, capture target / sync source

**Redaction rule**: MCP server `env`/`headers` values are ALWAYS rewritten at capture to `${SERVERID_KEY}` placeholders (never the literal value) — a credential must never reach the repo. A re-capture keeps a hand-renamed `${...}` placeholder already in the catalog over the freshly derived one (same key, both are placeholders — never a literal survives). `capture_stack()` also warn-only flags suspicious inline `key=`/`token=`/`--api-key`-style values in MCP `url`/`args` (never auto-rewritten, since url/args aren't redacted the way env/headers are).

**Additive-merge contracts**: curation (`group`/non-empty `description`) on an existing catalog item survives every re-capture; items no longer on the machine are kept and reported (`⚠ in catalog but not on this machine`), never auto-removed; `sync_stack()`'s writes to `.claude/settings.json`/`.mcp.json` only ever add — an existing `enabledPlugins`/`extraKnownMarketplaces`/`mcpServers` entry in the target project is never rewritten or dropped.

**Test suite**: `tests/catalog-distribution.test.sh`

**Notes / Caveats**:
- All three skill-copy call sites (`capture_stack()`'s vendor step, `sync_stack()`, `sync_skill_bodies()`) use `cp -rL`, not `cp -r`. Found during Task 6's real capture: a user-level skill dir is frequently itself a symlink (e.g. into a dotfiles/plugin checkout, `~/.claude/skills/x -> ../../.agents/skills/x`). Plain `cp -r` copies the symlink itself, carrying its relative target — which resolves to nothing once relocated into this repo, silently vendoring a broken symlink with zero content. `-L` dereferences and copies the real files. Regression check: `find templates/skills -maxdepth 1 -type l` must always be empty.

---

<!-- Add new components above this line -->
