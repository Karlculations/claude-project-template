#!/usr/bin/env bash
# tests/autonomy-layer.test.sh
# Smoke test for the autonomy layer: statusline sensor, usage guard, context
# guard, compaction brief, autopilot completion semantics, and init/--sync
# distribution.
#
# Self-contained — no test framework, no network (every guard invocation uses
# the override/state-file seams, so the OAuth fallback is never reached).
# Exits non-zero on the first failed assertion; prints PASS on success.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS="$TEMPLATE_DIR/.claude/hooks"
INIT="$TEMPLATE_DIR/init-claude-project.sh"
BASH_BIN="$(command -v bash)"   # absolute, so an emptied PATH still finds the interpreter

PASS_COUNT=0

fail() { echo ""; echo "✗ FAIL: $1"; exit 1; }
ok()   { echo "  ✓ $1"; PASS_COUNT=$((PASS_COUNT + 1)); }

assert_file() { [[ -f "$1" ]] || fail "expected file missing: $1 — $2"; ok "$2"; }
assert_contains()     { grep -qF -- "$2" "$1" || fail "$1 missing '$2' — $3"; ok "$3"; }
assert_not_contains() { grep -qF -- "$2" "$1" && fail "$1 unexpectedly contains '$2' — $3"; ok "$3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/usage-state.json"

# ─── 1. Syntax ────────────────────────────────────────────────────────────────

echo "Test 1: script syntax"
for s in "$HOOKS"/statusline.sh "$HOOKS"/usage-guard.sh "$HOOKS"/context-guard.sh \
         "$HOOKS"/session-compact-brief.sh "$TEMPLATE_DIR/.claude/autopilot.sh" "$INIT"; do
  bash -n "$s" || fail "syntax error in $s"
done
ok "all scripts parse (bash -n)"

# ─── 2. Statusline sensor ─────────────────────────────────────────────────────

echo "Test 2: statusline renders and caches state"
# resets_at far in the future — the guard treats a past reset as expired data
FIXTURE='{"model":{"display_name":"TestModel"},"rate_limits":{"five_hour":{"used_percentage":96,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"used_percentage":40,"resets_at":"2099-01-03T05:00:00Z"}}}'
printf '%s' "$FIXTURE" | CLAUDE_USAGE_STATE="$STATE" bash "$HOOKS/statusline.sh" > "$TMP/sl.out"
assert_contains "$TMP/sl.out" "TestModel" "statusline shows model name"
assert_contains "$TMP/sl.out" "5h 96%" "statusline shows 5h percentage"
assert_contains "$TMP/sl.out" "7d 40%" "statusline shows 7d percentage"
assert_file "$STATE" "statusline wrote the state cache"
[[ "$(jq -r '.five_hour.pct' "$STATE")" == "96" ]] || fail "state cache pct != 96"
ok "state cache normalized (five_hour.pct = 96)"

echo "Test 2b: statusline without rate_limits (API-key user) degrades gracefully"
printf '{"model":{"display_name":"Bare"}}' | CLAUDE_USAGE_STATE="$TMP/none.json" bash "$HOOKS/statusline.sh" > "$TMP/sl2.out"
assert_contains "$TMP/sl2.out" "Bare" "model still rendered"
[[ ! -f "$TMP/none.json" ]] || fail "state cache written despite missing rate_limits"
ok "no state cache written without rate_limits data"

# ─── 3. Usage guard ───────────────────────────────────────────────────────────

echo "Test 3: usage guard blocks a prompt at >= threshold"
rc=0
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_USAGE_OVERRIDE=97 CLAUDE_USAGE_RESET_OVERRIDE="2099-01-01T00:00:00Z" \
    bash "$HOOKS/usage-guard.sh" 2> "$TMP/ug.err" || rc=$?
[[ "$rc" == "2" ]] || fail "expected exit 2 at 97%, got $rc"
ok "UserPromptSubmit exits 2 over threshold"
assert_contains "$TMP/ug.err" "97%" "block message states the percentage"
assert_contains "$TMP/ug.err" "2099-01-01T00:00:00Z" "block message states the reset time"

echo "Test 3b: usage guard passes under threshold"
rc=0
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_USAGE_OVERRIDE=50 bash "$HOOKS/usage-guard.sh" 2>/dev/null || rc=$?
[[ "$rc" == "0" ]] || fail "expected exit 0 at 50%, got $rc"
ok "UserPromptSubmit exits 0 under threshold"

echo "Test 3c: PreToolUse denies with an instruction Claude sees"
printf '{"hook_event_name":"PreToolUse","tool_name":"Task"}' \
  | CLAUDE_USAGE_OVERRIDE=97 CLAUDE_USAGE_RESET_OVERRIDE="2099-01-01T00:00:00Z" \
    bash "$HOOKS/usage-guard.sh" > "$TMP/ug.json" 2>/dev/null || true
assert_contains "$TMP/ug.json" '"permissionDecision":"deny"' "PreToolUse emits deny JSON"
assert_contains "$TMP/ug.json" "end-session" "deny reason instructs /end-session wrap-up"

echo "Test 3d: CLAUDE_AUTONOMY=off bypasses the guard"
rc=0
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_AUTONOMY=off CLAUDE_USAGE_OVERRIDE=97 bash "$HOOKS/usage-guard.sh" 2>/dev/null || rc=$?
[[ "$rc" == "0" ]] || fail "expected exit 0 with CLAUDE_AUTONOMY=off, got $rc"
ok "bypass works"

echo "Test 3e: guard reads the statusline's state cache"
rc=0
touch "$STATE"   # refresh mtime so the cache is considered fresh
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_USAGE_STATE="$STATE" bash "$HOOKS/usage-guard.sh" 2> "$TMP/ug2.err" || rc=$?
[[ "$rc" == "2" ]] || fail "expected exit 2 from cached 96%, got $rc"
assert_contains "$TMP/ug2.err" "96%" "cached statusline percentage used"

echo "Test 3f: custom threshold respected"
rc=0
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_USAGE_OVERRIDE=85 CLAUDE_USAGE_THRESHOLD=80 bash "$HOOKS/usage-guard.sh" 2>/dev/null || rc=$?
[[ "$rc" == "2" ]] || fail "expected exit 2 at 85% with threshold 80, got $rc"
ok "CLAUDE_USAGE_THRESHOLD honored"

echo "Test 3g: --json and --status CLI modes"
CLAUDE_USAGE_OVERRIDE=42 bash "$HOOKS/usage-guard.sh" --json > "$TMP/ug3.json"
[[ "$(jq -r '.five_hour.pct' "$TMP/ug3.json")" == "42" ]] || fail "--json pct != 42"
ok "--json returns normalized state"
CLAUDE_USAGE_OVERRIDE=42 bash "$HOOKS/usage-guard.sh" --status > "$TMP/ug3.out"
assert_contains "$TMP/ug3.out" "42%" "--status prints a human summary"

echo "Test 3h: an already-expired reset never blocks (fail open, not closed)"
printf '{"ts":1600000000,"source":"statusline","five_hour":{"pct":96,"resets_at":"2020-01-01T00:00:00Z"},"seven_day":{"pct":null,"resets_at":null}}' > "$TMP/stale.json"
touch "$TMP/stale.json"   # fresh mtime — expiry must be caught by resets_at, not TTL
rc=0
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_USAGE_STATE="$TMP/stale.json" bash "$HOOKS/usage-guard.sh" 2>/dev/null || rc=$?
[[ "$rc" == "0" ]] || fail "expired-window state still blocked (fail-closed), rc=$rc"
ok "expired resets_at is treated as no data"
CLAUDE_USAGE_STATE="$TMP/stale.json" bash "$HOOKS/usage-guard.sh" --json > "$TMP/stale.out"
[[ "$(jq -r '.five_hour.pct' "$TMP/stale.out")" == "null" ]] || fail "--json still reports expired pct"
ok "--json blanks the expired reading (autopilot cannot spin on it)"

echo "Test 3i: a poisoned state file cannot reach bash arithmetic"
printf '{"ts":1600000000,"five_hour":{"pct":"THRESH[$(touch %s/pwned)]","resets_at":"2099-01-01T00:00:00Z"},"seven_day":{}}' "$TMP" > "$TMP/evil.json"
touch "$TMP/evil.json"
rc=0
printf '{"hook_event_name":"UserPromptSubmit"}' \
  | CLAUDE_USAGE_STATE="$TMP/evil.json" bash "$HOOKS/usage-guard.sh" 2>/dev/null || rc=$?
[[ ! -e "$TMP/pwned" ]] || fail "arithmetic injection executed a command"
[[ "$rc" == "0" ]] || fail "poisoned state blocked instead of failing open, rc=$rc"
ok "non-numeric pct is discarded before arithmetic"

echo "Test 3j: CLI modes report a dead sensor when jq is missing"
mkdir -p "$TMP/emptybin"
PATH="$TMP/emptybin" "$BASH_BIN" "$HOOKS/usage-guard.sh" --status > "$TMP/nojq.out" 2>&1 || true
assert_contains "$TMP/nojq.out" "jq not found" "--status names the missing dependency"
PATH="$TMP/emptybin" "$BASH_BIN" "$HOOKS/usage-guard.sh" --json > "$TMP/nojq.json" 2>&1 || true
assert_contains "$TMP/nojq.json" "error" "--json carries an error field"

# ─── 4. Context guard ─────────────────────────────────────────────────────────

TRANSCRIPT="$TMP/transcript.jsonl"
printf '%s\n%s\n' \
  '{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":10,"cache_creation_input_tokens":5}}}' \
  '{"type":"assistant","message":{"usage":{"input_tokens":150,"cache_read_input_tokens":10,"cache_creation_input_tokens":5}}}' \
  > "$TRANSCRIPT"

echo "Test 4: context guard blocks the stop over threshold"
printf '{"session_id":"t4-high","transcript_path":"%s","stop_hook_active":false}' "$TRANSCRIPT" \
  | TMPDIR="$TMP" CLAUDE_CONTEXT_WINDOW=200 bash "$HOOKS/context-guard.sh" > "$TMP/cg.json"
assert_contains "$TMP/cg.json" '"decision":"block"' "stop blocked at 82% of a 200-token window"
assert_contains "$TMP/cg.json" "end-session" "block reason demands /end-session"

echo "Test 4b: fires only once per session"
printf '{"session_id":"t4-high","transcript_path":"%s","stop_hook_active":false}' "$TRANSCRIPT" \
  | TMPDIR="$TMP" CLAUDE_CONTEXT_WINDOW=200 bash "$HOOKS/context-guard.sh" > "$TMP/cg2.json"
[[ ! -s "$TMP/cg2.json" ]] || fail "context guard blocked twice for the same session"
ok "once-per-session marker respected"

echo "Test 4c: stop_hook_active short-circuits (no infinite loop)"
printf '{"session_id":"t4-loop","transcript_path":"%s","stop_hook_active":true}' "$TRANSCRIPT" \
  | TMPDIR="$TMP" CLAUDE_CONTEXT_WINDOW=200 bash "$HOOKS/context-guard.sh" > "$TMP/cg3.json"
[[ ! -s "$TMP/cg3.json" ]] || fail "context guard blocked while stop_hook_active"
ok "stop_hook_active respected"

echo "Test 4d: under threshold stays silent"
printf '{"session_id":"t4-low","transcript_path":"%s","stop_hook_active":false}' "$TRANSCRIPT" \
  | TMPDIR="$TMP" bash "$HOOKS/context-guard.sh" > "$TMP/cg4.json"
[[ ! -s "$TMP/cg4.json" ]] || fail "context guard blocked under threshold (200k window)"
ok "no block at tiny usage of the default window"

echo "Test 4e: garbage transcript fails open"
printf 'not json at all\n' > "$TMP/garbage.jsonl"
rc=0
printf '{"session_id":"t4-garbage","transcript_path":"%s","stop_hook_active":false}' "$TMP/garbage.jsonl" \
  | TMPDIR="$TMP" CLAUDE_CONTEXT_WINDOW=200 bash "$HOOKS/context-guard.sh" > "$TMP/cg5.json" 2>/dev/null || rc=$?
[[ "$rc" == "0" && ! -s "$TMP/cg5.json" ]] || fail "context guard did not fail open on unparseable transcript"
ok "unparseable transcript = fail open"

# ─── 5. Compaction brief ──────────────────────────────────────────────────────

echo "Test 5: compaction brief injects re-orientation context"
printf '{"hook_event_name":"SessionStart","source":"compact"}' \
  | bash "$HOOKS/session-compact-brief.sh" > "$TMP/cb.json"
assert_contains "$TMP/cb.json" "additionalContext" "emits additionalContext JSON"
assert_contains "$TMP/cb.json" "knowledge" "points at the knowledge base"
jq -e . "$TMP/cb.json" > /dev/null || fail "compaction brief output is not valid JSON"
ok "output is valid JSON"

# ─── 6. Autopilot completion semantics ────────────────────────────────────────
# A sandbox project with a fake `claude` on PATH and a fake usage-guard so the
# usage gate always reads 0% and the loop runs immediately.

APILOT="$TMP/apilot"; mkdir -p "$APILOT/hooks"
cp "$TEMPLATE_DIR/.claude/autopilot.sh" "$APILOT/autopilot.sh"
cat > "$APILOT/hooks/usage-guard.sh" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--json" ]] && echo '{"five_hour":{"pct":0,"resets_at":null}}'
EOF
chmod +x "$APILOT/hooks/usage-guard.sh"
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"

echo "Test 6: restating the sentinel mid-sentence is NOT completion"
cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "Working on it. I will print AUTOPILOT_TASK_COMPLETE when finished (3/12 done)."
exit 0
EOF
chmod +x "$FAKEBIN/claude"
rc=0
PATH="$FAKEBIN:$PATH" bash "$APILOT/autopilot.sh" "do the thing" 2 > "$TMP/ap.out" 2>&1 || rc=$?
assert_not_contains "$TMP/ap.out" "task reported complete" "restated token does not count as done"
[[ "$rc" == "1" ]] || fail "expected max-turns exit 1, got $rc"
ok "autopilot exhausts turns instead of false-success"

echo "Test 6b: a whole-line sentinel completes"
cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
printf 'Done with everything.\nAUTOPILOT_TASK_COMPLETE\n'
exit 0
EOF
chmod +x "$FAKEBIN/claude"
rc=0
PATH="$FAKEBIN:$PATH" bash "$APILOT/autopilot.sh" "do the thing" 2 > "$TMP/ap2.out" 2>&1 || rc=$?
assert_contains "$TMP/ap2.out" "task reported complete" "whole-line sentinel completes"
[[ "$rc" == "0" ]] || fail "expected exit 0 on completion, got $rc"
ok "autopilot exits 0 on a real completion"

echo "Test 6c: rc=127 aborts fast and names the real cause"
cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$FAKEBIN/claude"
rc=0
PATH="$FAKEBIN:$PATH" bash "$APILOT/autopilot.sh" "x" 3 > "$TMP/ap3.out" 2>&1 || rc=$?
[[ "$rc" == "127" ]] || fail "expected exit 127 on missing claude, got $rc"
assert_contains "$TMP/ap3.out" "not found on PATH" "missing claude is named, not misattributed"

# ─── 7. Distribution via --sync ───────────────────────────────────────────────

make_proj() {
  local d="$TMP/$1"
  mkdir -p "$d/.claude/agents"
  cp "$TEMPLATE_DIR/.claude/agents/senior-dev.md" "$d/.claude/agents/"
  printf '%s' "$d"
}

echo "Test 7: --sync installs the autonomy layer into a fresh project"
P1=$(make_proj proj1)
( cd "$P1" && bash "$INIT" --sync ) > "$TMP/sync1.out" 2>&1 || { cat "$TMP/sync1.out"; fail "--sync exited non-zero"; }
for h in statusline.sh usage-guard.sh context-guard.sh session-compact-brief.sh; do
  assert_file "$P1/.claude/hooks/$h" "hook installed: $h"
  [[ -x "$P1/.claude/hooks/$h" ]] || fail "$h not executable"
done
ok "hooks are executable"
assert_file "$P1/.claude/autopilot.sh" "autopilot installed"
assert_file "$P1/.claude/settings.json" "settings.json created"
assert_contains "$P1/.claude/settings.json" "usage-guard.sh" "settings wires the usage guard"
assert_contains "$P1/.claude/settings.json" "statusLine" "settings wires the statusline"
assert_contains "$P1/.claude/settings.json" 'CLAUDE_PROJECT_DIR' "hook paths use \$CLAUDE_PROJECT_DIR"
assert_contains "$P1/CLAUDE.md" "Autonomy Guards" "CLAUDE.md protocols include the guard contract"

echo "Test 7b: existing settings.json is merged, not clobbered"
P2=$(make_proj proj2)
mkdir -p "$P2/.claude"
printf '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$P2/.claude/settings.json"
( cd "$P2" && bash "$INIT" --sync ) > "$TMP/sync2.out" 2>&1 || { cat "$TMP/sync2.out"; fail "--sync (merge) exited non-zero"; }
assert_contains "$P2/.claude/settings.json" "Bash(ls:*)" "existing permissions preserved"
assert_contains "$P2/.claude/settings.json" "usage-guard.sh" "hooks added alongside existing keys"
jq -e . "$P2/.claude/settings.json" > /dev/null || fail "merged settings.json is not valid JSON"
ok "merged settings.json is valid JSON"

echo "Test 7c: a project's own hooks key is never overwritten"
P3=$(make_proj proj3)
mkdir -p "$P3/.claude"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-own.sh"}]}]}}' > "$P3/.claude/settings.json"
( cd "$P3" && bash "$INIT" --sync ) > "$TMP/sync3.out" 2>&1 || { cat "$TMP/sync3.out"; fail "--sync (hooks conflict) exited non-zero"; }
assert_contains "$P3/.claude/settings.json" "my-own.sh" "user's own hook survives"
assert_not_contains "$P3/.claude/settings.json" "usage-guard.sh" "template hooks not force-injected"
assert_contains "$TMP/sync3.out" "manually" "conflict is reported to the user"

echo "Test 7d: malformed target settings.json warns and does not abort the run"
P4=$(make_proj proj4)
mkdir -p "$P4/.claude"
printf '{"permissions":{"allow":["Bash(ls:*)",]}}' > "$P4/.claude/settings.json"   # trailing comma
rc=0
( cd "$P4" && bash "$INIT" --sync ) > "$TMP/sync4.out" 2>&1 || rc=$?
[[ "$rc" == "0" ]] || fail "--sync aborted on malformed settings.json (rc=$rc)"
assert_contains "$TMP/sync4.out" "not valid JSON" "malformed settings.json is reported"
assert_contains "$TMP/sync4.out" "Sync complete" "run finished despite the bad settings file"
assert_file "$P4/CHANGELOG.md" "later --sync steps (changelog seeding) still ran"
[[ ! -e "$P4/.claude/settings.json.tmp" ]] || fail "orphan settings.json.tmp left behind"
ok "no orphan .tmp after a skipped merge"

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "PASS — $PASS_COUNT assertions"
