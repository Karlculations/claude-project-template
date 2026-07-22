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
  mkdir -p "$u/skills/fixskill" "$u/plugins"
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
assert_jq "$CAT" '.skills | length' "1" "skill captured"
assert_jq "$CAT" '.skills[0].description' "A fixture skill for tests." "skill description scraped from SKILL.md frontmatter"
assert_file "$CAP/skills/fixskill/SKILL.md" "skill body snapshotted into skills dir"
assert_jq "$CAT" '.groups | length' "9" "default group scaffold seeded on first capture"
assert_jq "$CAT" '.mcpServers[0].id' "fake-server" "user-scope MCP server captured"

# ─── 2. (reserved for Task 2: refresh/merge semantics) ────────────────────────

# ─── 3. Secret redaction ──────────────────────────────────────────────────────

echo "Test 3: captured MCP credentials are redacted"
assert_jq "$CAT" '.mcpServers[0].config.env.API_KEY' '${FAKE_SERVER_API_KEY}' "env value replaced with \${SERVERID_KEY} placeholder"
if grep -r "hunter2" "$CAP" >/dev/null 2>&1; then
  fail "literal secret found somewhere under the capture output dir"
fi
ok "literal secret appears nowhere in the captured output"

echo ""
echo "PASS — $PASS_COUNT assertions"
