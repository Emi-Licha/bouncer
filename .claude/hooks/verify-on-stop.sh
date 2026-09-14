#!/usr/bin/env bash
# Stop hook. This is the real gate: `make verify` has to pass before a turn
# can end. Exit 2 blocks the stop and hands stderr back as the reason.
#
# Anti-loop guard: three consecutive failures escalate to the user, because a check
# that cannot be fixed would otherwise spin forever.
set -u

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" 2>/dev/null || exit 0

# Without these the hook cannot do its job, and wedging the session is worse
# than letting the turn end.
[ -f Makefile ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The catalogue picks English or Spanish. Optional on purpose: if it is missing
# the gate still blocks, it just explains itself in English.
if [ -r scripts/messages.sh ]; then
  # shellcheck source=scripts/messages.sh
  . scripts/messages.sh
else
  msg() {
    case "$1" in
      stop_blocked)  printf '=== make verify FAILED (attempt %s/3): the turn cannot end ===' "$2" ;;
      stop_escalated) printf 'make verify still fails after 3 attempts: escalating to you, the turn ends with the gate red' ;;
      log_escalated) printf 'escalated after 3 failed attempts, first failing check: %s' "$2" ;;
      log_skipped)   printf 'gate skipped: .claude/.skip-verify is present, so the decision was already yours' ;;
      log_escalated_unreadable)
                     printf 'escalated after 3 failed attempts; the failing check could not be read from make verify output' ;;
    esac
  }
fi

# Bouncer steps aside in exactly two places: the three-strike escalation and the
# .skip-verify escape. Both end a turn with the gate red, and neither used to
# leave a trace, so "how often does this happen here?" had no answer. One line
# per event. Logging never fails the hook: a turn is not worth wedging over a
# file that could not be written.
note() {
  printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" \
    >> .bouncer-escalations.log 2>/dev/null || true
}

# Manual escape hatch. Git-ignored; never created automatically.
if [ -f .claude/.skip-verify ]; then
  note "$(msg log_skipped)"
  exit 0
fi

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
  # Resetting here matters: without it the gate stays open for the rest of
  # the session instead of only for this deadlock.
  rm -f "$counter"
  # Naming the check that was failing is what makes the log worth reading: three
  # escalations on the same check is a check to fix, not an agent to blame.
  # The headers come from the catalogue rather than being spelled out here: in
  # Spanish the block says CHECKS FALLIDOS, and an English-only pattern logged a
  # question mark instead of the check that was failing.
  first_under() {
    [ -n "$1" ] || return 0
    printf '%s\n' "$out" | awk -v hdr="$1" '
      index($0, hdr) == 1 { f = 1; next }
      f && /^  - / { sub(/^  - /, ""); print; exit }'
  }
  first=$(first_under "$(msg failed_checks)")
  [ -n "$first" ] || first=$(first_under "$(msg missing_tools)")
  # Reading that name depends on the shape of verify.sh's summary. If that shape
  # changes, the log says so instead of writing a bare question mark that looks
  # like nothing was failing.
  if [ -n "$first" ]; then
    note "$(msg log_escalated "$first")"
  else
    note "$(msg log_escalated_unreadable)"
  fi
  printf '{"systemMessage": "%s"}\n' "$(msg stop_escalated)"
  exit 0
fi

{
  printf '%s\n' "$(msg stop_blocked "$n")"
  printf '%s\n' "$out" | tail -60
} >&2
exit 2
