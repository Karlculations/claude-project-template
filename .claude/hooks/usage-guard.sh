#!/usr/bin/env bash
# usage-guard.sh — pauses the session when the subscription 5-hour window is
# nearly spent (default >= 95%). Wired as UserPromptSubmit + PreToolUse +
# PostToolUse hooks in .claude/settings.json. Fails OPEN: any internal error,
# missing data, or EXPIRED data (resets_at already past) lets work continue.
#
# Three checkpoints, because a fan-out tool (Workflow) is a blind spot: it
# spawns agents in its own runtime, so no hook fires for them and nothing can
# halt it mid-run.
#   before  — refuse to START a fan-out above FANOUT%, reserving headroom to
#             finish it (ordinary work is untouched until THRESH%)
#   during  — deny expensive/ordinary tool calls above THRESH%
#   after   — on a fan-out's PostToolUse, take a FORCE-REFRESHED reading (the
#             first trustworthy one since before the call) and, over THRESH%,
#             tell Claude its results are partial and to hand off
#
# Data sources, in order:
#   1. CLAUDE_USAGE_OVERRIDE / CLAUDE_USAGE_RESET_OVERRIDE  (tests / manual)
#   2. State file cached by statusline.sh (official rate_limits feed)
#   3. GET api.anthropic.com/api/oauth/usage — undocumented endpoint Claude
#      Code itself uses; needed only headless where no statusline runs.
#      Requires a claude-code/* User-Agent or it is aggressively 429'd.
#
# CLI: --status (human summary) | --json (normalized state for scripts)
# Env: CLAUDE_AUTONOMY=off        bypass the guard (hook mode only)
#      CLAUDE_USAGE_THRESHOLD=95  block at this 5h-window percentage
#      CLAUDE_USAGE_FANOUT_THRESHOLD=80  refuse to START a fan-out (Workflow)
#                                 above this — it cannot be guarded or halted
#                                 once running, so it needs reserved headroom
#      CLAUDE_USAGE_STATE=<path>  state file (default: private per-user dir)
#      CLAUDE_USAGE_STATE_TTL=600 seconds before cached state is stale
#      CLAUDE_USAGE_FETCH_BACKOFF=120  seconds to skip the API after a failed
#                                 fetch (the guard runs on every Bash call —
#                                 without this a dead API costs 6s each time)
set -uo pipefail

# Private, user-owned location — never bare /tmp (world-writable: a planted
# state file must not be readable as ours, and its values feed comparisons).
STATE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude-autonomy"
STATE="${CLAUDE_USAGE_STATE:-$STATE_DIR/usage-state.json}"
FAILMARK="$STATE.fetchfail"
THRESH="${CLAUDE_USAGE_THRESHOLD:-95}"
[[ "$THRESH" =~ ^[0-9]+$ ]] || THRESH=95
# Env values reach bash arithmetic below — digits only, same rule as the state file.
TTL="${CLAUDE_USAGE_STATE_TTL:-600}";      [[ "$TTL" =~ ^[0-9]+$ ]] || TTL=600
BACKOFF="${CLAUDE_USAGE_FETCH_BACKOFF:-120}"; [[ "$BACKOFF" =~ ^[0-9]+$ ]] || BACKOFF=120
FANOUT="${CLAUDE_USAGE_FANOUT_THRESHOLD:-80}"; [[ "$FANOUT" =~ ^[0-9]+$ ]] || FANOUT=80
MODE="hook"; case "${1:-}" in --status) MODE=status;; --json) MODE=json;; esac

if ! command -v jq >/dev/null 2>&1; then
  # Hook mode stays silent (fail open); the CLI must say the sensor is dead.
  case "$MODE" in
    status) echo "usage-guard: jq not found — autonomy layer disabled" ;;
    json)   echo '{"error":"jq not found — autonomy layer disabled"}' ;;
    *)      cat >/dev/null ;;
  esac
  exit 0
fi

if [[ "$MODE" == "hook" && "${CLAUDE_AUTONOMY:-on}" == "off" ]]; then
  cat >/dev/null   # bypass before any state work — no fetch, no latency
  exit 0
fi

# Read the payload BEFORE touching state — the event decides how fresh the
# reading has to be. (Only in hook mode: --status from a terminal must not
# block on stdin.)
INPUT=""; EVENT=""; TOOL=""; FETCH_TTL="$TTL"
if [[ "$MODE" == "hook" ]]; then
  INPUT=$(cat 2>/dev/null || true)
  EVENT=$(jq -r '.hook_event_name // empty' <<<"$INPUT" 2>/dev/null || true)
  TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null || true)
  # A fan-out tool has just finished spawning agents through its OWN runtime —
  # no hook fired for any of them, so cached state can be a whole workflow out
  # of date. This is the first moment a reading is meaningful: force a fresh one.
  [[ "$EVENT" == "PostToolUse" ]] && FETCH_TTL=0
fi

younger_than() {   # $1 = file, $2 = max age in seconds
  [[ -f "$1" ]] &&
    (( $(date +%s) - $(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0) < $2 ))
}

oauth_token() {
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN"; return; fi
  local cred="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
  if [[ -f "$cred" ]]; then jq -r '.claudeAiOauth.accessToken // empty' "$cred" 2>/dev/null; return; fi
  if [[ "$(uname)" == "Darwin" ]]; then
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
      | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
  fi
}

fetch_api() {
  local token resp
  token=$(oauth_token); [[ -n "$token" ]] || return 1
  # Token goes in via -K config fd, NEVER argv — argv is world-readable in ps.
  resp=$(curl -sf --max-time 6 \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    -A "${CLAUDE_USAGE_UA:-claude-code/2.1.0}" \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
    https://api.anthropic.com/api/oauth/usage) || return 1
  jq -c '{ts: (now|floor), source: "api",
    five_hour: {pct: (.five_hour.utilization // null), resets_at: (.five_hour.resets_at // null)},
    seven_day: {pct: (.seven_day.utilization // null), resets_at: (.seven_day.resets_at // null)}}' \
    <<<"$resp" 2>/dev/null || return 1
}

get_state() {
  if [[ -n "${CLAUDE_USAGE_OVERRIDE:-}" ]]; then
    jq -cn --arg p "$CLAUDE_USAGE_OVERRIDE" --arg r "${CLAUDE_USAGE_RESET_OVERRIDE:-}" \
      '{ts: (now|floor), source: "override",
        five_hour: {pct: ($p|tonumber? // null), resets_at: (if $r == "" then null else $r end)},
        seven_day: {pct: null, resets_at: null}}'
    return
  fi
  if younger_than "$STATE" "$FETCH_TTL"; then cat "$STATE" 2>/dev/null && return; fi
  local s
  # Back off after a failed fetch: this runs on every guarded call (Bash
  # included), and a 6s curl timeout per call would stall the whole session.
  if ! younger_than "$FAILMARK" "$BACKOFF"; then
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
    if s=$(fetch_api); then
      rm -f "$FAILMARK" 2>/dev/null || true
      printf '%s' "$s" > "$STATE.tmp.$$" && mv "$STATE.tmp.$$" "$STATE"
      printf '%s' "$s"; return
    fi
    touch "$FAILMARK" 2>/dev/null || true
  fi
  # stale state beats no state — the expiry check below keeps it honest
  [[ -f "$STATE" ]] && cat "$STATE" 2>/dev/null
}

STATE_JSON=$(get_state || true)
PCT=$(jq -r '.five_hour.pct // empty' <<<"$STATE_JSON" 2>/dev/null || true)
RESET=$(jq -r '.five_hour.resets_at // empty' <<<"$STATE_JSON" 2>/dev/null || true)
TS=$(jq -r '.ts // empty' <<<"$STATE_JSON" 2>/dev/null || true)
PCT=${PCT%.*}
# The state file is readable input, not trusted input: only digits may reach
# bash arithmetic (a crafted pct like 'x[$(cmd)]' would otherwise execute cmd).
[[ "$PCT" =~ ^[0-9]+$ ]] || PCT=""
[[ "$TS" =~ ^[0-9]+$ ]] || TS=""

# Never act on an EXPIRED window: if resets_at is already past, the reading is
# from a previous window — blank it (fail open) so a dead sensor can't block
# work forever. ponytail: GNU date; on BSD the check is skipped, guards keep
# the old reading until the sensor refreshes.
NOW=$(date +%s)
# resets_at arrives as epoch seconds from some sources and ISO-8601 from
# others. `date -d` parses only the latter, and a timestamp it cannot read
# silently becomes 0 — which SKIPS the expiry check and hands back exactly the
# fail-CLOSED bug it exists to prevent (MISTAKE-004). Handle both forms.
RESET_EPOCH=0
if [[ -n "$RESET" ]]; then
  if [[ "$RESET" =~ ^[0-9]+$ ]]; then
    RESET_EPOCH="$RESET"
  else
    RESET_EPOCH=$(date -d "$RESET" +%s 2>/dev/null || echo 0)
    [[ "$RESET_EPOCH" =~ ^[0-9]+$ ]] || RESET_EPOCH=0
  fi
  if (( RESET_EPOCH > 0 && RESET_EPOCH <= NOW )); then
    STATE_JSON=$(jq -c '.five_hour.pct = null | .five_hour.resets_at = null | .expired = true' \
      <<<"$STATE_JSON" 2>/dev/null || echo '{}')
    PCT=""; RESET=""; RESET_EPOCH=0
  fi
fi
# Human-readable form for every message below — a bare epoch tells nobody when
# to come back.
RESET_H="$RESET"
if (( RESET_EPOCH > 0 )) && [[ "$RESET" =~ ^[0-9]+$ ]]; then
  RESET_H=$(date -d "@$RESET" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || printf '%s' "$RESET")
fi
AGE_NOTE=""
if [[ -n "$TS" ]] && (( NOW - TS > TTL )); then
  AGE_NOTE=" [reading is $(( (NOW - TS) / 60 ))m old; sensor stale, API unreachable]"
fi

if [[ "$MODE" == "json" ]]; then
  [[ -n "$STATE_JSON" ]] || STATE_JSON='{}'
  printf '%s\n' "$STATE_JSON"
  exit 0
fi
if [[ "$MODE" == "status" ]]; then
  if [[ -n "$PCT" ]]; then
    echo "5h window: ${PCT}% used (threshold ${THRESH}%, fan-out reserve ${FANOUT}%)${RESET_H:+, resets at $RESET_H}${AGE_NOTE}"
  else
    echo "5h window: unknown (no statusline cache yet, reading expired, or usage API unreachable)"
  fi
  exit 0
fi

# ── hook mode ────────────────────────────────────────────────────────────────
[[ -n "$PCT" ]] || exit 0          # fail open: no usable usage data
WHEN=${RESET_H:-unknown}

# ── Reserve headroom before an UNGUARDABLE call ──────────────────────────────
# A fan-out tool spawns its agents through its own runtime, so no PreToolUse
# hook fires for any of them and nothing can halt it once it is running. The
# window it is blind for is the whole run. Starting one with little left means
# its agents die of limit exhaustion mid-flight, it returns PARTIAL results and
# reports success, and no denial ever occurs to trigger the handoff — which is
# exactly how a session burned its window with every guard installed.
# So the entry check is stricter than the work-stop threshold: below FANOUT,
# ordinary work continues untouched; between FANOUT and THRESH only the
# unguardable call is refused.
if [[ "$EVENT" == "PreToolUse" && "$TOOL" == "Workflow" ]] \
   && (( PCT >= FANOUT && PCT < THRESH )); then
  jq -cn --arg reason "Plan usage is at ${PCT}% of the 5-hour window — too little headroom to START a fan-out (fan-out reserve ${FANOUT}%, work-stop ${THRESH}%). A workflow spawns its agents in its own runtime: no hook fires for them, nothing can stop it once running, and if they hit the limit mid-run it returns partial results and reports SUCCESS — you would not be told. Do this work inline instead (every tool call stays guarded and you can be halted cleanly at ${THRESH}%), or narrow it to the single most valuable question. Ordinary work is fine — only the fan-out is refused. Window resets at: ${WHEN}." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

(( PCT >= THRESH )) || exit 0

# Bash IS in the guard matcher (a long run of edit/build/test calls was the
# hole: nothing else fires a PreToolUse check). But the handoff this guard
# asks for is itself a Bash call, so it must stay runnable at trip time.
# Exit 0 = "no opinion", not "approved" — normal permission rules still apply,
# so this is a usage carve-out, not a security bypass.
if [[ "$EVENT" == "PreToolUse" && "$TOOL" == "Bash" ]]; then
  case "$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)" in
    *autopilot.sh*) exit 0 ;;
  esac
fi

# PostToolUse on a fan-out tool: the reading above was force-refreshed, so this
# is the first trustworthy measurement since before the call. The tool already
# ran — exit 2 puts stderr in front of Claude rather than denying anything.
if [[ "$EVENT" == "PostToolUse" ]]; then
  echo "⛔ usage-guard: plan usage is at ${PCT}% (>= ${THRESH}%) now that ${TOOL:-the fan-out} has returned.${AGE_NOTE} Its sub-agents may have been killed mid-run, so treat any results as PARTIAL and verify before relying on them — a fan-out reports success even when agents died of limit exhaustion. Do NOT start more work. Persist state NOW: run the /end-session steps (components.md, mistakes.md, patterns.md, session-log.md, active-task.md). Then, unless the user asked you to wait or the task is blocked on their input, hand off: mkdir -p ~/.cache/claude-autonomy && AUTOPILOT_CLAUDE_ARGS='<mirror the permission mode the user approved>' nohup .claude/autopilot.sh \"continue: <one-line task summary>\" >> ~/.cache/claude-autonomy/autopilot.log 2>&1 & — that command is allow-listed and will run. Window resets at: ${WHEN}." >&2
  exit 2
fi

if [[ "$EVENT" == "PreToolUse" ]]; then
  # Deny reason is shown to Claude — this is the mid-turn "wrap up now" signal.
  jq -cn --arg reason "Plan usage is at ${PCT}% of the 5-hour window (threshold ${THRESH}%). Do NOT start new work or expensive tool calls. Persist state NOW: run the /end-session steps (update .claude/knowledge/ components.md, mistakes.md, patterns.md, session-log.md, active-task.md). Then, unless the user asked you to wait for them or the task is blocked on their input, hand off before ending the turn: mkdir -p ~/.cache/claude-autonomy && AUTOPILOT_CLAUDE_ARGS='<mirror the permission mode the user approved, e.g. --permission-mode acceptEdits>' nohup .claude/autopilot.sh \"continue: <one-line task summary>\" >> ~/.cache/claude-autonomy/autopilot.log 2>&1 & — autopilot sleeps until the reset, then finishes headless. That autopilot command is allow-listed by this guard and WILL run even though other Bash calls are now denied, so do not skip the handoff just because Bash was denied. Otherwise just end the turn; work resumes after the window resets at: ${WHEN}." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

# UserPromptSubmit (and any future event): hard-block, message shown to user.
echo "⛔ usage-guard: plan usage at ${PCT}% (>= ${THRESH}%).${AGE_NOTE} Prompt blocked. Resets at: ${WHEN}. Resume after the reset, bypass once with CLAUDE_AUTONOMY=off, or use .claude/autopilot.sh for unattended wait-and-resume." >&2
exit 2
