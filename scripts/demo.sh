#!/usr/bin/env bash
# Runs the gate's linters against examples/broken/ and asserts that every
# fixture is rejected. These files are excluded from the repository's own
# `make verify`, so they can stay broken on purpose.
#
# The demo passes when every check fails. A check that passes means the gate
# stopped catching something it used to catch.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
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
    printf '  %sskipped%s: %s is not installed. Run: make bootstrap\n' "$Y" "$O" "$tool"
    return
  fi
  local out rc
  out=$("$@" 2>&1); rc=$?
  printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$rc" -ne 0 ]; then
    printf '  %sthe gate caught it%s (exit %s)\n' "$G" "$O" "$rc"
  else
    printf '  %sTHE GATE MISSED IT%s: a non-zero exit was expected\n' "$R" "$O"
    missed=1
  fi
}

echo "Each fixture below is broken on purpose. Every check is expected to fail."

expect_reject shellcheck "shellcheck: an unquoted, undefined variable" \
  shellcheck -x "$DIR/unquoted-var.sh"

expect_reject yamllint "yamllint: invalid indentation" \
  yamllint -s "$DIR/bad-indent.yaml"

expect_reject hadolint "hadolint: untagged base image, no apt cleanup" \
  hadolint "$DIR/Dockerfile"

if [ "$missed" -ne 0 ]; then
  printf '\n%sdemo FAILED%s: at least one fixture was not rejected.\n' "$R" "$O"
  exit 1
fi

printf '\n%sdemo OK%s: every fixture was rejected, as it should be.\n' "$G" "$O"
