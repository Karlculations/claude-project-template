# Design: Public-Facing Changelogs

**Date:** 2026-06-29
**Status:** Implemented (2026-06-29) — see §10 for refinements made during build + adversarial review
**Scope:** Add `CHANGELOG.md` generation + maintenance to the claude-project-template, at the repo root and in every detected sub-project, driven by the existing `--sync` (seeding) and `/end-session` (content) machinery.

---

## 1. Goal

Give every project initialized from this template a **public-facing, user-friendly changelog** — release notes, bug fixes, and notable changes written for end users — as a sibling to the existing internal `session-log.md`.

- A `CHANGELOG.md` exists at the **repo root** (aggregate, product-wide) and in **every sub-project** (e.g. a React `web/` folder, a `supabase/` folder), each tailored to its scope.
- `/end-session` writes the entries (reasoning layer).
- `init-claude-project.sh --sync` (and full init) seeds the scaffolds (deterministic layer) and **never replaces** an existing changelog — only merges additively.

### Contrast with `session-log.md`

| | `session-log.md` | `CHANGELOG.md` |
|---|---|---|
| Audience | Internal / the next Claude session | Public / end users |
| Voice | Dev notes, blockers, "watch out for" | Plain product language |
| Example | "refactored export to stream rows to avoid OOM" | "CSV export now handles large reports without timing out" |
| Trigger | `/end-session` | `/end-session` (same command, new step) |

---

## 2. Decisions (locked during brainstorming)

1. **Format:** Keep a Changelog (keepachangelog.com) — `## [Unreleased]` on top, then versioned releases, each grouped by `### Added / Changed / Fixed / Removed / Deprecated / Security`. Adheres to SemVer.
2. **Sub-project detection:** Auto-detect by marker files. No config list.
3. **Root scope:** Root aggregates everything — every notable change appears in the root changelog (product language) and in its sub-project's changelog (more technical detail).
4. **Release model:** Entries land under `## [Unreleased]`. Promotion to a versioned release is gated on a real-world deploy + explicit human confirmation, asked **per changed sub-project**.
5. **Never-replace variant:** Seeding creates a changelog when missing and preserves an existing one completely; the only additive touch is inserting an empty `## [Unreleased]` at the top **if the file has none**.
6. **Root versioning under independent releases:** When only one sub-project ships, the root records the release **scoped** — `## [web 1.3.0] - 2026-06-29` — while un-shipped entries stay under the shared `## [Unreleased]`. If the repo root has its own version source and the user is cutting a unified product release, root uses a plain `## [1.3.0] - 2026-06-29` instead.

---

## 3. Architecture: two layers (mirrors existing template split)

The template already separates a **deterministic layer** (`init-claude-project.sh`) from a **reasoning layer** (`/end-session`). The changelog feature splits the same way.

| Concern | Lives in | Behavior |
|---|---|---|
| Detect sub-projects + seed empty scaffolds | `init-claude-project.sh` (`--sync` + full init) | Find marker files; create `CHANGELOG.md` where missing; never overwrite an existing one |
| Write entries + run the release flow | `.claude/commands/end-session.md` (Claude) | Draft user-facing entries under `[Unreleased]`; ask the deploy question; do version bumps |

Because `--sync` already re-copies all command files via `sync_commands()`, the new end-session logic propagates to existing projects through the sync the user already runs. No new propagation mechanism is needed.

---

## 4. Component 1 — `init-claude-project.sh` (seeding layer)

### 4.1 New constant: marker files

A directory (below root) is a **sub-project** if it directly contains any of:

```
package.json   supabase/config.toml   Cargo.toml   go.mod
pyproject.toml   composer.json   *.csproj   pom.xml   build.gradle   Gemfile
```

One folder = one sub-project even if it holds several markers (dedupe by folder).

### 4.2 New function `changelog_scaffold <scope_label>`

Emits the Keep a Changelog scaffold. Root uses `# Changelog`; a sub-project uses `# Changelog — <scope_label>` plus a one-line note that it tracks changes to that part of the project.

Root scaffold:

```markdown
# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
```

Sub-project scaffold (e.g. `web`):

```markdown
# Changelog — web

Changes to the `web` part of this project.
The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
```

### 4.3 New function `detect_subprojects <target>`

Echoes a newline-separated list of relative sub-project directories.

- `find` to `maxdepth 3`, excluding `node_modules/`, `vendor/`, `.git/`, `.claude/`, and common build dirs — the same exclusion philosophy as `build_existing_files_block()`.
- Map each found marker to its containing directory; dedupe; exclude the root directory itself (root is handled separately).

### 4.4 New function `seed_changelogs <target>`

For the root **and** each detected sub-project directory:

- **Missing `CHANGELOG.md`** → write `changelog_scaffold` for that scope. Report `✓ created CHANGELOG.md (<scope>)`.
- **Existing `CHANGELOG.md`** → preserve every byte of existing content. If it contains no `## [Unreleased]` line anywhere, insert an empty `## [Unreleased]` heading at the top — above the first existing `## ` section (or at end of the header block if there are no `## ` sections). Report `↷ CHANGELOG.md exists (<scope>) — left intact` or `+ added [Unreleased] section (<scope>)`.

Implementation note for the additive insert: guard with `grep -q '## \[Unreleased\]'`; when absent, use `awk` to print the empty `## [Unreleased]` block immediately before the first line matching `^## ` (a version heading). Existing entries are never rewritten, reordered, or removed.

### 4.5 Wiring

- Call `seed_changelogs "$TARGET_DIR"` inside the **`--sync`** block (after `sync_commands`, alongside the CLAUDE.md merge) and in **full init** (after the knowledge base is initialized).
- **Not** added to `--upgrade` (which stays CLAUDE.md-only).
- Update the script's usage header, the `--sync` console output, and the full-init "Next steps" / "Useful commands" footer to mention changelog seeding.

---

## 5. Component 2 — `.claude/commands/end-session.md` (content layer)

Insert a new **Step 5: Update CHANGELOG(s)** before the final confirm (current Step 5 "Confirm" becomes Step 6). The step instructs Claude to:

### 5.1 Identify changed scopes

From the session's work and `git status`, determine which scopes changed: the **root** plus any **sub-project** folders (a folder containing a marker file from §4.1). Map each changed path to its nearest enclosing sub-project, or to root.

### 5.2 Ensure changelogs exist

For each changed scope, if its `CHANGELOG.md` is missing (e.g. the project never ran `--sync`), create it from the scaffold described in §4.2 so end-session is self-sufficient.

### 5.3 Draft entries under `## [Unreleased]`

- Group under `### Added / Changed / Fixed / Removed / Deprecated / Security`.
- **Public/user-facing voice** — plain language describing user-visible impact, explicitly contrasted with the internal `session-log.md` (include the worked example from §1).
- **Aggregation:** every entry also goes to the **root** changelog (product language); the sub-project changelog carries the more technical detail. (Realizes "root aggregates everything.")
- Do not log internal-only churn (refactors with no user-visible effect, knowledge-base updates) to the changelog.

### 5.4 Release flow — asked per changed sub-project

For each changed sub-project (and root, per §5.5):

1. Ask: `<scope> — deployed, or deploying right after this? (y/n)`
2. **If yes:**
   - Read the current version from the scope's manifest (table below).
   - Propose a SemVer bump from the change types just written: **major** if any `Removed` or breaking `Changed`; **minor** if any `Added`; **patch** if only `Fixed` / `Security` / `Deprecated`.
   - Show **`current → new`** (e.g. `1.2.0 → 1.3.0`) and **wait for explicit confirmation or an override** — never auto-apply.
   - On confirm: promote `## [Unreleased]` → `## [<new>] - <YYYY-MM-DD>`, open a fresh empty `## [Unreleased]` on top, **and write the new version back into the manifest**.
   - **No version source** (e.g. supabase, go.mod): promote to a dated `## [<YYYY-MM-DD>]` heading, or let the user type an explicit version.
3. **If no:** entries stay under `## [Unreleased]`.

Version source per stack:

| Marker | Version field |
|---|---|
| `package.json` | `.version` |
| `Cargo.toml` | `[package] version` |
| `pyproject.toml` | `[project] version` or `[tool.poetry] version` |
| `composer.json` | `.version` (often absent → treat as versionless) |
| `*.csproj` | `<Version>` |
| `pom.xml` | `<version>` |
| `build.gradle` | `version` |
| `Gemfile` / `*.gemspec` | `.version` (gemspec) |
| `supabase/config.toml`, `go.mod` | none → date heading |

### 5.5 Root changelog promotion

- When a sub-project releases, the **root** records that release **scoped**: `## [web 1.3.0] - <date>` for the entries belonging to that sub-project, while entries from un-released scopes stay under the root's shared `## [Unreleased]`.
- If the **repo root has its own version source** and the user is cutting a unified product release across scopes, root uses a plain `## [<new>] - <date>` instead and writes back the root manifest.

### 5.6 End-of-command reminder

After the flow, print a reminder listing every scope still holding unreleased changes:

> ⚠ Unreleased changes remain in: `root`, `supabase` — promote them to a version when you deploy.

### 5.7 Scope of file edits

end-session only **edits files** (manifests + changelogs) — it never `git commit`s or `git tag`s, consistent with how it already treats the knowledge base. The user commits.

### 5.8 Confirm message

Update Step 6's confirm line to include changelog activity, e.g.:
"Session knowledge updated. [N] components updated, [N] mistakes logged, [N] patterns added. Changelog: [N] scopes updated, [N] released, [N] left unreleased."

---

## 6. Component 3 — README.md

- **File-structure tree:** add `CHANGELOG.md` at root and note per-sub-project changelogs.
- **New subsection** under "How It Works": *"Changelogs — Public-Facing Release Notes"* — explains seeding via `--sync`/init, the `[Unreleased]` model, deploy-gated per-sub-project promotion, root aggregation, and the never-replace guarantee.
- **Script Reference table:** update the `--sync` row to mention it also seeds/refreshes changelogs.
- **`/end-session` section:** add the changelog step to the numbered list.

---

## 7. Component 4 — Smoke test (`tests/changelog-sync.test.sh`, new `tests/` dir)

Self-contained bash test (no framework). It:

1. Creates a temp project dir with: a minimal `.claude/agents/senior-dev.md` (so `--sync` passes its agent guard with a real template-sourced agent), `web/package.json`, and `supabase/config.toml`.
2. Runs `bash <template>/init-claude-project.sh --sync` from inside the temp dir.
3. Asserts:
   - `CHANGELOG.md` exists at root, contains `# Changelog` and `## [Unreleased]`.
   - `web/CHANGELOG.md` exists, header `# Changelog — web`.
   - `supabase/CHANGELOG.md` exists, header `# Changelog — supabase`.
4. **Never-replace:** writes a sentinel comment into `web/CHANGELOG.md`, re-runs `--sync`, asserts the sentinel still present and not duplicated.
5. **Additive `[Unreleased]`:** overwrites `web/CHANGELOG.md` with a Keep-a-Changelog-less file (`# Changelog` + an old `## 2025-01-01` entry, no `[Unreleased]`), re-runs `--sync`, asserts `## [Unreleased]` now present **and** the old entry preserved.
6. Exits non-zero with a clear message on any failed assertion; prints `PASS` on success.

---

## 8. Non-goals / out of scope

- No automatic `git commit` or `git tag` (the user commits).
- No CI/release-automation integration.
- `--upgrade` behavior is unchanged (CLAUDE.md-only).
- Sub-projects nested deeper than `maxdepth 3` are not auto-seeded by the script; `/end-session` can still create a changelog for them on demand.
- No attempt to changelog dependencies (`node_modules/`, `vendor/`).

---

## 9. Risks / mitigations

- **Format drift** between the script's scaffold and end-session's entry guidance → mitigate by keeping responsibilities disjoint: the script only seeds the *empty* scaffold; end-session only describes how to *write entries*.
- **Destructive merge** on an existing changelog → mitigated by the never-replace contract (§4.4) and the dedicated smoke-test assertions (§7.4, §7.5).
- **Wrong version bump** → mitigated by mandatory human confirmation of `current → new` before any promotion or manifest write (§5.4).

---

## 10. Implementation refinements (post-build adversarial review)

A 5-lens adversarial review of the built feature surfaced edge cases that hardened the implementation beyond the literal design. The behavior contracts above stand; these are the precise mechanics:

1. **One matcher decides "has Unreleased?" for both the guard and the insert.** §4.4 originally prescribed `grep -q '## [Unreleased]'`. That exact/case-sensitive/bracketed test disagreed with the looser awk insert trigger (`/^## /`), so a real-world `## Unreleased` (no brackets), `## [unreleased]` (lowercase), or an indented heading slipped past the guard *and* got a second empty `## [Unreleased]` inserted above it — orphaning entries. Replaced by a shared `has_unreleased()` helper: case-insensitive, optional brackets, optional leading space, and **fence-aware**. The guard and the insert can no longer disagree.
2. **Insertion is code-fence-aware.** A `## …` line inside a ```/~~~ fenced block (e.g. a changelog documenting its own format) is no longer treated as the first heading; `## [Unreleased]` is placed before the first *real* heading.
3. **No-heading files get `[Unreleased]` near the top, not at EOF.** For a prose-only changelog, the section is inserted just after the title/intro block (first blank line) — realizing §4.4's "at end of the header block", not literally end-of-file.
4. **Sub-project detection runs from inside the target** (relative paths) so an *ancestor* directory named `build`/`dist`/`node_modules`/`vendor`/`.git` can't match the exclusion globs and silently drop every sub-project. The supabase marker branch gained the same `dist`/`build` exclusions as the others.
5. **Atomic scaffold writes.** New changelogs are written via `> "$file.tmp" && mv`, matching `insert_unreleased`, so an interrupted write can't leave a truncated file.

All five are covered by assertions in `tests/changelog-sync.test.sh` (Tests 4–9), alongside a byte-for-byte preservation check and full-init coverage.
