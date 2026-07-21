#!/usr/bin/env bash
# context-guard.sh — Stop hook. When the context window passes the threshold,
# blocks the stop ONCE per session and demands the /end-session knowledge dump
# (Steps 1-4) while the details still exist — compaction can drop them at any
# time. Fails OPEN: any parse problem means the stop is allowed.
# Env: CLAUDE_AUTONOMY=off           bypass
#      CLAUDE_CONTEXT_THRESHOLD=80   percent of window that triggers the dump
#      CLAUDE_CONTEXT_WINDOW=200000  assumed window size in tokens
#      CLAUDE_CONTEXT_OVERRIDE=<pct> test seam, skips transcript parsing
set -uo pipefail
command -v jq >/dev/null 2>&1 || { cat >/dev/null; exit 0; }

INPUT=$(cat 2>/dev/null || true)
[[ "${CLAUDE_AUTONOMY:-on}" == "off" ]] && exit 0
[[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" == "true" ]] && exit 0

THRESH="${CLAUDE_CONTEXT_THRESHOLD:-80}"
WINDOW="${CLAUDE_CONTEXT_WINDOW:-200000}"
[[ "$THRESH" =~ ^[0-9]+$ ]] || THRESH=80
[[ "$WINDOW" =~ ^[1-9][0-9]*$ ]] || WINDOW=200000
SID=$(jq -r '.session_id // "unknown"' <<<"$INPUT" 2>/dev/null || echo unknown)
MARKER="${TMPDIR:-/tmp}/claude-ctxguard-${SID}"
[[ -f "$MARKER" ]] && exit 0       # nag once per session, not on every stop

if [[ -n "${CLAUDE_CONTEXT_OVERRIDE:-}" ]]; then
  PCT="$CLAUDE_CONTEXT_OVERRIDE"
else
  TP=$(jq -r '.transcript_path // empty' <<<"$INPUT" 2>/dev/null || true)
  [[ -f "$TP" ]] || exit 0
  # ponytail: transcript JSONL is documented-unstable; any parse miss = 0 = fail open
  USED=$(tail -n 400 "$TP" 2>/dev/null | jq -s \
    '[.[] | .message?.usage? | select(type == "object")
       | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))]
     | last // 0' 2>/dev/null) || USED=0
  USED=${USED:-0}; USED=${USED%.*}
  PCT=$(( USED * 100 / WINDOW ))
fi
PCT=${PCT%.*}
# only digits may reach bash arithmetic (crafted values would execute code)
[[ "$PCT" =~ ^[0-9]+$ ]] || exit 0

(( PCT >= THRESH )) || exit 0
touch "$MARKER" 2>/dev/null || true
jq -cn --arg reason "Context window is ~${PCT}% full (threshold ${THRESH}%). Before stopping, persist this session's knowledge NOW: run /end-session Steps 1-4 (components.md, mistakes.md, patterns.md, session-log.md). Compaction can drop details at any moment — the knowledge base is what survives. Then finish your response." \
  '{decision: "block", reason: $reason}'
exit 0
