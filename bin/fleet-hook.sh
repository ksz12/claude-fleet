#!/usr/bin/env bash
# fleet-hook.sh <Event> — Claude Code hook dispatcher for the fleet harness.
# Reads hook JSON on stdin, updates ~/.claude/fleet/sessions/<name>.json.
# MUST be fast, MUST exit 0, MUST print nothing to stdout (stdout can be
# injected into the session as context on some events).
# bash 3.2 compatible.

EVENT="${1:-unknown}"
FLEET_DIR="${FLEET_DIR:-$HOME/.claude/fleet}"
SESS_DIR="$FLEET_DIR/sessions"
ARCH_DIR="$FLEET_DIR/archive"
INDEX="$FLEET_DIR/index.json"
mkdir -p "$SESS_DIR" "$ARCH_DIR" 2>/dev/null

input="$(cat)"
[ -z "$input" ] && input='{}'

getf() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
sid="$(getf '.session_id')"
cwd="$(getf '.cwd')"
tpath="$(getf '.transcript_path')"

# --- correlation: FLEET_SESSION_NAME (primary) -> index.json by cwd -> basename
name="${FLEET_SESSION_NAME:-}"
if [ -z "$name" ] && [ -n "$cwd" ] && [ -f "$INDEX" ]; then
  name="$(jq -r --arg c "$cwd" '.[$c] // empty' "$INDEX" 2>/dev/null)"
fi
if [ -z "$name" ] && [ -n "$cwd" ]; then
  name="$(basename "$cwd")"
fi
[ -z "$name" ] && name="unknown"
name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9._-' | cut -c1-40)"
[ -z "$name" ] && name="unknown"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$EVENT" in
  SessionStart)               status="active"  ;;
  UserPromptSubmit)           status="working" ;;
  PreToolUse|PostToolUse)     status="working" ;;
  Stop)                       status="idle"    ;;
  SessionEnd)                 status="ended"   ;;
  *)                          status=""        ;;
esac

f="$SESS_DIR/$name.json"
tmp="$f.tmp.$$"

# --- nested-session guard ---
# A session launched with FLEET_SESSION_NAME exports it into its environment, so
# any `claude -p` it spawns (smoke tests, judges, sub-agents) inherits the same
# name and fires these same hooks under a DIFFERENT session_id. Acting on those
# would flip the parent's status and, on their SessionEnd, mv its file to the
# archive — making the session flap in/out of the dashboard. Treat foreign sids
# as invisible: if a file already exists for this name with a recorded owner id
# and this event's sid differs, do nothing.
if [ -f "$f" ] && [ -n "$sid" ]; then
  owner="$(jq -r '.claude_conversation_id // empty' "$f" 2>/dev/null)"
  if [ -n "$owner" ] && [ "$owner" != "$sid" ]; then
    exit 0
  fi
fi

# auto-register unknown/ad-hoc sessions so they still appear on the dashboard
if [ ! -f "$f" ]; then
  jq -n --arg name "$name" --arg sa "$now" --arg wd "$cwd" \
    '{name:$name,prompt:"",started_at:$sa,status:"active",working_directory:$wd,repo_root:"",claude_conversation_id:"",transcript_path:"",current_task:"",latest_activity:$sa,tmux_session:$name}' \
    > "$f" 2>/dev/null
fi

jq --arg st "$status" --arg now "$now" --arg sid "$sid" --arg tp "$tpath" '
    (if $st != "" then .status = $st else . end)
  | .latest_activity = $now
  | (if ($sid != "") and ((.claude_conversation_id // "") == "") then .claude_conversation_id = $sid else . end)
  | (if $tp != "" then .transcript_path = $tp else . end)
' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" 2>/dev/null

# move ended sessions to the archive
if [ "$EVENT" = "SessionEnd" ] && [ -f "$f" ]; then
  mv "$f" "$ARCH_DIR/$name.json" 2>/dev/null
fi

exit 0
