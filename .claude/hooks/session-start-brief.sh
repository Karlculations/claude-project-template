#!/usr/bin/env bash
# session-start-brief.sh — SessionStart(matcher: startup|clear) hook. If the
# previous session left a task unfinished, /end-session recorded it in
# .claude/knowledge/active-task.md; this hook injects that marker into every
# fresh session with an instruction to resume immediately — the user's first
# message continues the work instead of re-explaining it. Autopilot's own
# headless turns set CLAUDE_AUTOPILOT=1 and get a variant WITHOUT the
# "is autopilot already on it?" check (they ARE the autopilot run — the check
# would tell them to refuse their own job). Silent (fail open) when there is
# no marker, no jq, or any read problem.
set -uo pipefail
cat >/dev/null 2>&1 || true

TASK_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/knowledge/active-task.md"
[[ -s "$TASK_FILE" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# ponytail: 4KB cap — the marker is a briefing, not a transcript
BODY=$(head -c 4096 "$TASK_FILE" 2>/dev/null) || exit 0
[[ -n "${BODY//[$' \t\r\n']/}" ]] || exit 0   # whitespace-only marker = no task

if [[ "${CLAUDE_AUTOPILOT:-}" == "1" ]]; then
  TAIL="You are an unattended autopilot continuation run. Re-read .claude/knowledge/ (components.md, patterns.md, mistakes.md, session-log.md), then CONTINUE this task immediately. If it is or becomes blocked on user input, output the single line AUTOPILOT_TASK_BLOCKED with the reason on the next line, instead of guessing."
else
  TAIL="Re-read .claude/knowledge/ (components.md, patterns.md, mistakes.md, session-log.md), then CONTINUE this task immediately — do not wait to be re-briefed. Exceptions: if the marker says it is blocked on user input, ask for that input instead; if autopilot may already be running it, check first (pgrep -f autopilot.sh) and report rather than duplicate. Delete active-task.md when the task is verifiably complete."
fi

jq -cn --arg body "$BODY" --arg tail "$TAIL" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    ("UNFINISHED TASK from the previous session (.claude/knowledge/active-task.md):\n\n" + $body + "\n\n" + $tail)}}'
