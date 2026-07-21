#!/usr/bin/env bash
# usage-guard.sh — pauses the session when the subscription 5-hour window is
# nearly spent (default >= 95%). Wired as UserPromptSubmit + PreToolUse hooks
# in .claude/settings.json. Fails OPEN: any internal error, missing data, or
# EXPIRED data (resets_at already past) lets work continue.
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
#      CLAUDE_USAGE_STATE=<path>  state file (default: private per-user dir)
#      CLAUDE_USAGE_STATE_TTL=600 seconds before cached state is stale
set -uo pipefail

# Private, user-owned location — never bare /tmp (world-writable: a planted
# state file must not be readable as ours, and its values feed comparisons).
STATE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude-autonomy"
STATE="${CLAUDE_USAGE_STATE:-$STATE_DIR/usage-state.json}"
THRESH="${CLAUDE_USAGE_THRESHOLD:-95}"
[[ "$THRESH" =~ ^[0-9]+$ ]] || THRESH=95
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

state_fresh() {
  [[ -f "$STATE" ]] &&
    (( $(date +%s) - $(stat -c %Y "$STATE" 2>/dev/null || stat -f %m "$STATE" 2>/dev/null || echo 0) \
       < ${CLAUDE_USAGE_STATE_TTL:-600} ))
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
  if state_fresh; then cat "$STATE" 2>/dev/null && return; fi
  local s
  if s=$(fetch_api); then
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
    printf '%s' "$s" > "$STATE.tmp.$$" && mv "$STATE.tmp.$$" "$STATE"
    printf '%s' "$s"; return
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
if [[ -n "$RESET" ]]; then
  RESET_EPOCH=$(date -d "$RESET" +%s 2>/dev/null || echo 0)
  if (( RESET_EPOCH > 0 && RESET_EPOCH <= NOW )); then
    STATE_JSON=$(jq -c '.five_hour.pct = null | .five_hour.resets_at = null | .expired = true' \
      <<<"$STATE_JSON" 2>/dev/null || echo '{}')
    PCT=""; RESET=""
  fi
fi
AGE_NOTE=""
if [[ -n "$TS" ]] && (( NOW - TS > ${CLAUDE_USAGE_STATE_TTL:-600} )); then
  AGE_NOTE=" [reading is $(( (NOW - TS) / 60 ))m old; sensor stale, API unreachable]"
fi

if [[ "$MODE" == "json" ]]; then
  [[ -n "$STATE_JSON" ]] || STATE_JSON='{}'
  printf '%s\n' "$STATE_JSON"
  exit 0
fi
if [[ "$MODE" == "status" ]]; then
  if [[ -n "$PCT" ]]; then
    echo "5h window: ${PCT}% used (threshold ${THRESH}%)${RESET:+, resets at $RESET}${AGE_NOTE}"
  else
    echo "5h window: unknown (no statusline cache yet, reading expired, or usage API unreachable)"
  fi
  exit 0
fi

# ── hook mode ────────────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null || true)
[[ -n "$PCT" ]] || exit 0          # fail open: no usable usage data
(( PCT >= THRESH )) || exit 0

EVENT=$(jq -r '.hook_event_name // empty' <<<"$INPUT" 2>/dev/null || true)
WHEN=${RESET:-unknown}

if [[ "$EVENT" == "PreToolUse" ]]; then
  # Deny reason is shown to Claude — this is the mid-turn "wrap up now" signal.
  jq -cn --arg reason "Plan usage is at ${PCT}% of the 5-hour window (threshold ${THRESH}%). Do NOT start new work or expensive tool calls. Persist state NOW: run the /end-session steps (update .claude/knowledge/ components.md, mistakes.md, patterns.md, session-log.md, active-task.md). Then, unless the user asked you to wait for them or the task is blocked on their input, hand off before ending the turn: mkdir -p ~/.cache/claude-autonomy && AUTOPILOT_CLAUDE_ARGS='<mirror the permission mode the user approved, e.g. --permission-mode acceptEdits>' nohup .claude/autopilot.sh \"continue: <one-line task summary>\" >> ~/.cache/claude-autonomy/autopilot.log 2>&1 & — autopilot sleeps until the reset, then finishes headless. Otherwise just end the turn; work resumes after the window resets at: ${WHEN}." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

# UserPromptSubmit (and any future event): hard-block, message shown to user.
echo "⛔ usage-guard: plan usage at ${PCT}% (>= ${THRESH}%).${AGE_NOTE} Prompt blocked. Resets at: ${WHEN}. Resume after the reset, bypass once with CLAUDE_AUTONOMY=off, or use .claude/autopilot.sh for unattended wait-and-resume." >&2
exit 2
