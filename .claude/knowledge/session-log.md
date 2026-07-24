# Session Log
# Appended by Claude at the end of each session via /end-session command.
# Most recent sessions at the top.

---

## Session: 2026-07-24 — Usage guard fired on nothing: matcher widened to Bash/Workflow, --sync matcher union

### Completed
- **Root cause of "the limit was hit and nothing paused"**: the guard was healthy and simply never invoked. PreToolUse matcher was `Task|WebFetch|WebSearch|mcp__.*`, so a long run of `Bash`/`Read`/`Edit`/`Write` fired **zero** checks; the sub-agents that actually died were spawned inside a background `Workflow` (own runtime → no main-loop PreToolUse); and by the next prompt `resets_at` had passed so UserPromptSubmit correctly failed open. Logged as MISTAKE-010.
- **Matcher** → `Task|Agent|Workflow|WebFetch|WebSearch|mcp__.*|Bash`. `Agent` because the subagent tool is named that in current builds; `Workflow` to refuse *starting* one near the limit.
- **Handoff carve-out** (`usage-guard.sh:150`): a Bash command containing `autopilot.sh` exits 0. Bash had been excluded from the matcher precisely because the deny message asks Claude to run `nohup .claude/autopilot.sh` — the guard would have denied its own escape hatch. Deny reason now states explicitly that the handoff will still run, so Claude doesn't infer "Bash denied → can't hand off". `Write`/`Edit`/`Read` stay unmatched so the /end-session dump can complete.
- **Fetch backoff** (`CLAUDE_USAGE_FETCH_BACKOFF`, 120s): at one guard call per Bash, a dead API meant a 6s curl timeout *every call*. Also validated `CLAUDE_USAGE_STATE_TTL` before `(( ))` — same class as MISTAKE-005, env-sourced rather than file-sourced.
- **`sync_autonomy()` matcher union**: the basename-keyed merge froze the matcher at first sync, so the fix would never have reached an already-synced project while `--sync` printed "up to date". Now unions the `|` alternatives (existing order first) for entries referencing the same template script. `--sync` prints `↳ usage-guard watches: …`.
- Tests 78 → **89** assertions. All suites green: 89 / 69 (catalog) / 37 (changelog). Docs synced: components.md, patterns.md, mistakes.md, README, CHANGELOG.
- Measured guard overhead: **~19ms per Bash call** — the "more frequent checks" cost that had been treated as the blocker is negligible.

### In Progress / Left Off At
- Nothing in flight. Committed and pushed to `origin/main`.

### Blockers
- None.

### Key Decisions Made
- **Carve-outs belong in the guard's logic, not the matcher.** A matcher-level exclusion is unconditional — it blinds the guard everywhere, not just where the exception is needed.
- **`--sync` unions matchers rather than overwriting them** (user's call — first pass overwrote; union keeps a project's own alternatives). Accepted trade: the template can widen a matcher but never shrink one. For a guard that is the fail-safe direction; to narrow, edit the entry or delete it and let the next `--sync` re-add the template's.
- Root CHANGELOG entries deliberately left under `## [Unreleased]` — this repo has no version manifest and has never cut a release; pushing the template is not a deploy.

### Watch Out For (Next Session)
- **Structural, unfixed**: hooks observe main-loop tool calls only, so agents spawned *inside* a running Workflow are invisible to them. Refusing to *start* a workflow near the limit is the only lever — one already in flight cannot be stopped by hooks. What improved is that the next Bash call after it returns now trips the guard.
- The union merge means a bad matcher alternative shipped in the template becomes sticky in synced projects — get widenings right the first time.
- This repo dogfoods its own hooks: every Bash call here now runs `usage-guard.sh`. If the session feels slow, check `~/.cache/claude-autonomy/usage-state.json.fetchfail` and `.claude/hooks/usage-guard.sh --status`.

---

## Session: 2026-07-22/23 — Stack catalog: subagent-driven execution, merged to main

### Completed
- All 6 plan tasks executed via subagent-driven development (fresh implementer + reviewer per task, fix/re-review loops). Branch `stack-catalog` (11 commits) merged to `main` as `85f8c40` (--no-ff). Post-merge suites: catalog 63, autonomy 78, changelog 37 — all green. NOT pushed (Karl pushes).
- Shipped: `--capture` (redacting scrape → templates/catalog.json + templates/skills/), grouped a/n/p picker in full init, `sync_stack()` declarative writes, `--sync` skill-body refresh, 63-assertion suite, README/CHANGELOG/components.md/patterns.md docs.
- Review loops caught + fixed: deleted redaction assertion (T2), fixture state leak (T4), **18/27 skills vendored as broken symlinks → cp -rL** (T6 smoke test), YAML quoted/folded description garbling (T6), headers parity in keep_env_refs (final review). Security-review add-on: pairwise argv credential-flag warn heuristic (Test 3b).
- Final whole-branch review: 0 Critical / 0 Important, ready-to-merge; accepted-minors documented in .superpowers/sdd/progress.md.
- Post-ship fix (`a47891b`, verified on brightcat-api): `enabledPlugins` is a RECORD at project level, not an array (docs-research claim was wrong; invalid key = whole settings.json skipped, hooks dead). sync_stack now writes records + migrates array-shaped files. See MISTAKE-009.

### In Progress / Left Off At
- Nothing in flight. active-task.md deleted. Local `stack-catalog` branch kept (delete at will).

### Key Decisions Made
- Scrape-bug repairs need curated-field blanking before re-capture (curation-preservation keeps old non-empty descriptions — by design).
- Vendored-skill supply chain: review `git diff templates/skills/` on every re-capture; provenance manifest recommended but NOT implemented (Karl's call).

### Watch Out For (Next Session)
- Karl follow-ups pending: push main; optional provenance manifest; delete `~/.claude/skills/cloudflare/references/r2-sql/SKILL.md.backup` + re-capture; awk block-scalar blank-line truncation (multi-paragraph descriptions) is a known accepted edge.
- `templates/skills/` is real third-party content (475 files incl. shell scripts) — trust surface for downstream projects.

---

## Session: 2026-07-22 — Stack catalog: design + spec + implementation plan (no code yet)

### Completed
- **Design + spec approved** (`docs/superpowers/specs/2026-07-22-stack-catalog-design.md`): checked-in catalog (`templates/catalog.json`) + `--capture` scrape mode; grouped `[a]/[n]/[p]` picker at init; writes are declarative only — `enabledPlugins`+`extraKnownMarketplaces` into project `.claude/settings.json` (ARRAY format; user-level is object — capture translates), `.mcp.json` (additive), vendored skills into `.claude/skills/`.
- **Implementation plan written** (`docs/superpowers/plans/2026-07-22-stack-catalog.md`): 6 TDD tasks with complete code (capture+redaction → refresh semantics → sync_stack+picker → drill-in/edges/idempotency → --sync skill refresh → real capture+curation+docs). New suite: `tests/catalog-distribution.test.sh`. Branch: `stack-catalog` (plan step 0 commits the spec).
- Verified via docs agent: project settings CAN carry enabledPlugins/extraKnownMarketplaces (Claude Code prompts install); `.mcp.json` supports `${VAR}` expansion; skills auto-load from `.claude/skills/`; **claude.ai connectors are account-bound — not project-configurable** (catalog carries them as doc-only "recommended" list).
- Machine inventory: 3 marketplaces, 31 plugins (30 enabled), 27 personal skills, 1 user MCP (`magic`, has real API key in env — redaction is mandatory).

### In Progress / Left Off At
- Plan saved; execution NOT started. Waiting on user's choice: subagent-driven vs inline execution.
- Spec + plan are uncommitted on `main` (working tree otherwise clean; plan's Task 1 Step 0 creates the branch + commits the spec).

### Blockers
- User input needed: execution approach (subagent-driven recommended vs inline).

### Key Decisions Made
- Three distribution verbs: plugins REFERENCED (settings keys), MCPs DECLARED (.mcp.json), skills VENDORED (copied; no reference mechanism exists).
- No scripted `claude plugin install` — rely on Claude Code's native trust/install prompts.
- `--sync` refreshes vendored skill bodies only; never touches plugin/MCP config (doesn't go stale).
- **Redaction hard rule**: captured MCP env/header values → `${SERVERID_KEY}` placeholders; dedicated test; nothing real ever committed.
- Test seams: `CLAUDE_USER_DIR`, `CLAUDE_USER_CONFIG`, `CLAUDE_STACK_CATALOG`, `CLAUDE_STACK_SKILLS_DIR`.

### Watch Out For (Next Session)
- Plan self-review already fixed: --sync refuses zero-agent projects (Test 8 needs `AGENT_ONE_YES`), picker reads need `|| var=n` EOF tolerance under `set -e`, changelog suite is `tests/changelog-sync.test.sh`.
- Existing suites only drive `--sync` (never interactive init) — shipping the real catalog won't starve their stdin; keep it that way.
- components.md/patterns.md deliberately NOT updated — nothing built yet; plan Task 6 updates them at implementation time.

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
