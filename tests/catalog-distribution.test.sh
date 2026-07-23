#!/usr/bin/env bash
# tests/catalog-distribution.test.sh
# Stack catalog: --capture (scrape/redact/merge), grouped picker, sync_stack
# target writes, and --sync skill-body refresh.
#
# Self-contained — no test framework, no network. Every invocation overrides
# CLAUDE_USER_DIR / CLAUDE_USER_CONFIG / CLAUDE_STACK_CATALOG /
# CLAUDE_STACK_SKILLS_DIR so the real ~/.claude and templates/ are never
# touched. Exits non-zero on first failure; prints PASS on success.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$TEMPLATE_DIR/init-claude-project.sh"

PASS_COUNT=0
fail() { echo ""; echo "✗ FAIL: $1"; exit 1; }
ok()   { echo "  ✓ $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
assert_file() { [[ -f "$1" ]] || fail "expected file missing: $1 — $2"; ok "$2"; }
assert_dir()  { [[ -d "$1" ]] || fail "expected dir missing: $1 — $2"; ok "$2"; }
assert_contains()     { grep -qF -- "$2" "$1" || fail "$1 missing '$2' — $3"; ok "$3"; }
assert_not_contains() { grep -qF -- "$2" "$1" && fail "$1 unexpectedly contains '$2' — $3"; ok "$3"; }
assert_jq() {  # file  jq-expr  expected  message
  local got; got=$(jq -r "$2" "$1") || fail "jq '$2' failed on $1 — $4"
  [[ "$got" == "$3" ]] || fail "$1: jq '$2' = '$got', expected '$3' — $4"
  ok "$4"
}

command -v jq >/dev/null 2>&1 || fail "jq is required to run this suite"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ─── Fixture: a fake user-level Claude config ─────────────────────────────────
# Layout mirrors the real machine: settings.json (object-shaped enabledPlugins,
# one disabled), known_marketplaces.json (with machine-local noise to strip),
# one skill with frontmatter, one MCP server with a secret to redact.
make_user_fixture() {
  local u="$1"
  mkdir -p "$u/skills/fixskill" "$u/skills/quoted-skill" "$u/skills/folded-skill" "$u/skills-store/linked-skill" "$u/plugins"
  cat > "$u/settings.json" <<'EOF'
{"enabledPlugins": {"alpha@market-one": true, "beta@market-one": true, "gamma@market-two": false}}
EOF
  cat > "$u/plugins/known_marketplaces.json" <<'EOF'
{"market-one": {"source": {"source": "github", "repo": "acme/market-one"}, "installLocation": "/home/someone/.claude/plugins/marketplaces/market-one", "lastUpdated": "2026-01-01T00:00:00Z"}}
EOF
  cat > "$u/skills/fixskill/SKILL.md" <<'EOF'
---
name: fixskill
description: A fixture skill for tests.
---
# Fixskill body v1
EOF
  cat > "$u/skills/quoted-skill/SKILL.md" <<'EOF'
---
name: quoted-skill
description: 'A quoted description.'
---
# Quoted-skill body
EOF
  cat > "$u/skills/folded-skill/SKILL.md" <<'EOF'
---
name: folded-skill
description: >-
  A folded description
  spanning two lines.
---
# Folded-skill body
EOF
  cat > "$u/skills-store/linked-skill/SKILL.md" <<'EOF'
---
name: linked-skill
description: A symlinked skill.
---
# Linked-skill body
EOF
  ln -s ../skills-store/linked-skill "$u/skills/linked-skill"
  cat > "$u/user-config.json" <<'EOF'
{"mcpServers": {"fake-server": {"type": "stdio", "command": "npx", "args": ["-y", "fake"], "env": {"API_KEY": "hunter2-super-secret"}}}}
EOF
}

# Run --capture against the fixture with all seams overridden.
run_capture() {  # $1 = user fixture dir, $2 = capture output dir, $3 = stdout file
  CLAUDE_USER_DIR="$1" CLAUDE_USER_CONFIG="$1/user-config.json" \
  CLAUDE_STACK_CATALOG="$2/catalog.json" CLAUDE_STACK_SKILLS_DIR="$2/skills" \
    bash "$INIT" --capture > "$3" 2>&1
}

# ─── 1. Fresh capture ─────────────────────────────────────────────────────────

echo "Test 1: --capture writes a catalog from a fixture user dir"
U="$TMP/userdir"; CAP="$TMP/capture"
make_user_fixture "$U"
mkdir -p "$CAP"
run_capture "$U" "$CAP" "$TMP/cap1.out" || fail "--capture exited non-zero: $(cat "$TMP/cap1.out")"
CAT="$CAP/catalog.json"
assert_file "$CAT" "catalog.json written"
assert_jq "$CAT" '.plugins | length' "2" "only enabled plugins captured (disabled gamma excluded)"
assert_jq "$CAT" '[.plugins[].id] | sort | join(",")' "alpha@market-one,beta@market-one" "plugin ids are name@marketplace strings (object→array translation)"
assert_jq "$CAT" '.plugins[0].group' "ungrouped" "new plugins land in group ungrouped"
assert_jq "$CAT" '.marketplaces["market-one"].source.repo' "acme/market-one" "marketplace source ref kept"
assert_jq "$CAT" '.marketplaces["market-one"] | has("installLocation")' "false" "machine-local marketplace noise stripped"
assert_jq "$CAT" '.skills | length' "4" "skills captured"
assert_jq "$CAT" '.skills[] | select(.id == "fixskill") | .description' "A fixture skill for tests." "plain scalar description scraped from SKILL.md frontmatter"
assert_jq "$CAT" '.skills[] | select(.id == "quoted-skill") | .description' "A quoted description." "single-quoted scalar description has surrounding quotes stripped"
assert_jq "$CAT" '.skills[] | select(.id == "folded-skill") | .description' "A folded description spanning two lines." "folded block scalar description joined into one line"
assert_file "$CAP/skills/fixskill/SKILL.md" "skill body snapshotted into skills dir"
[[ -f "$CAP/skills/linked-skill/SKILL.md" && ! -L "$CAP/skills/linked-skill/SKILL.md" ]] || fail "linked-skill/SKILL.md missing or still a symlink"
[[ ! -L "$CAP/skills/linked-skill" ]] || fail "linked-skill dir itself is a symlink (cp -rL should have dereferenced it)"
ok "symlinked skill vendored as a real file (cp -rL dereferences)"
assert_contains "$CAP/skills/linked-skill/SKILL.md" "Linked-skill body" "symlinked skill body content correct"
assert_jq "$CAT" '.skills[] | select(.id == "linked-skill") | .description' "A symlinked skill." "symlinked skill description captured"
assert_jq "$CAT" '.groups | length' "9" "default group scaffold seeded on first capture"
assert_jq "$CAT" '.mcpServers[0].id' "fake-server" "user-scope MCP server captured"
assert_jq "$CAT" '.mcpServers[0].config.env.API_KEY' '${FAKE_SERVER_API_KEY}' "env value redacted to derived \${SERVERID_KEY} slug on first capture"

# ─── 2. Refresh semantics ─────────────────────────────────────────────────────

echo "Test 2: re-capture preserves curation and keeps missing items"
# Curate: assign alpha a group + description; plant a ghost item not on the
# machine; hand-rename the redacted env reference.
jq '.plugins |= map(if .id == "alpha@market-one"
                    then .group = "core-quality" | .description = "Curated alpha"
                    else . end)
    | .plugins += [{id: "ghost@market-one", group: "core-quality", description: "Gone from machine"}]
    | .mcpServers |= map(.config.env.API_KEY = "${MY_RENAMED_KEY}")
    | .connectors = [{id: "Notion", note: "test connector note"}]' \
  "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"

run_capture "$U" "$CAP" "$TMP/cap2.out" || fail "re-capture exited non-zero: $(cat "$TMP/cap2.out")"
assert_jq "$CAT" '.plugins[] | select(.id == "alpha@market-one") | .group' "core-quality" "curated group survives re-capture"
assert_jq "$CAT" '.plugins[] | select(.id == "alpha@market-one") | .description' "Curated alpha" "curated description survives re-capture"
assert_jq "$CAT" '.plugins[] | select(.id == "ghost@market-one") | .id' "ghost@market-one" "item missing from machine is kept"
assert_contains "$TMP/cap2.out" "ghost@market-one" "missing item is reported in the capture summary"
assert_jq "$CAT" '.mcpServers[0].config.env.API_KEY' '${MY_RENAMED_KEY}' "hand-renamed env reference survives re-capture"
assert_jq "$CAT" '.connectors[0].id' "Notion" "connectors list survives re-capture"
assert_jq "$CAT" '.plugins[] | select(.id == "beta@market-one") | .group' "ungrouped" "uncurated item stays ungrouped"

# ─── 3. Secret redaction ──────────────────────────────────────────────────────

echo "Test 3: captured MCP credentials are redacted"
assert_jq "$CAT" '.mcpServers[0].config.env.API_KEY' '${MY_RENAMED_KEY}' "hand-renamed env reference persisted from test 2"
if grep -r "hunter2" "$CAP" >/dev/null 2>&1; then
  fail "literal secret found somewhere under the capture output dir"
fi
ok "literal secret appears nowhere in the captured output"

echo "Test 3b: credential passed as a separate argv element (no '=') also warns"
U3B="$TMP/userdir3b"
cp -r "$U" "$U3B"
jq '.mcpServers["fake-server"].args = ["-y", "fake", "--api-key", "fake-secret-arg"]' "$U3B/user-config.json" > "$U3B/user-config.json.tmp" && mv "$U3B/user-config.json.tmp" "$U3B/user-config.json"
CAP3B="$TMP/capture3b"
mkdir -p "$CAP3B"
run_capture "$U3B" "$CAP3B" "$TMP/cap3b.out" || fail "fresh capture for Test 3b exited non-zero: $(cat "$TMP/cap3b.out")"
# fake-secret-arg legitimately appears verbatim in this catalog (args are not
# redacted — warn-only by design); the warning presence is the assertion.
# (Not just grepping for "fake-server" — it also shows up in the unrelated
# "ungrouped" warning on a fresh catalog, which would pass without the fix.)
assert_contains "$TMP/cap3b.out" "credential in url/args of: fake-server" "warns on credential passed as a separate --api-key argv element"
assert_jq "$CAT" '.mcpServers[0].config.args | length' "2" "shared fixture args unchanged (isolation)"

# ─── 4. Full init writes the selection into the project ───────────────────────

# The full-init flow prompts: name, type, stack, one y/n per registry agent,
# then one a/n/p per non-empty catalog group. Keep the agent count assertion
# loud so registry growth fails here, not as a silent hang.
AGENT_PROMPTS=$(grep -c '^  "[a-z-]*\.md|' "$INIT")
[[ "$AGENT_PROMPTS" == "10" ]] || fail "AGENT_REGISTRY has $AGENT_PROMPTS entries (expected 10) — update the scripted answers in Tests 4–8"
AGENT_NOES=$'n\nn\nn\nn\nn\nn\nn\nn\nn\nn'
# Test 8 runs --sync on PROJ, and --sync refuses projects with zero agents —
# so PROJ (Tests 4/7/8) installs the first registry agent (senior-dev).
AGENT_ONE_YES=$'y\nn\nn\nn\nn\nn\nn\nn\nn\nn'

run_init() {  # $1 = project dir, $2 = answers, $3 = stdout file
  ( cd "$1" && printf '%s\n' "$2" \
      | CLAUDE_STACK_CATALOG="$CAT" CLAUDE_STACK_SKILLS_DIR="$CAP/skills" \
        bash "$INIT" > "$3" 2>&1 )
}

echo "Test 4: full init writes plugins, MCP servers, and skills into the project"
PROJ="$TMP/proj"
mkdir -p "$PROJ"
# Group prompts for the current catalog: core-quality has items (alpha, ghost)
# → 'a'; ungrouped has items (beta, fixskill, quoted-skill, folded-skill,
# linked-skill, fake-server) → 'a'.
run_init "$PROJ" "proj
api
teststack
$AGENT_ONE_YES
a
a" "$TMP/init4.out" || fail "full init exited non-zero: $(cat "$TMP/init4.out")"

SETTINGS="$PROJ/.claude/settings.json"
assert_file "$SETTINGS" "project settings.json exists"
assert_jq "$SETTINGS" '.enabledPlugins | type' "array" "enabledPlugins is project-level array format"
assert_jq "$SETTINGS" '.enabledPlugins | contains(["alpha@market-one","beta@market-one"])' "true" "selected plugins present"
assert_jq "$SETTINGS" '.extraKnownMarketplaces["market-one"].source.repo' "acme/market-one" "marketplace ref carried for selected plugins"
assert_jq "$SETTINGS" 'has("statusLine")' "true" "autonomy settings not clobbered by stack merge"
MCPJ="$PROJ/.mcp.json"
assert_file "$MCPJ" ".mcp.json created"
assert_jq "$MCPJ" '.mcpServers["fake-server"].env.API_KEY' '${MY_RENAMED_KEY}' "MCP config lands with redacted reference"
assert_file "$PROJ/.claude/skills/fixskill/SKILL.md" "selected skill vendored into project"
assert_contains "$TMP/init4.out" "MY_RENAMED_KEY" "init output lists env vars the user must set"

echo "Test 4b: additive merges preserve existing project entries"
PROJ2="$TMP/proj2"
mkdir -p "$PROJ2/.claude"
echo '{"enabledPlugins": ["keep-me@existing"], "extraKnownMarketplaces": {"market-one": {"source": {"source": "github", "repo": "user/own-fork"}}}}' > "$PROJ2/.claude/settings.json"
echo '{"mcpServers": {"fake-server": {"command": "user-custom"}}}' > "$PROJ2/.mcp.json"
run_init "$PROJ2" "proj2
api
teststack
$AGENT_NOES
a
a" "$TMP/init4b.out" || fail "init on pre-configured project exited non-zero: $(cat "$TMP/init4b.out")"
assert_jq "$PROJ2/.claude/settings.json" '.enabledPlugins | contains(["keep-me@existing"])' "true" "pre-existing plugin entry preserved"
assert_jq "$PROJ2/.claude/settings.json" '.extraKnownMarketplaces["market-one"].source.repo' "user/own-fork" "existing marketplace key never overwritten"
assert_jq "$PROJ2/.mcp.json" '.mcpServers["fake-server"].command' "user-custom" "existing MCP server entry never overwritten"

# ─── 5. Per-item drill-in ─────────────────────────────────────────────────────

echo "Test 5: [p]ick selects individual items only"
PROJ3="$TMP/proj3"
mkdir -p "$PROJ3"
# core-quality prompts first (a/n/p → p), items in catalog order within the
# group: plugins (alpha, ghost) then skills/mcps. Answers: y for alpha, n for
# ghost; then 'n' for the whole ungrouped group.
run_init "$PROJ3" "proj3
api
teststack
$AGENT_NOES
p
y
n
n" "$TMP/init5.out" || fail "drill-in init exited non-zero: $(cat "$TMP/init5.out")"
assert_jq "$PROJ3/.claude/settings.json" '.enabledPlugins | contains(["alpha@market-one"])' "true" "picked item present"
assert_jq "$PROJ3/.claude/settings.json" '.enabledPlugins | contains(["ghost@market-one"])' "false" "declined item absent"
[[ ! -f "$PROJ3/.mcp.json" ]] || fail ".mcp.json written although no MCP selected"
ok "no .mcp.json when no MCP server selected"
[[ ! -d "$PROJ3/.claude/skills/fixskill" ]] || fail "skill vendored although group declined"
ok "no skills vendored when group declined"
assert_contains "$TMP/init5.out" "Notion" "connector recommendation shown for selection"

# ─── 6. Defensive edges ───────────────────────────────────────────────────────

echo "Test 6: object-shaped enabledPlugins in target → warn, skip, continue"
PROJ4="$TMP/proj4"
mkdir -p "$PROJ4/.claude"
echo '{"enabledPlugins": {"user-format@somewhere": true}}' > "$PROJ4/.claude/settings.json"
run_init "$PROJ4" "proj4
api
teststack
$AGENT_NOES
a
a" "$TMP/init6.out" || fail "init exited non-zero on object-shaped enabledPlugins: $(cat "$TMP/init6.out")"
assert_contains "$TMP/init6.out" "object-shaped enabledPlugins" "warning printed"
assert_jq "$PROJ4/.claude/settings.json" '.enabledPlugins | type' "object" "user's object shape untouched"
assert_file "$PROJ4/.claude/skills/fixskill/SKILL.md" "skills still vendored despite plugin-merge skip"
assert_file "$PROJ4/.mcp.json" ".mcp.json still written despite plugin-merge skip"

echo "Test 6b: malformed target settings.json → warn, run completes"
PROJ5="$TMP/proj5"
mkdir -p "$PROJ5/.claude"
echo 'this is not json' > "$PROJ5/.claude/settings.json"
run_init "$PROJ5" "proj5
api
teststack
$AGENT_NOES
a
a" "$TMP/init6b.out" || fail "init exited non-zero on malformed settings.json: $(cat "$TMP/init6b.out")"
assert_contains "$TMP/init6b.out" "not valid JSON" "malformed settings warning printed"
assert_file "$PROJ5/.claude/skills/fixskill/SKILL.md" "run continued past malformed settings"

echo "Test 6c: absent catalog → picker skipped silently, init completes"
PROJ6="$TMP/proj6"
mkdir -p "$PROJ6"
( cd "$PROJ6" && printf '%s\n' "proj6
api
teststack
$AGENT_NOES" \
    | CLAUDE_STACK_CATALOG="$TMP/nonexistent-catalog.json" CLAUDE_STACK_SKILLS_DIR="$TMP/nonexistent-skills" \
      bash "$INIT" > "$TMP/init6c.out" 2>&1 ) || fail "init exited non-zero without a catalog: $(cat "$TMP/init6c.out")"
assert_contains "$TMP/init6c.out" "no stack catalog" "catalog-less init reports the skip"
assert_contains "$TMP/init6c.out" "Setup Complete" "catalog-less init completes"

# ─── 7. Idempotency ───────────────────────────────────────────────────────────

echo "Test 7: re-running init with the same answers changes nothing"
cp "$PROJ/.claude/settings.json" "$TMP/settings.before"
cp "$PROJ/.mcp.json" "$TMP/mcp.before"
run_init "$PROJ" "proj
api
teststack
$AGENT_ONE_YES
a
a" "$TMP/init7.out" || fail "second init run exited non-zero: $(cat "$TMP/init7.out")"
diff <(jq -S . "$TMP/settings.before") <(jq -S . "$PROJ/.claude/settings.json") >/dev/null \
  || fail "settings.json changed on identical re-run"
ok "settings.json unchanged on identical re-run"
diff <(jq -S . "$TMP/mcp.before") <(jq -S . "$PROJ/.mcp.json") >/dev/null \
  || fail ".mcp.json changed on identical re-run"
ok ".mcp.json unchanged on identical re-run"

# ─── 8. --sync refreshes vendored skill bodies ───────────────────────────

echo "Test 8: --sync refreshes template-sourced skills, leaves the rest alone"
# Simulate a template update: bump the snapshot body.
echo "# Fixskill body v2" >> "$CAP/skills/fixskill/SKILL.md"
# A project-local skill with no template source must never be touched.
mkdir -p "$PROJ/.claude/skills/localskill"
printf -- '---\nname: localskill\ndescription: Project-local.\n---\n' > "$PROJ/.claude/skills/localskill/SKILL.md"
cp "$PROJ/.claude/settings.json" "$TMP/settings.presync"
cp "$PROJ/.mcp.json" "$TMP/mcp.presync"

( cd "$PROJ" && CLAUDE_STACK_CATALOG="$CAT" CLAUDE_STACK_SKILLS_DIR="$CAP/skills" \
    bash "$INIT" --sync > "$TMP/sync8.out" 2>&1 ) || fail "--sync exited non-zero: $(cat "$TMP/sync8.out")"

assert_contains "$PROJ/.claude/skills/fixskill/SKILL.md" "Fixskill body v2" "vendored skill body refreshed from template"
assert_contains "$PROJ/.claude/skills/localskill/SKILL.md" "Project-local." "project-local skill untouched"
assert_contains "$TMP/sync8.out" "localskill" "project-local skill reported as left as-is"
diff <(jq -S . "$TMP/settings.presync") <(jq -S . "$PROJ/.claude/settings.json") >/dev/null \
  || fail "--sync modified settings.json (must not touch plugins)"
ok "--sync left settings.json untouched"
diff <(jq -S . "$TMP/mcp.presync") <(jq -S . "$PROJ/.mcp.json") >/dev/null \
  || fail "--sync modified .mcp.json"
ok "--sync left .mcp.json untouched"
[[ ! -d "$PROJ/.claude/skills/ghostskill" ]] || fail "--sync added a skill the project never selected"
ok "--sync added no new skills"

echo ""
echo "PASS — $PASS_COUNT assertions"
