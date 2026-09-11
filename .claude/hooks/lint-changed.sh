#!/usr/bin/env bash
# PostToolUse hook, matcher Edit|Write. Lints only the file that was just
# touched. Budget: under 2 seconds.
#
# Exit 2 sends stderr back to Claude as feedback. PostToolUse cannot undo the
# edit, since the tool already ran, but the message lands in context and the next
# step can fix it. Exit 1 is useless here: it is treated as a non-blocking
# error and only reaches the debug log.
#
# Defensive by design: any unexpected condition exits 0 in silence. A broken
# hook that blocks every edit is worse than no hook at all.
set -u

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null) || exit 0
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

# Never lint outside the project. Both paths are canonicalised first: a literal
# prefix test would accept a symlink that lives inside the repo but resolves
# outside it, and the linter's output, which quotes the file, reaches the
# model's context.
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# The catalogue picks English or Spanish. It is optional on purpose: a hook that
# cannot find it should still report the error, just in English.
cd "$root" 2>/dev/null || true
if [ -r "$root/scripts/messages.sh" ]; then
  # shellcheck source=scripts/messages.sh
  . "$root/scripts/messages.sh"
else
  msg() { shift; printf 'LINT FAILED: %s' "$1"; }
fi

# Containment only means anything on canonical paths, so when they cannot be
# resolved the hook declines to lint at all rather than falling back to the
# literal test a symlink defeats. Losing lint feedback is acceptable; reading a
# file outside the project is not.
command -v realpath >/dev/null 2>&1 || exit 0
real_file=$(realpath "$file" 2>/dev/null) || exit 0
real_root=$(realpath "$root" 2>/dev/null) || exit 0
case "$real_file" in
  "$real_root"/*) ;;
  *) exit 0 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }

out=""
rc=0

case "$file" in
  */.github/workflows/*.yml|*/.github/workflows/*.yaml)
    have actionlint && { out=$(actionlint "$file" 2>&1) || rc=$?; }
    ;;
  *.sh|*.bash)
    have shellcheck && { out=$(shellcheck -x "$file" 2>&1) || rc=$?; }
    ;;
  *.yaml|*.yml)
    # The wrapper skips Helm chart templates, the same files pre-commit skips.
    # Without it, fall back to plain yamllint rather than not linting at all.
    if [ -r "$root/scripts/yamllint.sh" ]; then
      have yamllint && { out=$(bash "$root/scripts/yamllint.sh" "$file" 2>&1) || rc=$?; }
    else
      have yamllint && { out=$(yamllint -s "$file" 2>&1) || rc=$?; }
    fi
    ;;
  *.tf|*.tfvars)
    have terraform && { out=$(terraform fmt -check -diff "$file" 2>&1) || rc=$?; }
    ;;
  *.py)
    have ruff && { out=$(ruff check "$file" 2>&1 && ruff format --check "$file" 2>&1) || rc=$?; }
    ;;
  *.md)
    have markdownlint && { out=$(markdownlint "$file" 2>&1) || rc=$?; }
    ;;
  *Dockerfile|*Dockerfile.*|*.dockerfile)
    have hadolint && { out=$(hadolint "$file" 2>&1) || rc=$?; }
    ;;
  *.json)
    out=$(jq empty "$file" 2>&1) || rc=$?
    ;;
  *)
    exit 0
    ;;
esac

[ "$rc" -eq 0 ] && exit 0

printf '%s\n%s\n' "$(msg lint_failed "$file")" "$out" >&2
exit 2
