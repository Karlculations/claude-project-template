#!/usr/bin/env bash
# session-compact-brief.sh — SessionStart(matcher: compact) hook. Fires right
# after a compaction and injects a re-orientation instruction so the session
# rebuilds its picture from the knowledge base instead of guessing.
cat >/dev/null 2>&1 || true
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"NOTE: context was just compacted. Re-read .claude/knowledge/ (components.md, patterns.md, mistakes.md, session-log.md) before continuing. If work from before the compaction is not yet captured there, run the /end-session knowledge steps (1-4) first, then resume the task."}}'
