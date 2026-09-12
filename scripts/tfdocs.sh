#!/usr/bin/env bash
# Finding the terraform-docs config for a module, and reading its output file.
#
# These live apart from verify.sh so scripts/tfdocs-test.sh can source them and
# assert on them directly. The parser has been wrong twice in ways no fixture
# under examples/ can express, so its cases are a test rather than a note in a
# commit message.
#
# Written for bash 3.2 (macOS).

# tfdocs_config <module dir>: the config terraform-docs will use for that
# module, searched in its order: the module, the module's .config/, the current
# directory, its .config/, then ~/.tfdocs.d/. Prints nothing when there is none.
# A leading ./ is dropped, so one file always comes out spelled one way, whether
# it was reached from a module at the root or from one in a subdirectory.
tfdocs_config() {
  local c
  for c in "$1/.terraform-docs.yml" "$1/.config/.terraform-docs.yml" \
           .terraform-docs.yml .config/.terraform-docs.yml \
           "${HOME:-/nonexistent}/.tfdocs.d/.terraform-docs.yml"; do
    if [ -f "$c" ]; then
      printf '%s' "${c#./}"
      return
    fi
  done
}

# tfdocs_output_file <config>: output.file, with quotes and a trailing comment
# stripped. Only a key sitting directly under output: counts. A file: line in
# another section, or inside the text of a template: block, is more deeply
# indented or outside the block, and is ignored. Block style only: a one-line
# `output: {...}` map yields nothing, and the caller reports it as unreadable.
tfdocs_output_file() {
  awk -v q="'" '
    /^output[[:space:]]*:[[:space:]]*(#.*)?$/ { inside = 1; indent = -1; next }
    inside {
      if ($0 ~ /^[[:space:]]*(#.*)?$/) next
      match($0, /^[[:space:]]*/)
      if (RLENGTH == 0) exit
      if (indent < 0) indent = RLENGTH
      if (RLENGTH < indent) exit
      if (RLENGTH == indent && $0 ~ /^[[:space:]]*file[[:space:]]*:/) {
        v = $0
        sub(/^[[:space:]]*file[[:space:]]*:[[:space:]]*/, "", v)
        sub(/[[:space:]]+#.*$/, "", v)
        sub(/[[:space:]]+$/, "", v)
        gsub(/"/, "", v)
        gsub(q, "", v)
        print v
        exit
      }
    }
  ' "$1"
}
