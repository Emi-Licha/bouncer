#!/usr/bin/env bash
# Runs the gate's linters against examples/broken/ and asserts that every
# fixture is rejected. These files are excluded from the repository's own
# `make verify`, so they can stay broken on purpose.
#
# The demo passes when every check fails. A check that passes means the gate
# stopped catching something it used to catch.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Sourced after the cd, because the language file is read from the
# repository root.
# shellcheck source=scripts/messages.sh
. scripts/messages.sh

DIR=examples/broken
missed=0

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; O=$'\033[0m'
else
  R=""; G=""; Y=""; O=""
fi

# expect_reject <tool> <label> <command...>
expect_reject() {
  local tool="$1" label="$2"
  shift 2
  printf '\n%s\n' "--- $label"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '  %sskipped%s: %s\n' "$Y" "$O" "$(msg demo_skipped "$tool")"
    return
  fi
  local out rc
  out=$("$@" 2>&1); rc=$?
  printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$rc" -ne 0 ]; then
    printf '  %s%s%s\n' "$G" "$(msg demo_caught "$rc")" "$O"
  else
    printf '  %s%s%s\n' "$R" "$(msg demo_missed)" "$O"
    missed=1
  fi
}

# A missing fixture makes its linter fail with "file not found", which would
# count as a rejection and report the demo as passing. Check they exist first.
for f in "$DIR/unquoted-var.sh" "$DIR/bad-indent.yaml" "$DIR/Dockerfile"; do
  if [ ! -f "$f" ]; then
    printf '%s%s%s\n' "$R" "$(msg demo_no_fixtures "$f")" "$O" >&2
    exit 1
  fi
done

msg demo_intro; echo

expect_reject shellcheck "$(msg demo_case_shell)" \
  shellcheck -x "$DIR/unquoted-var.sh"

expect_reject yamllint "$(msg demo_case_yaml)" \
  yamllint -s "$DIR/bad-indent.yaml"

expect_reject hadolint "$(msg demo_case_docker)" \
  hadolint "$DIR/Dockerfile"

if [ "$missed" -ne 0 ]; then
  printf '\n%s%s%s\n' "$R" "$(msg demo_failed)" "$O"
  exit 1
fi

printf '\n%s%s%s\n' "$G" "$(msg demo_ok)" "$O"
