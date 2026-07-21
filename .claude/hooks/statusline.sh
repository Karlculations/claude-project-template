#!/usr/bin/env bash
# statusline.sh — renders the status line AND acts as the usage SENSOR.
# Claude Code pipes a JSON payload to this script on every refresh; on Pro/Max
# (CC >= 2.1) it includes rate_limits.* — the only official source of plan
# usage. We cache a normalized copy to a state file that the guard hooks
# (usage-guard.sh) read, so no undocumented API call is needed interactively.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { cat >/dev/null; echo "Claude"; exit 0; }

input=$(cat)
# Private, user-owned location (matches usage-guard.sh) — never bare /tmp.
STATE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude-autonomy"
STATE="${CLAUDE_USAGE_STATE:-$STATE_DIR/usage-state.json}"

norm=$(jq -c '{ts: (now|floor), source: "statusline",
  five_hour: {pct: (.rate_limits.five_hour.used_percentage // null),
              resets_at: (.rate_limits.five_hour.resets_at // null)},
  seven_day: {pct: (.rate_limits.seven_day.used_percentage // null),
              resets_at: (.rate_limits.seven_day.resets_at // null)}}' \
  <<<"$input" 2>/dev/null || true)
if [[ -n "$norm" && $(jq -r '.five_hour.pct // "null"' <<<"$norm") != "null" ]]; then
  mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
  # $$ suffix: concurrent sessions' statuslines must not race on one tmp name
  printf '%s' "$norm" > "$STATE.tmp.$$" && mv "$STATE.tmp.$$" "$STATE"
fi

model=$(jq -r '.model.display_name // "Claude"' <<<"$input" 2>/dev/null)
p5=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input" 2>/dev/null)
p7=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input" 2>/dev/null)
r5=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input" 2>/dev/null)

line="$model"
if [[ -n "$p5" ]]; then
  rt=""
  # ponytail: GNU date only — on BSD/macOS the raw ISO timestamp is shown instead
  [[ -n "$r5" ]] && rt=$(date -d "$r5" +%H:%M 2>/dev/null || true)
  [[ -z "$rt" && -n "$r5" ]] && rt="$r5"
  line+=" | 5h ${p5%.*}%${rt:+ → $rt}"
fi
[[ -n "$p7" ]] && line+=" | 7d ${p7%.*}%"
echo "$line"
