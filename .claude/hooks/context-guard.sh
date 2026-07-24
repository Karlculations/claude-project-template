#!/usr/bin/env bash
# context-guard.sh — Stop hook. When the context window passes the threshold,
# blocks the stop ONCE per session and demands the /end-session knowledge dump
# (Steps 1-4) while the details still exist — compaction can drop them at any
# time. Fails OPEN: any parse problem means the stop is allowed.
#
# Reads the OFFICIAL context percentage cached by statusline.sh (Claude Code
# passes it `context_window.used_percentage` + the real window size). Falls
# back to estimating from the transcript only when that cache is absent or
# stale — e.g. headless runs, where no statusline ever renders.
# Env: CLAUDE_AUTONOMY=off           bypass
#      CLAUDE_CONTEXT_THRESHOLD=80   percent of window that triggers the dump
#      CLAUDE_CONTEXT_STATE=<path>   cached official reading from statusline.sh
#      CLAUDE_CONTEXT_STATE_TTL=600  seconds before that reading is stale
#      CLAUDE_CONTEXT_WINDOW=200000  window size for the FALLBACK estimate only
#                                    (a cached real size wins over this default)
#      CLAUDE_CONTEXT_OVERRIDE=<pct> test seam, skips all of the above
set -uo pipefail
command -v jq >/dev/null 2>&1 || { cat >/dev/null; exit 0; }

INPUT=$(cat 2>/dev/null || true)
[[ "${CLAUDE_AUTONOMY:-on}" == "off" ]] && exit 0
[[ "$(jq -r '.stop_hook_active // false' <<<"$INPUT" 2>/dev/null)" == "true" ]] && exit 0

THRESH="${CLAUDE_CONTEXT_THRESHOLD:-80}"
WINDOW="${CLAUDE_CONTEXT_WINDOW:-200000}"
[[ "$THRESH" =~ ^[0-9]+$ ]] || THRESH=80
[[ "$WINDOW" =~ ^[1-9][0-9]*$ ]] || WINDOW=200000
CTX_STATE="${CLAUDE_CONTEXT_STATE:-${XDG_RUNTIME_DIR:-$HOME/.cache}/claude-autonomy/context-state.json}"
CTX_TTL="${CLAUDE_CONTEXT_STATE_TTL:-600}"
[[ "$CTX_TTL" =~ ^[0-9]+$ ]] || CTX_TTL=600
PCT=""
SID=$(jq -r '.session_id // "unknown"' <<<"$INPUT" 2>/dev/null || echo unknown)
MARKER="${TMPDIR:-/tmp}/claude-ctxguard-${SID}"
[[ -f "$MARKER" ]] && exit 0       # nag once per session, not on every stop

if [[ -n "${CLAUDE_CONTEXT_OVERRIDE:-}" ]]; then
  PCT="$CLAUDE_CONTEXT_OVERRIDE"
else
  # 1. The official reading, cached by statusline.sh from the payload Claude
  #    Code gives it. Preferred: no estimation, and it knows the real window
  #    size — the assumed 200k below reads ~89% on a 1M model at 18% real use.
  if [[ -f "$CTX_STATE" ]] &&
     (( $(date +%s) - $(stat -c %Y "$CTX_STATE" 2>/dev/null || stat -f %m "$CTX_STATE" 2>/dev/null || echo 0) < CTX_TTL )); then
    PCT=$(jq -r '.pct // empty' "$CTX_STATE" 2>/dev/null || true)
    PCT=${PCT%.*}
  fi
  # 2. Fallback: estimate from the transcript (headless runs have no
  #    statusline). Use the real window size if the sensor ever cached one —
  #    a stale size still beats a hardcoded guess.
  if [[ ! "$PCT" =~ ^[0-9]+$ ]]; then
    if [[ -z "${CLAUDE_CONTEXT_WINDOW:-}" && -f "$CTX_STATE" ]]; then
      CACHED_SIZE=$(jq -r '.size // empty' "$CTX_STATE" 2>/dev/null || true)
      [[ "$CACHED_SIZE" =~ ^[1-9][0-9]*$ ]] && WINDOW="$CACHED_SIZE"
    fi
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
fi
PCT=${PCT%.*}
# only digits may reach bash arithmetic (crafted values would execute code)
[[ "$PCT" =~ ^[0-9]+$ ]] || exit 0

(( PCT >= THRESH )) || exit 0
touch "$MARKER" 2>/dev/null || true
jq -cn --arg reason "Context window is ~${PCT}% full (threshold ${THRESH}%). Before stopping, persist this session's knowledge NOW: run /end-session Steps 1-4 (components.md, mistakes.md, patterns.md, session-log.md, and the active-task.md marker if the task is unfinished). Compaction can drop details at any moment — the knowledge base is what survives. Then finish your response." \
  '{decision: "block", reason: $reason}'
exit 0
