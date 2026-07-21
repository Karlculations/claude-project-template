#!/usr/bin/env bash
# autopilot.sh — resumable long-task runner for THIS project's owner.
#
# Purpose: let a long task survive the subscription's 5-hour usage window.
# It does NOT evade or exceed any limit — the opposite: it stops WORK EARLY
# (default 95%, before Claude Code itself would hard-block), then waits until
# Anthropic's own published reset time and continues the same session, exactly
# as the user would do manually. All Claude Code permission settings still
# apply to every turn; this script grants nothing.
#
# Usage:  .claude/autopilot.sh "task prompt" [max_turns]
# Env:    CLAUDE_USAGE_THRESHOLD=95   pause at this % of the 5h window
#         AUTOPILOT_CLAUDE_ARGS=...   extra flags passed to claude -p
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/hooks" && pwd)"
PROMPT=${1:?usage: autopilot.sh "task prompt" [max_turns]}
MAX=${2:-24}
THRESH="${CLAUDE_USAGE_THRESHOLD:-95}"
[[ "$THRESH" =~ ^[0-9]+$ ]] || THRESH=95
DONE_TOKEN="AUTOPILOT_TASK_COMPLETE"
BLOCKED_TOKEN="AUTOPILOT_TASK_BLOCKED"
# Hooks (session-start-brief.sh) use this to know a turn IS the autopilot run
# — without it they would tell the child to defer to the running autopilot.
export CLAUDE_AUTOPILOT=1

command -v jq >/dev/null 2>&1 || { echo "✗ autopilot: jq is required (usage gating would be blind without it)" >&2; exit 1; }

pct() {
  local p
  p=$("$HOOKS_DIR/usage-guard.sh" --json 2>/dev/null | jq -r '.five_hour.pct // 0' 2>/dev/null) || p=0
  p=${p%.*}
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  printf '%s' "$p"
}

wait_for_reset() {
  local r secs=0
  r=$("$HOOKS_DIR/usage-guard.sh" --json 2>/dev/null | jq -r '.five_hour.resets_at // empty' 2>/dev/null) || r=""
  if [[ -n "$r" ]]; then
    secs=$(( $(date -d "$r" +%s 2>/dev/null || echo 0) - $(date +%s) + 120 ))
  fi
  # ponytail: reset time unknown or already past → plain 15-minute recheck
  (( secs > 0 )) || secs=900
  echo "⏸ 5h window >= ${THRESH}% — sleeping $(( secs / 60 ))m (until reset${r:+ at $r})"
  sleep "$secs"
}

for (( turn = 1; turn <= MAX; turn++ )); do
  while (( $(pct) >= THRESH )); do wait_for_reset; done
  echo "── autopilot turn $turn/$MAX (5h window at $(pct)%) ──"

  # shellcheck disable=SC2086  # AUTOPILOT_CLAUDE_ARGS is intentionally word-split
  if (( turn == 1 )); then
    out=$(claude -p ${AUTOPILOT_CLAUDE_ARGS:-} "$PROMPT

Follow this project's CLAUDE.md protocols and keep .claude/knowledge/ current as you go. When the ENTIRE task is verifiably complete (tests written and passing), output the single line $DONE_TOKEN. If the task is blocked on user input, output the single line $BLOCKED_TOKEN with the reason on the next line" 2>&1)
  else
    out=$(claude -p --continue ${AUTOPILOT_CLAUDE_ARGS:-} "Re-read .claude/knowledge/session-log.md and continue the task from where it left off. When the ENTIRE task is verifiably complete, output the single line $DONE_TOKEN. If the task is blocked on user input, output the single line $BLOCKED_TOKEN with the reason on the next line" 2>&1)
  fi
  rc=$?
  printf '%s\n' "$out" | tail -n 20

  # -x: the sentinel must be a whole line — a model RESTATING the instruction
  # ("I will output AUTOPILOT_TASK_COMPLETE when done") must not count as done
  if grep -qxF "$DONE_TOKEN" <<<"$out"; then
    echo "✓ task reported complete after $turn turn(s)"
    exit 0
  fi
  if grep -qxF "$BLOCKED_TOKEN" <<<"$out"; then
    echo "⏹ task blocked on user input after $turn turn(s) — stopping (see .claude/knowledge/active-task.md)"
    exit 1
  fi
  if (( rc == 127 )); then
    echo "✗ autopilot: claude not found on PATH — aborting" >&2
    exit 127
  elif (( rc != 0 )) && grep -qiE 'usage limit|limit reached|rate.?limit' <<<"$out"; then
    wait_for_reset
  elif (( rc != 0 )); then
    echo "⚠ turn $turn failed (rc=$rc) — retrying in 60s"
    sleep 60
  fi
done

echo "⚠ max turns ($MAX) reached without $DONE_TOKEN"
exit 1
