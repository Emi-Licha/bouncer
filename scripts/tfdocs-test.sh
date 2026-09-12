#!/usr/bin/env bash
# Regression cases for the helpers in tfdocs.sh. verify.sh runs them from its
# units stage, so they are part of `make verify` and a regression blocks the
# gate rather than waiting for someone to run them by hand.
#
# Every case here is a bug that shipped: a file: key inside a template: block
# read as the output file, a flow-style map reported as "no output file", one
# config spelled two ways and so reported twice. None of them can be expressed
# as a fixture under examples/, because a fixture is one config in one shape,
# and these are about the shapes the parser gets wrong.
#
# Written for bash 3.2 (macOS).
set -u

# shellcheck source=scripts/tfdocs.sh
. "$(dirname "$0")/tfdocs.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/bouncer-tfdocs.XXXXXX") || exit 1
trap 'rm -rf "${TMP:?}"' EXIT
failures=0
cases=0

fail() {
  printf 'FAIL %s\n  got:  [%s]\n  want: [%s]\n' "$1" "$2" "$3" >&2
  failures=$((failures + 1))
}

# parse <name> <expected> <config body, printf %b>
parse() {
  cases=$((cases + 1))
  printf '%b' "$3" > "$TMP/.terraform-docs.yml"
  local got
  got=$(tfdocs_output_file "$TMP/.terraform-docs.yml")
  [ "$got" = "$2" ] || fail "$1" "$got" "$2"
}

parse 'plain'                  'README.md' 'output:\n  file: README.md\n  mode: inject\n'
parse 'double quotes, comment' 'USAGE.md'  'output:\n  file: "USAGE.md"  # generated\n'
parse 'single quotes'          'USAGE.md'  "output:\n  file: 'USAGE.md'\n"
parse 'blank and comment line' 'USAGE.md'  'output:\n  # which file\n\n  mode: inject\n  file: USAGE.md\n'
parse 'document start'         'USAGE.md'  '---\noutput:\n  file: USAGE.md\n'
parse 'CRLF'                   'USAGE.md'  'output:\r\n  file: USAGE.md\r\n  mode: inject\r\n'
parse 'four space indent'      'USAGE.md'  'output:\n    mode: inject\n    file: USAGE.md\n'
parse 'comment after output'   'USAGE.md'  'output:  # where docs go\n  file: USAGE.md\n'
parse 'file: in a template'    'README.md' 'output:\n  mode: inject\n  template: |-\n    file: WRONG.md\n    {{ .Content }}\n  file: README.md\n'
parse 'template, no file key'  ''          'output:\n  template: |-\n    file: WRONG.md\n'
parse 'file: in another block' ''          'settings:\n  file: WRONG.md\noutput:\n  mode: inject\nsort:\n  file: ALSO-WRONG.md\n'
parse 'empty value'            ''          'output:\n  file: ""\n  mode: inject\n'
parse 'flow style map'         ''          'output: {file: USAGE.md, mode: inject}\n'

# lookup <name> <expected> <module dir>: tfdocs_config resolves relative paths,
# so every case runs from inside the throwaway repository.
lookup() {
  cases=$((cases + 1))
  local got
  got=$(cd "$TMP/repo" && tfdocs_config "$3")
  [ "$got" = "$2" ] || fail "$1" "$got" "$2"
}

config() { mkdir -p "$(dirname "$1")" && printf 'output:\n  file: README.md\n' > "$1"; }

rm -rf "${TMP:?}/repo"; mkdir -p "$TMP/repo/mod"
config "$TMP/repo/.terraform-docs.yml"
# The root module reaches the root config as ./.terraform-docs.yml and a module
# below it as .terraform-docs.yml. Spelled two ways, it gets reported twice.
lookup 'root config from the root module' '.terraform-docs.yml' '.'
lookup 'root config from a subdirectory'  '.terraform-docs.yml' './mod'

config "$TMP/repo/mod/.terraform-docs.yml"
lookup 'module config wins over root'     'mod/.terraform-docs.yml' './mod'
rm -f "$TMP/repo/mod/.terraform-docs.yml"

config "$TMP/repo/mod/.config/.terraform-docs.yml"
lookup 'module .config wins over root'    'mod/.config/.terraform-docs.yml' './mod'
rm -rf "${TMP:?}/repo/mod/.config"

rm -f "$TMP/repo/.terraform-docs.yml"
config "$TMP/repo/.config/.terraform-docs.yml"
lookup 'root .config'                     '.config/.terraform-docs.yml' './mod'
rm -rf "${TMP:?}/repo/.config"

# terraform-docs reads ~/.tfdocs.d/ last, so the gate has to as well, or it
# reports no config while terraform-docs is using one.
saved_home=${HOME:-}
config "$TMP/home/.tfdocs.d/.terraform-docs.yml"
HOME="$TMP/home"
lookup 'home config, nothing in the repo' "$TMP/home/.tfdocs.d/.terraform-docs.yml" './mod'
config "$TMP/repo/.terraform-docs.yml"
lookup 'repo config beats home'           '.terraform-docs.yml' './mod'
rm -f "$TMP/repo/.terraform-docs.yml"
rm -rf "${TMP:?}/home"
lookup 'no config anywhere'               '' './mod'
HOME="$saved_home"

if [ "$failures" -gt 0 ]; then
  printf '%s of %s cases failed\n' "$failures" "$cases" >&2
  exit 1
fi
printf '%s cases ok\n' "$cases"
