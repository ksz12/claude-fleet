#!/usr/bin/env bash
# install.sh — install claude-fleet into ~/.claude. Idempotent.
#   ./install.sh             install / re-install
#   ./install.sh --uninstall remove hooks + installed files
set -eu
REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
FLEET_BIN="$CLAUDE/fleet/bin"
SKILLS="$CLAUDE/skills"
SETTINGS="$CLAUDE/settings.json"
HOOK="$FLEET_BIN/fleet-hook.sh"
TS="$(date -u +%Y%m%d-%H%M%S)"
EVENTS="SessionStart UserPromptSubmit PreToolUse Stop SessionEnd"

uninstall() {
  echo "== uninstall =="
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak.$TS"
    for ev in $EVENTS; do
      jq --arg ev "$ev" '
        if .hooks[$ev] then .hooks[$ev] |= map(select((.hooks[]?.command // "") | test("fleet-hook.sh")|not)) else . end
      ' "$SETTINGS" >"$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    done
    echo "removed fleet-hook from settings.json (backup: $SETTINGS.bak.$TS)"
  fi
  for s in background taskboard conclude; do [ -L "$SKILLS/$s" ] && rm -f "$SKILLS/$s"; done
  echo "uninstalled. ~/.claude/fleet state left intact."
  exit 0
}
[ "${1:-}" = "--uninstall" ] && uninstall

echo "== 1. dependency check =="
for d in tmux jq python3 git; do command -v "$d" >/dev/null || echo "   WARNING: '$d' not found — claude-fleet needs it"; done

echo "== 2. install scripts -> $FLEET_BIN =="
mkdir -p "$FLEET_BIN"; cp "$REPO"/bin/* "$FLEET_BIN"/ && chmod +x "$FLEET_BIN"/*
echo "   installed: $(ls "$FLEET_BIN" | tr '\n' ' ')"

echo "== 3. link skills -> $SKILLS =="
mkdir -p "$SKILLS"
for s in background taskboard conclude; do ln -sfn "$REPO/skills/$s" "$SKILLS/$s"; done
echo "   linked: background taskboard conclude"

echo "== 4. wire fleet-hook into settings.json =="
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$TS"
for ev in $EVENTS; do
  matcher=""; [ "$ev" = "PreToolUse" ] && matcher="*"
  jq --arg ev "$ev" --arg cmd "$HOOK $ev" --arg m "$matcher" '
    .hooks[$ev] = ( .hooks[$ev] // [] ) |
    if any(.hooks[$ev][]?; (.hooks[]?.command // "") == $cmd) then .
    else .hooks[$ev] += [ (if $m=="" then {"hooks":[{"type":"command","command":$cmd}]}
                          else {"matcher":$m,"hooks":[{"type":"command","command":$cmd}]} end) ] end
  ' "$SETTINGS" >"$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
done
echo "   hooks wired for: $EVENTS (backup: $SETTINGS.bak.$TS)"

echo
echo "DONE. Launch a session with /background, watch with: $FLEET_BIN/claude-dashboard"
echo "  uninstall: $REPO/install.sh --uninstall"
