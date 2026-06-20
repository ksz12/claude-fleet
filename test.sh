#!/usr/bin/env bash
# test.sh — smoke check: every script parses under its interpreter.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"; pass=0; fail=0
for f in "$ROOT"/bin/*; do
  case "$(head -1 "$f")" in
    *python*) if python3 -m py_compile "$f" 2>/dev/null; then echo "  ok(py) $(basename "$f")"; pass=$((pass+1)); else echo "  FAIL  $(basename "$f")"; fail=$((fail+1)); fi ;;
    *)        if bash -n "$f" 2>/dev/null;        then echo "  ok(sh) $(basename "$f")"; pass=$((pass+1)); else echo "  FAIL  $(basename "$f")"; fail=$((fail+1)); fi ;;
  esac
done
find "$ROOT" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
echo "RESULT: $pass ok, $fail failed"; [ "$fail" -eq 0 ]
