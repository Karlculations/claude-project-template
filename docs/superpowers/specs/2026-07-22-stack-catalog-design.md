# Stack Catalog & Distribution — Design Spec

**Date**: 2026-07-22
**Status**: Approved (design); implementation pending
**Owner**: init-claude-project.sh

## Problem

The template distributes agents, commands, hooks, and knowledge stubs — but nothing about the
*tooling stack* a project should run with: Claude Code plugins, MCP servers, and skills. Today that
stack lives only in user-level config on one machine (`~/.claude/settings.json`,
`~/.claude.json`, `~/.claude/skills/`). A fresh machine, a teammate cloning a project, or a
project wanting a curated subset gets nothing.

## Goals

- A project initialized (or `--sync`ed) from this template declares, in checked-in config, which
  plugins/MCPs/skills it uses — Claude Code's own trust/install flows then guarantee exposure.
- The offerable set is a **checked-in catalog** in the template repo, refreshable from a real
  machine via a new `--capture` mode. Curation (grouping, descriptions) survives refreshes.
- Selection UX: grouped bundles with per-item drill-in (`[a]ll / [n]one / [p]ick`), mirroring the
  spirit of the existing agent picker without 60 serial y/n prompts.

## Non-Goals

- **No vendoring of plugin content.** Plugins are referenced by `name@marketplace`; Claude Code
  installs them. Only skills are vendored (there is no reference mechanism for skills).
- **No claude.ai connector configuration.** Connectors (Gmail, Notion, Calendar, …) are
  account-bound; the catalog carries them as a documentation-only "recommended" list.
- **No scripted `claude plugin install`.** Opening Claude Code in the project triggers native
  trust → install prompts; the script only writes declarative config. (Revisit if the native flow
  proves unreliable.)
- **No automatic removal.** Neither `--capture` nor `--sync` ever deletes catalog entries or
  target-project config.

## Verified Platform Mechanisms (docs, 2026-07)

| Category | Mechanism | User action on open |
|---|---|---|
| Plugins | project `.claude/settings.json`: `enabledPlugins` (array of `"name@marketplace"`) + `extraKnownMarketplaces` (dict keyed by marketplace id, `{"source": {"source": "github", "repo": "owner/repo"}}`) | workspace trust, then prompted install of missing marketplaces/plugins |
| MCP servers | project `.mcp.json` at repo root; `${VAR}` / `${VAR:-default}` expansion in command/args/env/url/headers | per-server approval via `/mcp`; approvals stored in gitignored `settings.local.json` |
| Skills | project `.claude/skills/<name>/SKILL.md` | none beyond workspace trust — auto-discovered |
| claude.ai connectors | none — strictly account-scoped | enable manually in claude.ai account settings |

Format quirk: user-level `enabledPlugins` is an **object** (`{"x@y": true}`); project-level is an
**array**. `--capture` translates (object entries where value is `true` → array members).

## Components

### 1. Catalog — `templates/catalog.json`

Single JSON file (jq is already a hard dependency). Machine-scraped facts + hand-curated fields.

```json
{
  "capturedAt": "2026-07-22",
  "marketplaces": {
    "claude-plugins-official": { "source": { "source": "github", "repo": "anthropics/claude-plugins-official" } }
  },
  "groups": [
    { "id": "core-quality", "name": "Core Quality & Workflow", "description": "Review, commits, TDD, guardrails" }
  ],
  "plugins": [
    { "id": "superpowers@claude-plugins-official", "group": "core-quality", "description": "Process skills: brainstorm, TDD, debugging" }
  ],
  "skills": [
    { "id": "tdd", "group": "core-quality", "description": "Red-green-refactor loop" }
  ],
  "mcpServers": [
    { "id": "magic", "group": "frontend-design", "config": { "command": "npx", "args": ["-y", "@21st-dev/magic"], "env": { "API_KEY": "${MAGIC_API_KEY}" } } }
  ],
  "connectors": [
    { "id": "Notion", "note": "Enable in claude.ai account settings if this project uses Notion docs" }
  ]
}
```

- **Curated fields**: `group`, `description` on every item; the `groups` list itself; `connectors`
  notes. These survive `--capture` refreshes.
- **Scraped fields**: everything else.
- Skill *content* lives in `templates/skills/<name>/` (full directory snapshot); the catalog entry
  is the index/picker record.
- Seed grouping (editable in the catalog, never in the script): core-quality, frontend-design,
  cloudflare, email, backend-data, cms-commerce, diagrams, planning, workflow-extras.

### 2. `--capture` mode (new flag on init-claude-project.sh)

Refreshes the catalog + vendored skills from the current machine. Runs from the template repo
(TEMPLATE_DIR is the write target), so it composes with the existing flags rather than the
init/target flow.

Sources (all overridable for tests via `CLAUDE_USER_DIR`, default `~/.claude`, and
`CLAUDE_USER_CONFIG`, default `~/.claude.json`):

- `$CLAUDE_USER_DIR/settings.json` → `enabledPlugins` object → entries with value `true`
- `$CLAUDE_USER_DIR/plugins/known_marketplaces.json` → marketplace ids + `source` only
  (`installLocation`, `lastUpdated` stripped)
- `$CLAUDE_USER_CONFIG` → top-level `mcpServers` (user scope only; per-project entries ignored)
- `$CLAUDE_USER_DIR/skills/<name>/` → snapshot to `templates/skills/<name>/` (template-owned:
  existing snapshot dirs are replaced wholesale)

Merge semantics against the existing catalog:

- **New item** → appended with `"group": "ungrouped"`; description scraped from SKILL.md
  frontmatter `description:` (skills) or left empty (plugins/MCPs) for hand-editing.
- **Existing item** → scraped facts refreshed; curated `group`/`description` preserved.
- **Item absent from machine** → kept in catalog, listed in a `⚠ not present on this machine`
  report. Removal is a manual edit.
- Output ends with a summary: added / refreshed / missing counts, plus any `ungrouped` items
  needing curation.

**Secret redaction (hard rule)**: every `env` value and every `headers` value in a captured MCP
config is replaced with `${<SERVERID>_<KEYNAME>}` (uppercased, non-alphanumerics → `_`) before
writing. If the existing catalog already has a redacted reference for the same key, that exact
reference is kept. A literal credential must never reach the repo; this rule has a dedicated test.
`url` and `args` are captured verbatim — flagged in the capture summary if they contain
`key=`/`token=`-style substrings so a human can veto (heuristic, warn-only).

### 3. Picker (full init, after agent selection)

For each catalog group with at least one item:

```
── Cloudflare Stack — Workers, Wrangler, DO, email (1 plugin, 8 skills)
   Install? [a]ll / [n]one / [p]ick:
```

- `a` → all items in group selected; `n` → none; `p` → per-item `y/n` with description shown.
- `ungrouped` items are offered last under an "Ungrouped (needs curation)" heading, per-item.
- After selection, if any selected item's group has associated `connectors`, print a closing
  note: "This selection benefits from claude.ai connectors: X, Y — enable them in your account
  settings." Connectors are never prompted for.
- Selection is stored nowhere except the resulting project files — the installed set IS the state,
  exactly like agents (`collect_installed_agents` pattern).

### 4. Target-project writes — `sync_stack()`

New function, called from full init with the picker's selection. (`--sync` runs only the
skill-body refresh — see §5.) Follows the Distribution Ownership rule:

- **`.claude/settings.json`** (user-owned, additive):
  - `enabledPlugins`: created as array if missing; selected ids unioned in (`jq 'unique'`);
    existing entries never removed. If the key exists as an object (user copied user-level
    format), abort the plugin merge for that file with a warning — never rewrite user data shape.
  - `extraKnownMarketplaces`: only marketplaces referenced by selected plugins; each key added
    only when absent; existing keys never modified.
  - Same invalid-JSON tolerance as the hooks merge: unparseable target → warn, skip, don't abort.
- **`.mcp.json`** (user-owned, additive): created if absent; each selected server key added only
  when absent; existing keys never modified. Configs come from the catalog verbatim (already
  redacted); a note lists env vars the user must set (`MAGIC_API_KEY`, …).
- **`.claude/skills/<name>/`** (template-owned bodies): selected skills copied from
  `templates/skills/<name>/`, replacing any prior copy of the same skill.

### 5. `--sync` integration

- New `collect_installed_skills()` + refresh: skills already in the target's `.claude/skills/`
  whose name has a `templates/skills/` source are overwritten from the template (same contract as
  `sync_agent_bodies`); project-local skills untouched; never adds new skills.
- `--sync` does NOT touch `.claude/settings.json` plugins or `.mcp.json`. Those are declarative
  references that don't go stale (Claude Code resolves plugin versions itself). Only vendored
  skill *bodies* can rot, so only they are refreshed. Re-running the picker (full init is already
  re-runnable) is the way to add stack items to an existing project.

### 6. Tests — `tests/catalog-distribution.test.sh`

House style: self-contained bash, `assert_*` helpers, `mktemp -d` fixtures, no network, exercises
the real script. Coverage:

1. `--capture` fresh: fixture `$CLAUDE_USER_DIR` → catalog created; object→array translation;
   marketplace metadata stripped; skill snapshot copied; SKILL.md description scraped.
2. `--capture` refresh: curated group/description preserved; new item → `ungrouped`; missing item
   kept + reported.
3. **Redaction**: fixture MCP config with a fake secret in `env` → catalog contains only
   `${...}` reference; literal never present anywhere in the repo tree after capture.
4. Init writes: settings created correctly when absent; additive union when present; object-shaped
   `enabledPlugins` in target → warn + skip; `.mcp.json` existing key untouched; skills copied.
5. `--sync`: vendored skill body refreshed; project-local skill untouched; no new skills added;
   settings/`.mcp.json` untouched by sync.
6. Idempotency: running init twice with the same picks produces identical files.
7. Malformed target settings.json → warn, continue, exit 0 for the rest of the run.

Picker prompts are driven in tests by piping a scripted answer sequence to stdin.

## Security Notes

- Redaction-at-capture is the single point where a real credential could enter git history; it is
  a hard rule with a dedicated test, not best-effort.
- The design adds zero executable surface to target projects — only declarative config that Claude
  Code's own permission/trust flows act on. All new code runs in the template's init script.
- Env expansion in `.mcp.json` means credentials stay in each user's environment.

## Documentation Updates (same change)

- README: new `--capture` flag, stack picker section, catalog curation guide (how to edit
  groups/descriptions), connector caveat.
- CLAUDE.md template: no protocol changes needed (stack is config, not behavior).
- components.md / patterns.md: register `sync_stack()`/`--capture`; extend the Distribution
  Ownership pattern entry with the skill-vendoring + config-additive rules above.
