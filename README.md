# claude-project-template

A scaffolding system for Claude Code that gives it persistent memory, specialized sub-agents, and a self-updating knowledge base — so it stops forgetting what it built, what failed, and how your project works.

Works on new projects and existing ones.

---

## The Problem

Claude Code is powerful, but every session starts from zero. It doesn't remember:

- What components already exist and where they live
- What approaches failed and why
- What architectural and design decisions were made
- Where the last session left off

The result is repeated mistakes, redundant questions, and time wasted re-explaining context that should already be there.

---

## The Solution

This template gives every Claude Code project a structured `.claude/` directory containing a living knowledge base, a set of specialized sub-agents, and enforced behavioral protocols — all wired together so Claude starts every session informed and ends every session with its knowledge updated.

---

## Quick Start

```bash
# 1. Clone this template somewhere accessible
git clone https://github.com/Karlculations/claude-project-template.git

# 2. Navigate to your project root (new or existing)
cd /your/project

# 3. Run the init script
bash /path/to/claude-project-template/init-claude-project.sh

# 4. Open Claude Code — it reads CLAUDE.md automatically on start
claude

# 5. End every session with this before /exit
/end-session
```

---

## File Structure

After running the init script, your project gains:

```
your-project/
├── CLAUDE.md                          ← Master context file, auto-read every session
├── CHANGELOG.md                       ← Public-facing release notes (Keep a Changelog)
├── web/                               ← A sub-project…
│   └── CHANGELOG.md                   ← …gets its own scoped changelog
└── .claude/
    ├── agents/                        ← Sub-agent definitions (install only what you need)
    │   ├── senior-dev.md
    │   ├── qa-engineer.md
    │   └── ...
    ├── commands/
    │   └── end-session.md             ← Slash command: /end-session
    ├── hooks/                         ← Autonomy layer (see below)
    │   ├── statusline.sh              ← Usage sensor + status line display
    │   ├── usage-guard.sh             ← Pauses work near the 5h usage limit
    │   ├── context-guard.sh           ← Forces /end-session before context fills
    │   └── session-compact-brief.sh   ← Re-orients the session after compaction
    ├── autopilot.sh                   ← Unattended wait-for-reset-and-resume runner
    ├── settings.json                  ← Wires the hooks + statusline (merged, never clobbered)
    └── knowledge/
        ├── components.md              ← Registry of every component and module
        ├── mistakes.md                ← Failed attempts, errors, anti-patterns
        ├── patterns.md                ← Project-specific conventions and decisions
        └── session-log.md             ← Rolling log of session summaries
```

All of this commits to git alongside your code. The knowledge base is versioned, portable, and survives machine changes.

---

## How It Works

### CLAUDE.md — The Brain

`CLAUDE.md` sits in your project root and is read by Claude Code automatically at session start. It tells Claude:

- Which knowledge files to read and in what order
- Any existing design docs, specs, or requirement files to read before touching code
- How to handle errors: read fully → form a hypothesis → two attempts → stop and report
- Testing requirements: tests must be written before a feature is marked done, and the full suite must pass after every change
- When and how to update the knowledge base
- Project-specific hard rules that must not be reversed without discussion

**Smart merge behavior:** The init script never blindly overwrites an existing `CLAUDE.md`. It detects what kind of file it finds and handles it accordingly:

| Scenario | What happens |
|---|---|
| No `CLAUDE.md` exists | Created from template with your project info |
| Existing `CLAUDE.md` from a previous init | Surgical update — only script-owned sections are refreshed, your custom content is untouched |
| Handwritten `CLAUDE.md` (no anchors) | Your entire file is preserved, template sections are appended to the bottom |

Re-run the merge anytime with:

```bash
bash init-claude-project.sh --upgrade
```

This is useful after adding new agents — it updates the agent roster in `CLAUDE.md` without touching anything else.

**Pulling template updates into an existing project:** `--upgrade` only refreshes `CLAUDE.md`'s anchored sections. It does **not** re-copy agent file *bodies* or commands — so improvements you make to an agent's instructions in the template won't reach a project that way. Use `--sync` for that:

```bash
bash init-claude-project.sh --sync
```

`--sync` does everything `--upgrade` does, and additionally refreshes the bodies of the agents the project already has, plus its commands, from the template. It iterates over the project's own agent selection, so it never adds agents the project deliberately left out, and it leaves a project-local agent (one with no template source) untouched. It also seeds changelogs (see below). The knowledge base and your custom `CLAUDE.md` content are never modified, and existing changelog content is never rewritten, reordered, or removed — the only change to an existing changelog is inserting a `## [Unreleased]` section if it has none.

---

### The Knowledge Base — Persistent Memory

Four files in `.claude/knowledge/` act as Claude's external memory. Claude reads all four at the start of every session before touching anything.

**`components.md`** — A registry of every component, model, service, utility, and migration in the project. Each entry covers what it does, where it lives, key dependencies, and any non-obvious behavior. This prevents Claude from rebuilding things that already exist.

**`mistakes.md`** — A log of every failed attempt, wrong assumption, and anti-pattern encountered in the project. Each entry includes the context it occurred in, what was tried, and what resolved it (or that it's unresolved). This prevents Claude from repeating errors across sessions.

**`patterns.md`** — Project-specific conventions that Claude would otherwise have to guess at. Not generic best practices — those Claude already knows. This file captures decisions made when there were multiple valid options and you picked one: your API response shape, how errors are handled, naming conventions beyond language defaults, what you deliberately chose not to use. If a pattern exists here, Claude follows it without being asked.

**`session-log.md`** — A rolling log appended at the end of every session. Each entry covers what was completed, what's in progress, any blockers, key decisions made, and what to watch for next session.

---

### Sub-Agents — Specialized Context

Agents live in `.claude/agents/` as markdown files with YAML frontmatter. The init script asks which agents your project needs and only installs those. Each agent:

- Has a `description` field Claude uses to decide when to auto-invoke it
- Reads `CLAUDE.md` and the knowledge base on initialization before doing any work
- Has role-specific behavioral standards, output expectations, and update responsibilities
- Carries a **`## ✅ Non-Negotiables` block** — Must Do / Must Never / Definition of Done — the hard rules it applies on every task, tuned to the tools it actually has

Claude Code delegates to agents automatically based on task context, or you can invoke them explicitly:

> "Use the security-engineer agent to review this auth flow."

<!-- AGENTS_TABLE_START -->
### Available Agents

| Agent | File | Best Used For |
|---|---|---|
| Senior Developer | `senior-dev.md` | Architecture decisions, complex logic, implementation, refactoring |
| QA Engineer | `qa-engineer.md` | Spec compliance verification, design matching, stress testing, acceptance criteria |
| Project Manager | `project-manager.md` | Scope, task breakdown, acceptance criteria definition, requirements |
| Data Analyst | `data-analyst.md` | Query design, data modeling, metrics and reporting |
| UI Designer | `ui-designer.md` | Component layout, UX decisions, design-to-code fidelity, accessibility |
| DevOps | `devops.md` | Infrastructure, CI/CD, deployment, env configuration |
| Security Engineer | `security-engineer.md` | Auth review, secrets exposure, vulnerability checks, OWASP |
| Technical Writer | `technical-writer.md` | READMEs, API docs, inline comments, changelogs |
| Code Reviewer | `code-reviewer.md` | Pre-completion review, pattern consistency, maintainability |
| Performance Engineer | `performance-engineer.md` | Load testing, query profiling, caching, response time, scalability |
<!-- AGENTS_TABLE_END -->

**Agent highlights:**

- **QA Engineer** operates in two phases: first verifies the implementation is 1:1 with specs, designs, and defined acceptance criteria; then stress tests it adversarially. Nothing ships without passing both.
- **Security Engineer** leads with a full secrets exposure check before anything else — grepping the codebase for hardcoded keys, auditing git history for committed `.env` files, checking for credentials leaking into logs or frontend bundles.
- **Project Manager** defines explicit Given/When/Then acceptance criteria before implementation begins. These become the QA agent's compliance checklist — closing the loop between planning and verification.
- **Performance Engineer** sets baseline response time targets, profiles queries for N+1 patterns, and flags features that can't meet load targets before they're marked done.

---

### The Tooling Stack — Plugins, Skills, and MCP Servers

Full init also offers a curated catalog of plugins, skills, and MCP servers — the same kind of tooling you already have installed at the user level — grouped and pickable per project instead of installed everywhere.

- **What it installs, and where.** Selected plugins go into `.claude/settings.json` (`enabledPlugins` + `extraKnownMarketplaces`), selected MCP servers into `.mcp.json`, selected skill bodies are vendored into `.claude/skills/`. All three are additive merges — an existing entry is never rewritten or removed.
- **Nothing is scripted-installed.** The script only writes declarative config. Opening Claude Code in the project afterward triggers its own native trust/install prompts for the plugins and MCP servers you selected.
- **claude.ai connectors are account-level, not project config.** Things like Notion, Gmail, or Google Calendar can't be wired into a project file — the picker only *recommends* enabling them in your claude.ai account settings when they pair with what you picked.
- **Curating the catalog.** `templates/catalog.json` ships pre-curated, but it's just JSON — edit any item's `group` (which picker section it appears under) or `description` (the one-liner shown at pick time) directly. Re-running `--capture` preserves your edits: an item already in the catalog keeps its curated `group`/`description`, only newly-discovered items land in `"ungrouped"`.
- **License note.** Vendored skills under `templates/skills/` are snapshots of locally-installed third-party skills. Check upstream licenses before publishing this template repo publicly.

---

### Existing File Scan — Context From Day One

When you run the init script on a project that already has files, it scans up to 3 levels deep for:

- Markdown, text, and RST files: design docs, specs, wireframes, architecture notes, requirements
- Common documentation folders: `docs/`, `design/`, `specs/`, `requirements/`, `planning/`

Files found are listed in a dedicated section of `CLAUDE.md` with an explicit instruction to read them before touching code. If your project already has a `design/wireframes.md` or `specs/api-contract.md`, Claude reads them from session one without you pointing them out each time.

Excluded from the scan: `node_modules/`, `vendor/`, `.git/`, `.claude/`, `README.md`.

---

### `/end-session` — The Update Trigger

Claude doesn't write to files unprompted. `/end-session` is a slash command that explicitly instructs Claude to update the entire knowledge base before you exit:

1. Update `components.md` with anything created or changed this session
2. Log new errors, failed attempts, and gotchas to `mistakes.md`
3. Record any new patterns or conventions established to `patterns.md`
4. Append a structured summary to `session-log.md`
5. Draft public-facing entries in the `CHANGELOG.md` of each changed scope, and run the deploy-gated release flow (see below)

**This is the most important habit in the system.** Skip it and the knowledge base goes stale within a few sessions. Run it consistently and it becomes genuinely useful — Claude arrives at each new session knowing what exists, what failed, and where things stand.

---

### Changelogs — Public-Facing Release Notes

Alongside the internal `session-log.md`, every project gets a **public, user-facing `CHANGELOG.md`** — release notes written for the people who *use* the software, not the next Claude session. The two are deliberately different voices for the same facts: `session-log.md` says *"refactored export to stream rows to avoid OOM"*; `CHANGELOG.md` says *"CSV export now handles large reports without timing out"*.

It works in two layers, mirroring the rest of the template:

- **Seeding (deterministic, in the script).** Full init and `--sync` auto-detect sub-projects by marker file (`package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `composer.json`, `*.csproj`, `pom.xml`, `build.gradle`, `Gemfile`, `supabase/config.toml`) and create a [Keep a Changelog](https://keepachangelog.com/) scaffold at the **root** and in **every sub-project** (e.g. `web/CHANGELOG.md`). This is **never-replace**: existing changelog content is preserved byte-for-byte — the only additive touch is inserting a `## [Unreleased]` section (above the first version entry, or just below the title if the file has no sections yet) when the file has none.
- **Entries + releases (reasoning, in `/end-session`).** `/end-session` writes user-facing entries under `## [Unreleased]`, grouped `Added / Changed / Fixed / Removed / Deprecated / Security`. The **root** changelog aggregates every change in product language; each sub-project's changelog carries the technical detail.

**Releases are deploy-gated and never automatic.** For each changed sub-project, `/end-session` asks whether you've deployed; only on a *yes* does it propose a SemVer bump (shown as `current → new`), wait for your explicit confirmation, then promote `## [Unreleased]` to a versioned, dated release and write the new version back into the manifest. When one sub-project ships independently, the root records it **scoped** (e.g. `## [web 1.3.0] - 2026-06-29`) while un-shipped changes stay under the shared `## [Unreleased]`. It never commits or tags — you do.

---

### The Autonomy Layer — Self-Aware Sessions

Every initialized project also gets a set of guard hooks (`.claude/hooks/` + `.claude/settings.json`) that make sessions aware of their two hard resource limits — the **context window** and the **subscription usage window** — and react before either one truncates work. Requires `jq`; every guard **fails open** (a guard error can never lock you out).

- **Sensor — `statusline.sh`.** Claude Code pipes official `rate_limits` data (5h/7d percentages + reset times) into the status line on every refresh. The script renders it (`Opus | 5h 42% → 15:00 | 7d 12%`) *and* caches it to a state file the guards read. Check anytime with `.claude/hooks/usage-guard.sh --status`.
- **Usage guard — stop at ≥95%.** A `UserPromptSubmit` hook blocks new prompts once the 5-hour window passes the threshold (default 95%, `CLAUDE_USAGE_THRESHOLD`), telling you the reset time. A `PreToolUse` hook denies expensive tool calls (subagents, web) mid-turn with an instruction Claude *sees*: persist state via `/end-session`, then launch autopilot in the background (unless you asked it to wait, or the task needs your input) so the work self-resumes after the reset with no manual restart. Bypass once with `CLAUDE_AUTONOMY=off`.
- **Context guard — `/end-session` before the window fills.** A `Stop` hook estimates context usage; past the threshold (default 80%, `CLAUDE_CONTEXT_THRESHOLD`) it blocks the stop once per session and instructs Claude to run the `/end-session` knowledge steps immediately — so the knowledge base is written *while the details still exist*, not after compaction ate them.
- **Compaction brief.** A `SessionStart(compact)` hook fires after any compaction and injects a note to re-read `.claude/knowledge/` before continuing. Compaction stops being a memory wipe — the knowledge base is the memory.
- **Session-start brief — fresh sessions pick up where the last one left off.** `/end-session` maintains `.claude/knowledge/active-task.md` while a task is unfinished; a `SessionStart(startup|clear)` hook injects it into every new session with an instruction to continue immediately. After a `/clear` or a restart, your first message — even just "go" — resumes the task; you never re-explain it. The marker is deleted when the task completes, so clean projects start silent.
- **Autopilot — auto-resume after reset.** `.claude/autopilot.sh "task"` runs the task headless in turns: it checks the usage window before each turn, sleeps until the *known* reset time when the threshold is hit, then continues the same session (`claude -p --continue`), re-orienting from `session-log.md`. It never evades limits — it stops early and waits. Headless runs have no statusline, so it falls back to the same usage endpoint Claude Code itself queries.

The result: a session that saves its own memory before running out of context, refuses to burn the last 5% of a usage window mid-task, and picks itself back up when the window resets.

---

## Script Reference

| Command | What it does |
|---|---|
| `bash init-claude-project.sh` | Full init or smart upgrade on the current directory |
| `bash init-claude-project.sh --upgrade` | Re-run the CLAUDE.md merge only (useful after adding agents) |
| `bash init-claude-project.sh --sync` | Pull template updates into an existing project: refresh agent bodies + commands + autonomy hooks + CLAUDE.md, and seed root + sub-project changelogs (knowledge base untouched; existing changelog content never rewritten; settings.json merged, never clobbered) |
| `.claude/autopilot.sh "task" [max_turns]` | Unattended runner: works in turns, pauses at the usage threshold, resumes after the window resets |
| `bash init-claude-project.sh --update-readme` | Rebuild the agents table in README.md from the registry |
| `bash init-claude-project.sh --capture` | Refresh `templates/catalog.json` + `templates/skills/` from this machine |

---

## Adding Your Own Agents

1. Create `.claude/agents/your-agent-name.md` using this structure:

```markdown
---
name: your-agent-name
description: When to invoke this agent — be specific, Claude uses this to auto-delegate.
tools: read, write, edit, bash
---

# Agent Name

## Initialization (Run Every Time)
1. Read `CLAUDE.md`
2. Read `.claude/knowledge/components.md`
3. Read `.claude/knowledge/mistakes.md`

## Role
What this agent is responsible for and how it thinks.

## ✅ Non-Negotiables
The hard rules this agent applies on every task. Keep them honest to the agent's tools — don't promise a check the agent can't run (a read-only reviewer can't "run tests"; a writer with no shell can't "execute examples").

**Must Do** — the handful of things this role always does (read before changing, show evidence before claiming done, stay in its lane).
**Must Never** — the lines it must not cross (no skipped failing tests, no committed secrets, no irreversible change without a rollback).
**Definition of Done** — the checklist that must be true before the agent hands work back.

## Standards
Specific behavioral rules, checklists, and output expectations for this role.

## After Completing Work
What this agent must update in the knowledge base before finishing.
```

2. Add one line to `AGENT_REGISTRY` in `init-claude-project.sh`:

```bash
"your-agent-name.md|Display Name|Short description for the table"
```

3. Regenerate the README agents table:

```bash
bash init-claude-project.sh --update-readme
```

---

## What Goes in `patterns.md`

This is the most underused file in the system and the most valuable over time. It captures decisions specific to *this project* that Claude would otherwise guess at or rediscover each session.

Good entries for `patterns.md`:

- **API response shape** — if all responses use `{ data: {}, meta: {}, error: null }`, Claude won't return raw objects on the next endpoint
- **Error handling approach** — global handler vs. per-controller, whichever was decided
- **Auth pattern** — middleware on routes vs. policy classes vs. manual checks
- **Naming conventions** — beyond language defaults, anything project-specific
- **What you chose NOT to use** — "No Redux, we use Zustand" or "No Eloquent global scopes, they caused hidden bugs in session 3"
- **ORM patterns** — repository pattern, query builder vs. ORM, eager loading conventions

After any session where you make a decision you'd have to re-explain to a new developer, that explanation belongs in `patterns.md`.

---

## What This Is Not

- **Not machine learning.** Claude doesn't learn in the training sense. What looks like learning is structured context injection — well-maintained markdown files loaded at session start. The quality of the system depends on the quality of those files.
- **Not automatic.** `/end-session` must be run. Claude will not reliably update knowledge files without being explicitly instructed to. If you skip it, the system degrades.
- **Not a replacement for good specs.** The QA agent's compliance checks are only as strong as your spec and design files. Vague requirements produce vague verification.
- **Not a system prompt.** System prompts hit context limits fast and don't update themselves. This approach keeps context lean (Claude reads what it needs) and grows richer over time as knowledge files fill in.

---

## Git Setup

Commit `.claude/` to version control:

```bash
git add .claude/ CLAUDE.md
git commit -m "chore: add Claude project structure"
```

The knowledge base is most useful when versioned — if a pattern in `mistakes.md` turns out to be wrong, `git diff` shows you when it changed. If you want to keep knowledge files private (sensitive architecture notes, internal context), add them to `.gitignore`:

```
.claude/knowledge/
```

---

## Works With Any Stack

This template is stack-agnostic. The agent files reference stack-specific tooling (e.g. `php artisan`, `npm audit`, `composer audit`) but these are illustrative — each agent's behavior adapts to whatever stack is defined in `CLAUDE.md`. It has been used with:

Laravel · Next.js · React · Vue · Django · FastAPI · Node/Express · PostgreSQL · MySQL · Docker · AWS · Supabase · and others

---

## Contributing

Stack-specific agent variants, new agent roles, and knowledge base templates for specific domains are welcome. Open a PR with:

- The agent or template file(s)
- A short description of what problem it solves and what type of project it suits
- Any stack-specific tooling commands it relies on

---

## License

MIT
