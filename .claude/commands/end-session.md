# End Session — Knowledge Base Update

Run this before `/exit` to persist session knowledge.

## Instructions for Claude

You are closing a work session. Complete the following steps in order. Do not skip any.

### Step 1: Update `components.md`

Review everything created, modified, or deleted this session.
For each component/module touched, ensure `.claude/knowledge/components.md` has an up-to-date entry covering:
- What it does
- Where it lives in the codebase
- Key dependencies
- Any important usage notes or caveats discovered this session

### Step 2: Update `mistakes.md`

Review every error, failed attempt, or wrong assumption that occurred this session.
For each one, add or update an entry in `.claude/knowledge/mistakes.md` with:
- The error or wrong assumption
- The context it occurred in
- What was tried that failed
- What actually resolved it (or that it is still unresolved)

### Step 3: Update `patterns.md`

If any new approach, convention, or architectural decision was established this session that should be repeated in the future, add it to `.claude/knowledge/patterns.md`.

### Step 4: Append to `session-log.md`

Add a new entry at the top of `.claude/knowledge/session-log.md` using this format:

```
## Session: [DATE] — [ONE LINE SUMMARY]

### Completed
- [list of things finished]

### In Progress / Left Off At
- [anything partially done]

### Blockers
- [anything that was stuck or needs user input]

### Key Decisions Made
- [architectural or product decisions]

### Watch Out For (Next Session)
- [anything that tripped us up, or needs attention next time]
```

**Also maintain `.claude/knowledge/active-task.md`** — the auto-resume marker a `SessionStart` hook injects into every fresh session:
- **Task unfinished** (anything real under "In Progress / Left Off At" or "Blockers"): overwrite the file with — the task in one line, the exact next step, how to verify done, and whether it is blocked on user input (a blocked marker makes the next session ask instead of act).
- **Task fully complete**: delete the file so fresh sessions start clean.

### Step 5: Update CHANGELOG(s)

`session-log.md` (Step 4) is for the *next Claude session* — dev notes, blockers, "watch out for". The **`CHANGELOG.md`** is the opposite audience: **public, end-user-facing release notes**. Same facts, different voice.

| | `session-log.md` | `CHANGELOG.md` |
|---|---|---|
| Audience | Internal / next session | Public / end users |
| Voice | "refactored export to stream rows to avoid OOM" | "CSV export now handles large reports without timing out" |

**5.1 — Identify changed scopes.** From this session's work and `git status`, list which scopes changed: the **root**, plus any **sub-project** folder (a directory directly containing a marker file: `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `composer.json`, `*.csproj`, `pom.xml`, `build.gradle`, `Gemfile`, or `supabase/config.toml`). Map each changed path to its nearest enclosing sub-project, or to root.

**5.2 — Ensure a changelog exists for each changed scope.** If a scope's `CHANGELOG.md` is missing (e.g. the project never ran `--sync`), create it first so this command is self-sufficient. Use the Keep a Changelog scaffold — `# Changelog` (root) or `# Changelog — <scope>` (sub-project), a one-line note, the Keep a Changelog + SemVer links, then `## [Unreleased]`.

**5.3 — Draft entries under `## [Unreleased]`.**
- Group under `### Added` / `### Changed` / `### Fixed` / `### Removed` / `### Deprecated` / `### Security`.
- **Public voice** — describe the user-visible impact in plain language (see the table above). Do **not** copy dev notes verbatim.
- **Aggregate to root.** Every user-facing entry also goes in the **root** changelog (product language); the sub-project's changelog carries the more technical detail.
- **Skip internal-only churn** — refactors with no user-visible effect, knowledge-base updates, test-only changes. If nothing user-facing changed in a scope, write nothing for it.

**5.4 — Release flow, asked per changed sub-project (and root, per 5.5).**

> **Headless/unattended runs (autopilot, `claude -p`):** there is no user to answer — skip the questions below entirely and leave all entries under `## [Unreleased]`. Never invent a y/n answer or bump a version unattended.

1. Ask: `<scope> — deployed, or deploying right after this? (y/n)`
2. **If yes:**
   - Read the current version from the scope's manifest:

     | Marker | Version field |
     |---|---|
     | `package.json` | `.version` |
     | `Cargo.toml` | `[package] version` |
     | `pyproject.toml` | `[project] version` or `[tool.poetry] version` |
     | `composer.json` | `.version` (often absent → treat as versionless) |
     | `*.csproj` | `<Version>` |
     | `pom.xml` | `<version>` |
     | `build.gradle` | `version` |
     | `*.gemspec` | `.version` |
     | `supabase/config.toml`, `go.mod` | none → use a dated heading |

   - Propose a SemVer bump from the change types just written: **major** if any `Removed` or breaking `Changed`; **minor** if any `Added`; **patch** if only `Fixed` / `Security` / `Deprecated`.
   - Show **`current → new`** (e.g. `1.2.0 → 1.3.0`) and **wait for explicit confirmation or an override**. Never auto-apply a version.
   - On confirm: rename `## [Unreleased]` → `## [<new>] - <YYYY-MM-DD>`, add a fresh empty `## [Unreleased]` on top, **and write the new version back into the manifest**.
   - **No version source** (supabase, go.mod): promote to a dated `## [<YYYY-MM-DD>]` heading, or let the user type an explicit version.
3. **If no:** leave the entries under `## [Unreleased]`.

**5.5 — Root promotion.** When a sub-project releases, the **root** records that release **scoped**: `## [<scope> <new>] - <date>` (e.g. `## [web 1.3.0] - 2026-06-29`) for that sub-project's entries, while entries from un-released scopes stay under the root's shared `## [Unreleased]`. If the **repo root has its own version source** and the user is cutting a unified product release, use a plain `## [<new>] - <date>` and write back the root manifest instead.

**5.6 — Scope of edits.** Only **edit files** (changelogs + manifests). Never `git commit` or `git tag` — the user commits, exactly as with the knowledge base.

**5.7 — Unreleased reminder.** After the flow, list every scope still holding unreleased changes, e.g.:

> ⚠ Unreleased changes remain in: `root`, `supabase` — promote them to a version when you deploy.

### Step 6: Confirm

Report back: "Session knowledge updated. [N] components updated, [N] mistakes logged, [N] patterns added. Changelog: [N] scopes updated, [N] released, [N] left unreleased."
