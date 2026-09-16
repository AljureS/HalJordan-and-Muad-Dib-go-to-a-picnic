#!/usr/bin/env bash
# Opt-in Claude Code status line that caches the session JSON so the collab skill
# can read Claude's subscription windows later. It prints a short status line and
# writes ~/.collab/claude-statusline-latest.json (override with COLLAB_DIR).
#
# Enable it in ~/.claude/settings.json:
#   { "statusLine": { "type": "command", "command": "/absolute/path/to/claude_statusline_capture.sh" } }
#
# Notes: rate_limits only appears for claude.ai Pro/Max subscribers and only after
# the first API response of a session; each window may be absent. The cache holds
# no secrets — it is the same JSON Claude Code hands to any status line script.
set -uo pipefail
dir="${COLLAB_DIR:-$HOME/.collab}"
mkdir -p "$dir"
input=$(cat)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"observed_at":"%s","statusline":%s}\n' "$now" "$input" > "$dir/claude-statusline-latest.json.tmp" \
  && mv "$dir/claude-statusline-latest.json.tmp" "$dir/claude-statusline-latest.json"
if command -v jq >/dev/null 2>&1; then
  model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
  ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
  five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
  week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  line="[$model]"
  [[ -n "$ctx" ]] && line="$line ctx ${ctx%.*}%"
  [[ -n "$five" ]] && line="$line | 5h ${five%.*}%"
  [[ -n "$week" ]] && line="$line | 7d ${week%.*}%"
  [[ -z "$five$week" ]] && line="$line | limits: n/a"
  echo "$line"
else
  echo "[Claude] statusline cached (install jq for details)"
fi
