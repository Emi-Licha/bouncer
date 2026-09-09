#!/usr/bin/env bash
# Stop hook. This is the real gate: `make verify` has to pass before a turn
# can end. Exit 2 blocks the stop and hands stderr back as the reason.
#
# Anti-loop guard: three consecutive failures release the gate, because a check
# that cannot be fixed would otherwise spin forever.
set -u

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" 2>/dev/null || exit 0

# Manual escape hatch. Git-ignored; never created automatically.
[ -f .claude/.skip-verify ] && exit 0

# Without these the hook cannot do its job, and wedging the session is worse
# than letting the turn end.
[ -f Makefile ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
# session_id is external JSON and ends up in a filesystem path, so constrain it
# to a safe character set before use.
sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)
[ -n "$sid" ] || sid="nosession"
counter="${TMPDIR:-/tmp}/cc-verify-${sid}.count"

out=$(make verify 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
  rm -f "$counter"
  exit 0
fi

n=0
if [ -f "$counter" ]; then
  n=$(tr -cd '0-9' < "$counter")
fi
[ -n "$n" ] || n=0
n=$((n + 1))
printf '%s' "$n" > "$counter"

if [ "$n" -ge 3 ]; then
  # Resetting here matters: without it the gate stays released for the rest of
  # the session instead of only for this deadlock.
  rm -f "$counter"
  printf '{"systemMessage": "verify sigue fallando despues de 3 intentos, se libera el gate"}\n'
  exit 0
fi

{
  printf '=== make verify FAILED (attempt %s/3) — the turn cannot end ===\n' "$n"
  printf '%s\n' "$out" | tail -60
} >&2
exit 2
