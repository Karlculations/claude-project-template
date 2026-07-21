#!/usr/bin/env bash
# tests/changelog-sync.test.sh
# Smoke test for CHANGELOG.md seeding by init-claude-project.sh.
#
# Self-contained — no test framework. Spins up a throwaway project in a temp
# dir, runs `--sync`, and asserts the seeding contract from the design spec
# (docs/superpowers/specs/2026-06-29-changelog-design.md §7):
#   1. Root + per-sub-project changelogs are created with the right headers.
#   2. Never-replace: an existing changelog is preserved byte-for-byte (no dupes).
#   3. Additive: a changelog lacking `## [Unreleased]` gets one inserted on top,
#      while every existing entry survives.
#
# Exits non-zero on the first failed assertion; prints PASS on success.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$TEMPLATE_DIR/init-claude-project.sh"

PASS_COUNT=0

fail() {
  echo ""
  echo "✗ FAIL: $1"
  exit 1
}

assert_file() {
  # assert_file <path> <description>
  [[ -f "$1" ]] || fail "expected file missing: $1 — $2"
  echo "  ✓ $2"
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_contains() {
  # assert_contains <file> <fixed-string> <description>
  grep -qF -- "$2" "$1" || fail "$1 missing expected text '$2' — $3"
  echo "  ✓ $3"
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_count() {
  # assert_count <file> <fixed-string> <expected-n> <description>
  local n
  n=$(grep -cF -- "$2" "$1" || true)
  [[ "$n" == "$3" ]] || fail "$1: expected $3 occurrence(s) of '$2', got $n — $4"
  echo "  ✓ $4"
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_before() {
  # assert_before <file> <fixed-string-A> <fixed-string-B> <description>
  # Asserts A appears on an earlier line than B.
  local a b
  a=$(grep -nF -- "$2" "$1" | head -1 | cut -d: -f1)
  b=$(grep -nF -- "$3" "$1" | head -1 | cut -d: -f1)
  [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]] \
    || fail "$1: expected '$2' (line ${a:-?}) before '$3' (line ${b:-?}) — $4"
  echo "  ✓ $4"
  PASS_COUNT=$((PASS_COUNT + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_sync() {
  # Run --sync from inside the temp project; fail loudly if the script crashes,
  # so a seeding-assertion failure is never confused with a broken --sync.
  if ! ( cd "$TMP" && bash "$INIT" --sync ) > "$TMP/.sync.out" 2>&1; then
    echo "----- --sync output -----"
    cat "$TMP/.sync.out"
    echo "-------------------------"
    fail "init-claude-project.sh --sync exited non-zero"
  fi
}

# ─── Fixture ──────────────────────────────────────────────────────────────────
# Minimal project: one real template-sourced agent (so --sync's agent guard
# passes), plus two sub-projects detected by marker files.
mkdir -p "$TMP/.claude/agents"
cp "$TEMPLATE_DIR/.claude/agents/senior-dev.md" "$TMP/.claude/agents/senior-dev.md"

mkdir -p "$TMP/web"
printf '{\n  "name": "web",\n  "version": "1.0.0"\n}\n' > "$TMP/web/package.json"

mkdir -p "$TMP/supabase"
printf 'project_id = "demo"\n' > "$TMP/supabase/config.toml"

echo "Running changelog-sync smoke test in: $TMP"
echo ""

# ─── Test 1: seeding ──────────────────────────────────────────────────────────
echo "Test 1 — seeds changelogs at root and every sub-project"
run_sync
assert_file     "$TMP/CHANGELOG.md"          "root CHANGELOG.md created"
assert_contains "$TMP/CHANGELOG.md"          "# Changelog"          "root has '# Changelog' header"
assert_contains "$TMP/CHANGELOG.md"          "## [Unreleased]"      "root has [Unreleased] section"
assert_file     "$TMP/web/CHANGELOG.md"      "web/CHANGELOG.md created"
assert_contains "$TMP/web/CHANGELOG.md"      "# Changelog — web"    "web has scoped header"
assert_contains "$TMP/web/CHANGELOG.md"      "## [Unreleased]"      "web has [Unreleased] section"
assert_file     "$TMP/supabase/CHANGELOG.md" "supabase/CHANGELOG.md created"
assert_contains "$TMP/supabase/CHANGELOG.md" "# Changelog — supabase" "supabase has scoped header"
assert_contains "$TMP/supabase/CHANGELOG.md" "## [Unreleased]"      "supabase has [Unreleased] section"
echo ""

# ─── Test 2: never-replace + no duplication ───────────────────────────────────
echo "Test 2 — preserves an existing changelog and never duplicates sections"
SENTINEL="<!-- SENTINEL-DO-NOT-DELETE -->"
printf '%s\n' "$SENTINEL" >> "$TMP/web/CHANGELOG.md"
before=$(cksum < "$TMP/web/CHANGELOG.md")
run_sync
after=$(cksum < "$TMP/web/CHANGELOG.md")
[[ "$before" == "$after" ]] || fail "existing changelog was modified by re-sync — not byte-for-byte preserved"
echo "  ✓ existing changelog preserved byte-for-byte"
PASS_COUNT=$((PASS_COUNT + 1))
assert_contains "$TMP/web/CHANGELOG.md" "$SENTINEL"        "sentinel preserved across re-sync"
assert_count    "$TMP/web/CHANGELOG.md" "$SENTINEL"    "1" "sentinel not duplicated"
assert_count    "$TMP/web/CHANGELOG.md" "## [Unreleased]" "1" "[Unreleased] not duplicated on re-sync"
echo ""

# ─── Test 3: additive [Unreleased] on a Keep-a-Changelog-less file ────────────
echo "Test 3 — inserts [Unreleased] when missing, preserving existing entries"
cat > "$TMP/web/CHANGELOG.md" <<'EOF'
# Changelog — web

Some hand-written preamble.

## 2025-01-01
- Old entry that must survive
EOF
run_sync
assert_contains "$TMP/web/CHANGELOG.md" "## [Unreleased]"             "[Unreleased] inserted when absent"
assert_contains "$TMP/web/CHANGELOG.md" "Old entry that must survive" "existing entry preserved"
assert_contains "$TMP/web/CHANGELOG.md" "## 2025-01-01"               "existing version heading preserved"
assert_before   "$TMP/web/CHANGELOG.md" "## [Unreleased]" "## 2025-01-01" "[Unreleased] sits above existing releases"
echo ""

# ─── Test 4: non-canonical Unreleased headings are recognized, not duplicated ─
echo "Test 4 — recognizes a non-canonical Unreleased heading and leaves the file intact"
# 4a — bracket-less '## Unreleased' that already holds entries
cat > "$TMP/web/CHANGELOG.md" <<'EOF'
# Changelog — web

## Unreleased
### Added
- A feature already noted here
EOF
before=$(cksum < "$TMP/web/CHANGELOG.md")
run_sync
after=$(cksum < "$TMP/web/CHANGELOG.md")
[[ "$before" == "$after" ]] || fail "bracket-less '## Unreleased' file was modified (a duplicate heading was inserted)"
echo "  ✓ bracket-less '## Unreleased' left byte-for-byte intact"
PASS_COUNT=$((PASS_COUNT + 1))
assert_count "$TMP/web/CHANGELOG.md" "Unreleased" "1" "no second Unreleased heading inserted"
# 4b — indented '## [Unreleased]'
printf '# Changelog\n\n  ## [Unreleased]\n- kept\n' > "$TMP/web/CHANGELOG.md"
before=$(cksum < "$TMP/web/CHANGELOG.md")
run_sync
after=$(cksum < "$TMP/web/CHANGELOG.md")
[[ "$before" == "$after" ]] || fail "indented Unreleased heading file was modified"
echo "  ✓ indented Unreleased heading left intact"
PASS_COUNT=$((PASS_COUNT + 1))
echo ""

# ─── Test 5: never inject [Unreleased] inside a fenced code block ──────────────
echo "Test 5 — does not inject [Unreleased] inside a fenced code block"
cat > "$TMP/web/CHANGELOG.md" <<'EOF'
# Changelog — web

Example of an entry format:

```
## [1.0.0] - 2024-01-01
- example line inside a code fence
```

## 2025-01-01
- a real old entry
EOF
run_sync
assert_contains "$TMP/web/CHANGELOG.md" "## [Unreleased]" "[Unreleased] inserted"
assert_before   "$TMP/web/CHANGELOG.md" "## [1.0.0] - 2024-01-01" "## [Unreleased]" "[Unreleased] placed after the fenced example, not inside it"
assert_before   "$TMP/web/CHANGELOG.md" "## [Unreleased]" "## 2025-01-01" "[Unreleased] placed above the real release"
assert_contains "$TMP/web/CHANGELOG.md" "## [1.0.0] - 2024-01-01" "fenced example preserved"
# 5b — a fence that mixes ``` and ~~~ markers: the inner marker must NOT close the outer fence
cat > "$TMP/web/CHANGELOG.md" <<'EOF'
# Changelog — web

```
## [1.0.0] - 2024-01-01
~~~
## still inside the code fence
```

## 2025-01-01
- a real old entry
EOF
run_sync
assert_before "$TMP/web/CHANGELOG.md" "## still inside the code fence" "## [Unreleased]" "mixed-fence: [Unreleased] placed after the whole fenced block, not inside it"
assert_before "$TMP/web/CHANGELOG.md" "## [Unreleased]" "## 2025-01-01" "mixed-fence: [Unreleased] above the real release"
echo ""

# ─── Test 6: heading-less file gets [Unreleased] on top, not at EOF ───────────
echo "Test 6 — inserts [Unreleased] near the top of a heading-less changelog"
cat > "$TMP/web/CHANGELOG.md" <<'EOF'
# Changelog — web

This file is maintained by hand.
EOF
run_sync
assert_contains "$TMP/web/CHANGELOG.md" "## [Unreleased]"      "[Unreleased] inserted into heading-less file"
assert_contains "$TMP/web/CHANGELOG.md" "maintained by hand"   "existing prose preserved"
assert_before   "$TMP/web/CHANGELOG.md" "## [Unreleased]" "maintained by hand" "[Unreleased] sits above the prose, not at EOF"
echo ""

# ─── Test 7: full init (not just --sync) seeds changelogs ─────────────────────
echo "Test 7 — full init seeds root + sub-project changelogs"
FI="$(mktemp -d)"
mkdir -p "$FI/api"
printf '[project]\nname = "svc"\nversion = "0.1.0"\n' > "$FI/api/pyproject.toml"
# Feed: project name, type, stack, then 'n' to every agent prompt (extra n's are ignored).
printf 'FullInitTest\napi\nPython\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\nn\n' \
  | ( cd "$FI" && bash "$INIT" ) > "$FI/.out" 2>&1 || { cat "$FI/.out"; fail "full init exited non-zero"; }
assert_file     "$FI/CHANGELOG.md"     "full-init seeded root CHANGELOG.md"
assert_file     "$FI/api/CHANGELOG.md" "full-init seeded api/CHANGELOG.md"
assert_contains "$FI/api/CHANGELOG.md" "# Changelog — api" "full-init scoped header"
rm -rf "$FI"
echo ""

# ─── Test 8: a folder with multiple markers yields exactly one changelog ──────
echo "Test 8 — dedupes a folder that holds several marker files"
mkdir -p "$TMP/multi"
printf '{"name":"multi","version":"1.0.0"}\n' > "$TMP/multi/package.json"
printf 'module example.com/multi\n' > "$TMP/multi/go.mod"
run_sync
assert_file  "$TMP/multi/CHANGELOG.md"      "multi-marker folder seeded"
assert_count "$TMP/multi/CHANGELOG.md" "## [Unreleased]" "1" "multi-marker folder has exactly one [Unreleased]"
echo ""

# ─── Test 9: root-only project (no sub-projects) still seeds root ─────────────
echo "Test 9 — a project with no sub-projects still seeds the root changelog"
RO="$(mktemp -d)"
mkdir -p "$RO/.claude/agents"
cp "$TEMPLATE_DIR/.claude/agents/senior-dev.md" "$RO/.claude/agents/senior-dev.md"
if ! ( cd "$RO" && bash "$INIT" --sync ) > "$RO/.out" 2>&1; then cat "$RO/.out"; fail "--sync crashed on a root-only project"; fi
assert_file     "$RO/CHANGELOG.md" "root CHANGELOG.md seeded with zero sub-projects"
assert_contains "$RO/CHANGELOG.md" "## [Unreleased]" "root-only changelog has [Unreleased]"
extra=$(find "$RO" -name CHANGELOG.md ! -path "$RO/CHANGELOG.md" | wc -l | tr -d ' ')
[[ "$extra" -eq 0 ]] || fail "root-only project created $extra unexpected sub-project changelog(s)"
echo "  ✓ no spurious sub-project changelogs created"
PASS_COUNT=$((PASS_COUNT + 1))
rm -rf "$RO"
echo ""

echo "──────────────────────────────────────────────"
echo "PASS — all $PASS_COUNT assertions passed."
