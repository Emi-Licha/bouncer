#!/usr/bin/env bash
# yamllint over the files it is given, minus Helm chart templates.
#
# A chart's templates/ holds Go template text that only becomes YAML once helm
# renders it, so yamllint can only fail on it. Charts are checked by
# `helm template` in verify.sh instead. A file counts as a template when some
# directory above it is named templates and the directory holding that
# templates/ has a Chart.yaml. A templates/ with no Chart.yaml beside it is
# ordinary YAML and gets linted like any other.
#
# The yamllint hook in .pre-commit-config.yaml and the PostToolUse hook both go
# through here, so the two can never disagree about which files are skipped.
#
# Written for bash 3.2 (macOS).
set -u

# is_chart_template <path>: walks the path one directory at a time, checking
# every templates/ along the way. Works for relative and absolute paths alike.
is_chart_template() {
  local rest="$1" prefix=""
  while :; do
    case "$rest" in
      templates/*)
        if [ -f "${prefix}Chart.yaml" ]; then
          return 0
        fi
        ;;
    esac
    case "$rest" in
      */*)
        prefix="${prefix}${rest%%/*}/"
        rest="${rest#*/}"
        ;;
      *)
        return 1
        ;;
    esac
  done
}

files=()
for f in "$@"; do
  is_chart_template "$f" || files+=("$f")
done

[ "${#files[@]}" -gt 0 ] || exit 0
exec yamllint -s "${files[@]}"
