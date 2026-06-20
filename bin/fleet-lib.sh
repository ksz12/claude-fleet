#!/usr/bin/env bash
# Shared helpers for the Claude Fleet harness. Source this file.
# bash 3.2 compatible (macOS default).

FLEET_DIR="${FLEET_DIR:-$HOME/.claude/fleet}"
SESS_DIR="$FLEET_DIR/sessions"
ARCH_DIR="$FLEET_DIR/archive"
TASKS_DIR="$FLEET_DIR/tasks"
INDEX="$FLEET_DIR/index.json"
ALERTS="$FLEET_DIR/alerts.log"
SESSIONS_BASE="${SESSIONS_BASE:-$HOME/claude-sessions}"

fleet_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# fleet_slug "Some Name" -> some-name  (lowercase, <=40 chars, safe charset)
fleet_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' \
    | tr -cd 'a-z0-9._-' | cut -c1-40
}

fleet_ensure_dirs() { mkdir -p "$SESS_DIR" "$ARCH_DIR" "$TASKS_DIR" 2>/dev/null; }

# canonical repo root: git common dir's parent if a repo, else the dir itself
fleet_repo_root() {
  local d="$1"
  if git -C "$d" rev-parse --git-common-dir >/dev/null 2>&1; then
    ( cd "$d" && cd "$(git rev-parse --git-common-dir)/.." && pwd )
  else
    ( cd "$d" && pwd )
  fi
}
