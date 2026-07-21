# Session Log
# Appended by Claude at the end of each session via /end-session command.
# Most recent sessions at the top.

---

## Session: 2026-07-21 (later) — Auto-resume layer: autopilot handoff, active-task marker, additive settings merge

### Completed
- **Autopilot handoff (usage guard)**: PreToolUse deny message now instructs — persist state, then (default-on unless user said wait / task blocked on their input) background-launch `nohup .claude/autopilot.sh "continue: <summary>" >> ~/.cache/claude-autonomy/autopilot.log` with `AUTOPILOT_CLAUDE_ARGS` mirroring the approved permission mode. Bash deliberately absent from the guard matcher so the handoff runs at trip time.
- **Auto-resume marker**: `/end-session` Step 4 now maintains `.claude/knowledge/active-task.md` (write when unfinished + blocked-on-user flag; delete when complete). New `session-start-brief.sh` (SessionStart `startup|clear`) injects it into fresh sessions → first user message resumes the task. 4KB cap, jq-escaped, whitespace-only = silent, fail open.
- **Review fixes**: autopilot exports `CLAUDE_AUTOPILOT=1` (child gets "continue directly" variant — without it the pgrep check made autopilot's own turn refuse its job); `AUTOPILOT_TASK_BLOCKED` sentinel (exit 1, one turn, instead of burning 24); end-session release questions skipped headless; context-guard message names the marker.
- **Additive settings merge in `--sync`**: template hook entries appended per-event iff no existing entry references the same script basename; existing entries never modified; idempotent. Replaces "existing hooks key is sacred" (which silently orphaned new hooks in previously-synced projects). Opt-out = `CLAUDE_AUTONOMY=off`.
- Tests 59 → **78 assertions**, all green. Docs synced (CLAUDE.md guards, README, components.md, patterns.md).

### In Progress / Left Off At
- Nothing in flight; no active-task.md needed. 12 files modified/added, ALL UNCOMMITTED on `main` — user to review + commit (offered twice, not yet answered).
- CHANGELOG root `[Unreleased]` updated this session; release/versioning still the user's call.

### Blockers
- None technical. Commit decision is the user's.

### Key Decisions Made
- Handoff is default-ON at guard trip (user preference, stated twice); exceptions: user said wait, or task blocked on user input.
- Interactive sessions cannot self-wake at reset — headless autopilot handoff is the mechanism; the brief makes any first message resume.
- `--sync` merge policy change is deliberate and documented in patterns.md (2026-07-21 entry).

### Watch Out For (Next Session)
- `active-task.md` is injected into fresh-session context — keep it short; it's also a prompt-injection surface in cloned repos (accepted, same trust as CLAUDE.md).
- Background workflows die on idle session gaps (MISTAKE-008); recover from journal.jsonl.
- If headless autopilot runs stall: check `AUTOPILOT_CLAUDE_ARGS` permission mode and `~/.cache/claude-autonomy/autopilot.log`.

---

## Session: 2026-07-21 — Autonomy layer: usage/context guards, autopilot, template distribution

### Completed
- Built `.claude/hooks/` (statusline sensor, usage-guard, context-guard, session-compact-brief), `.claude/autopilot.sh`, `.claude/settings.json`
- `init-claude-project.sh`: new `sync_autonomy()` wired into full init + `--sync`; full init now reuses `sync_commands`
- CLAUDE.md: "Autonomy Guards" protocol added inside `CLAUDE_PROTOCOLS` anchors (propagates via --sync); README: autonomy section, file tree, script table
- `tests/autonomy-layer.test.sh` — 44 assertions green; changelog suite (37) still green
- Moved shipped knowledge stubs to `templates/knowledge/` (init path updated) so this repo keeps a real knowledge base — conflict found when the context-guard fired on its own author mid-session

### Review Findings — all 12 confirmed, all fixed (task `wu4sfw0lo`, 19 agents, 4 refuted)
- 🔴 arithmetic injection via poisoned state file (`(( PCT ))`) → regex-validate before arithmetic, private state dir
- 🟠 OAuth token on curl argv (world-readable) → `-K` config fd
- 🟠 "fail open" actually failed CLOSED on expired/stale state → blank past-`resets_at`, stale-age note
- 🟠 autopilot false-success on restated sentinel → `grep -qxF` whole-line
- 🟠 `--status`/`--json` silent when jq missing → explicit error
- minor: `--sync` aborted on invalid target JSON; merge-fail printed success; autopilot burned turns on rc=127; shared `.tmp` race; unquoted `$CLAUDE_PROJECT_DIR` → all fixed
- Tests grew 44 → 59 assertions (added expiry, injection, jq-missing, autopilot semantics, malformed-settings). Both suites green (59 + 37).

### In Progress / Left Off At
- Nothing committed. Staged: `git mv` of knowledge stubs to `templates/knowledge/`. Untracked: `.claude/{hooks,autopilot.sh,settings.json,knowledge}`, `tests/autonomy-layer.test.sh`, `CHANGELOG.md`. Ready for the user to review + commit.
- CHANGELOG.md created at root under `## [Unreleased]` — NOT released/versioned (this repo has no version manifest; deploy-gated release is the user's call).

### Blockers
- Cannot live-probe the OAuth usage endpoint in-session (classifier denies credential reads). Shape verified via 3 community sources; user self-test: `.claude/hooks/usage-guard.sh --status`

### Key Decisions Made
- Statusline = official usage sensor cached to a state file; hooks are actuators reading it; OAuth endpoint (`claude-code/*` User-Agent required) is headless-only fallback
- Guards fail open, `CLAUDE_AUTONOMY=off` bypass, thresholds via env (95% usage / 80% context)
- settings.json merged never clobbered; existing `hooks` key never touched
- Autopilot stops work at threshold and waits for the official reset — no limit evasion, no permission grants

### Watch Out For (Next Session)
- CLAUDE.md keeps `[PROJECT_*]`/`[DATE]` placeholders — they ARE the template payload; do not "fix" them
- `.claude/knowledge/` in this repo is now REAL; shipped stubs live in `templates/knowledge/`
- This repo dogfoods its own hooks — the statusline/guards are active here; project `statusLine` overrides any user-level one (flagged to Karl, pending his call)
- The 7-day bucket from the OAuth endpoint is unreliable (community-measured ~72h resets; `resets_at` misleading) — guards only key off `five_hour`

---

<!-- Sessions appended above this line, newest first -->
