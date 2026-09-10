#!/usr/bin/env bash
# Verification engine behind `make verify`.
#
# Two rules govern every check:
#   - No files of a given kind in the repo  -> skip silently. Nothing to check.
#   - Files exist but the linter is missing -> hard failure. That is the gate.
#
# Fast static checks live in .pre-commit-config.yaml and are NOT duplicated here;
# pre-commit is the single source of truth for those. This file only adds the
# semantic checks that pre-commit cannot express (rendering, validation, tests).
#
# Written for bash 3.2 (macOS): no associative arrays, no mapfile, no ${var,,}.
set -uo pipefail

# Everything printed here goes through msg(), so the harness can speak
# English or Spanish. scripts/messages.sh explains how it picks.
# shellcheck source=scripts/messages.sh
. "$(dirname "$0")/messages.sh"

STAGE="${1:-core}"
RUN_OUT=""
TMP=.verify-tmp
MISSING=""
FAILED=""
SKIPPED=""

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; O=$'\033[0m'
else
  R=""; G=""; Y=""; O=""
fi

skip() { SKIPPED="${SKIPPED}  - $1"$'\n'; }

# need <binary> <reason>: records a hard failure when repo content requires a
# tool that is not installed. Absent content is a skip; absent tool is a failure.
need() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  MISSING="${MISSING}  - $1 $(msg required_by "$2")"$'\n'
  return 1
}

# run <label> <command...>: execute, print a one-line verdict, record failures.
# The command runs inside $( ), i.e. a subshell, so a callee may cd freely.
# Sets RUN_OUT to the command's combined output, so a caller that needs to read
# something out of a successful run does not have to run it twice.
run() {
  # Trailing space, not part of the padding: a label longer than the field runs
  # straight into the verdict otherwise.
  printf '  %-28s ' "$1"
  local out rc
  out=$("${@:2}" 2>&1); rc=$?
  RUN_OUT="$out"
  if [ "$rc" -eq 0 ]; then
    printf '%sok%s\n' "$G" "$O"
  else
    printf '%sFAIL%s\n' "$R" "$O"
    printf '%s\n' "$out" | sed 's/^/      /'
    FAILED="${FAILED}  - $1"$'\n'
  fi
}

# examples/valid holds real content: a module, a chart, a policy, a manifest.
# `make selftest` unprunes it so the gate runs over content instead of skipping
# everything, which is the only way the stage wiring itself gets exercised.
# Ordinary runs prune it, so the repository's own gate stays fast and a fork does
# not inherit fixtures it never asked for.
if [ -n "${HARNESS_SELFTEST:-}" ]; then
  VALID_PRUNE='./examples/__not_a_path__'
else
  VALID_PRUNE='./examples/valid'
fi

# scan <find-expr...>: NUL-separated paths with vendor directories pruned.
# NUL rather than newline because filenames may contain spaces.
# examples/broken holds fixtures that are invalid on purpose, so the gate can be
# demonstrated catching them. They are always pruned here and excluded in
# .pre-commit-config.yaml; `make demo` is what runs the linters against them.
scan() {
  find . \( -name .git -o -name .terraform -o -name node_modules -o -name .venv \
            -o -name vendor -o -name "$TMP" -o -path './examples/broken' \
            -o -path "$VALID_PRUNE" \) -prune \
       -o \( "$@" \) -type f -print0 2>/dev/null
}

count() { scan "$@" | tr -cd '\0' | wc -c | tr -d ' '; }

# dirs_of <nul-file> <out-file>: unique parent directories, NUL in and NUL out.
# `xargs -0 -n1 dirname` would be shorter but emits newlines, which re-splits any
# directory whose name contains one: the whole point of carrying NUL this far.
# ${f%/*} keeps the bytes intact and needs no subshell.
dirs_of() {
  local f
  while IFS= read -r -d '' f; do
    printf '%s\0' "${f%/*}"
  done < "$1" | sort -zu > "$2"
}

# ---------------------------------------------------------------------------
# stages
# ---------------------------------------------------------------------------

stage_lint() {
  echo "== static (pre-commit) =="
  if [ ! -f .pre-commit-config.yaml ]; then
    skip "$(msg skip_precommit)"
    return
  fi
  need pre-commit ".pre-commit-config.yaml" || return
  run "pre-commit" pre-commit run --all-files
}

# pre-commit only sees git-tracked files, so an untracked file bypasses the
# whole static pass. This warns instead of failing on purpose: untracked files
# are normal while work is in progress, and a gate that blocked on them would be
# switched off within a day. The warning is what keeps the hole visible rather
# than silent, which is the property that actually matters.
stage_untracked() {
  git rev-parse --git-dir >/dev/null 2>&1 || return
  local u
  u=$(git ls-files --others --exclude-standard)
  [ -n "$u" ] || return
  printf '\n%swarn%s  %s\n' "$Y" "$O" "$(msg untracked_warn)"
  printf '%s\n' "$u" | sed 's/^/        /'
}

# in_chart <path>: true when the file lives inside a Helm chart.
in_chart() {
  [ -s "$TMP/chartdirs.z" ] || return 1
  local d
  while IFS= read -r -d '' d; do
    case "$1" in
      "$d"/*) return 0 ;;
    esac
  done < "$TMP/chartdirs.z"
  return 1
}

stage_k8s() {
  scan \( -name '*.yaml' -o -name '*.yml' \) > "$TMP/yaml.z"
  : > "$TMP/k8s.z"
  # Helm chart sources are left out. A template carries apiVersion and kind at
  # column 0, so detection would claim it, but it is Go template text rather
  # than YAML and kubeconform can only fail on it. Charts are checked by
  # `helm template` in stage_helm, which renders them first.
  scan -name 'Chart.yaml' > "$TMP/chartfiles.z"
  dirs_of "$TMP/chartfiles.z" "$TMP/chartdirs.z"
  # One pass, NUL in and NUL out. Chaining two `grep -l` calls would reintroduce
  # newline separation halfway through and mis-split any filename containing one.
  # The patterns tolerate indentation and a list dash so that a manifest nested
  # inside a list is not silently skipped. A file that slips past detection is
  # never validated and nothing says so.
  while IFS= read -r -d '' f; do
    if in_chart "$f"; then
      continue
    fi
    if grep -qE '^[[:space:]]*(-[[:space:]]+)?apiVersion:' "$f" 2>/dev/null &&
       grep -qE '^[[:space:]]*(-[[:space:]]+)?kind:' "$f" 2>/dev/null; then
      printf '%s\0' "$f" >> "$TMP/k8s.z"
    fi
  done < "$TMP/yaml.z"
  if [ ! -s "$TMP/k8s.z" ]; then
    skip "$(msg skip_k8s)"
    return
  fi
  echo "== kubernetes =="
  need kubeconform "kubernetes manifests" || return
  # kubeconform fetches JSON schemas over HTTP. Without a cache that is a
  # network round trip on every run, which makes the gate slow and flaky; with
  # one, only the first run needs the network. -ignore-missing-schemas covers
  # unknown CRDs but not download failures, so a cold cache with no network is
  # still a hard failure, because you genuinely cannot validate in that state.
  KUBECONFORM_CACHE="${KUBECONFORM_CACHE:-$HOME/.cache/kubeconform}"
  mkdir -p "$KUBECONFORM_CACHE"
  run "kubeconform" bash -c \
    "xargs -0 kubeconform -strict -summary -ignore-missing-schemas \
       -cache '$KUBECONFORM_CACHE' < '$TMP/k8s.z'"
  # -ignore-missing-schemas is what lets CRDs through, and it is also how a run
  # reports ok while validating a fraction of what it read: a Kustomization and
  # two kyverno CRDs are skipped in silence. The count is surfaced so nobody
  # mistakes "kubeconform ok" for "every manifest was checked".
  local skipped
  skipped=$(printf '%s' "$RUN_OUT" | sed -n 's/.*Skipped: \([0-9][0-9]*\).*/\1/p' | tail -1)
  if [ -n "$skipped" ] && [ "$skipped" -gt 0 ]; then
    printf '  %swarn%s  %s\n' "$Y" "$O" "$(msg kubeconform_skipped "$skipped")"
  fi
}

stage_helm() {
  scan -name 'Chart.yaml' > "$TMP/charts.z"
  if [ ! -s "$TMP/charts.z" ]; then
    skip "$(msg skip_helm)"
    return
  fi
  echo "== helm =="
  need helm "helm charts" || return
  dirs_of "$TMP/charts.z" "$TMP/helmdirs.z"
  # --validate is deliberately absent: it requires a live API server, and
  # verify must run without a cluster. Server-side validation is in verify-full.
  while IFS= read -r -d '' c; do
    run "helm template $c" helm template "$c"
  done < "$TMP/helmdirs.z"
}

stage_policy() {
  scan \( -name 'kyverno-test.yaml' -o -name 'kyverno-test.yml' \) > "$TMP/kyv.z"
  if [ ! -s "$TMP/kyv.z" ]; then
    skip "$(msg skip_policy)"
    return
  fi
  echo "== policy =="
  need kyverno "kyverno test manifests" || return
  dirs_of "$TMP/kyv.z" "$TMP/kyvdirs.z"
  while IFS= read -r -d '' d; do
    run "kyverno test $d" kyverno test "$d"
  done < "$TMP/kyvdirs.z"
}

# Called through run(), which executes it inside $( ), so the cd stays contained.
tf_validate() {
  cd "$1" || return 1
  terraform init -backend=false -input=false -no-color >/dev/null || return 1
  terraform validate -no-color
}

stage_terraform() {
  if [ "$(count -name '*.tf')" -eq 0 ]; then
    skip "$(msg skip_terraform)"
    return
  fi
  echo "== terraform =="
  # `terraform fmt` is handled by pre-commit; not repeated here.
  need terraform ".tf files" || return
  scan -name '*.tf' > "$TMP/tffiles.z"
  dirs_of "$TMP/tffiles.z" "$TMP/tfdirs.z"

  need tflint ".tf files" && run "tflint" tflint --recursive
  # trivy is pointed at the terraform directories rather than the repository
  # root. Given the root it also scans Dockerfiles and rendered chart templates,
  # which belong to other tools, and it ignores this file's prune list, so it
  # reported the fixtures in examples/broken that are invalid on purpose.
  if need trivy ".tf files"; then
    while IFS= read -r -d '' d; do
      run "trivy config $d" trivy config --exit-code 1 --quiet "$d"
    done < "$TMP/tfdirs.z"
  fi
  # Scoped per module, and only where docs were opted into. Pointed at the
  # repository root it checks a directory with no .tf at all and decides the
  # project README is missing terraform documentation. Pointed at every
  # directory holding a .tf it fails on examples/, which is a normal thing for a
  # Terraform repository to have and which carries no generated docs. A README
  # holding the BEGIN_TF_DOCS marker is the directory saying it wants them.
  if [ ! -f .terraform-docs.yml ]; then
    skip "$(msg skip_tfdocs)"
  elif ! grep -qE '^[[:space:]]*file[[:space:]]*:' .terraform-docs.yml; then
    # With no output file configured, --output-check writes the rendered docs to
    # stdout and exits 0 however stale the README is. It would report ok while
    # checking nothing, so it is skipped out loud instead.
    skip "$(msg skip_tfdocs_nooutput)"
  elif need terraform-docs ".terraform-docs.yml"; then
    while IFS= read -r -d '' d; do
      if grep -q 'BEGIN_TF_DOCS' "$d/README.md" 2>/dev/null; then
        run "terraform-docs $d" terraform-docs markdown table --output-check "$d"
      fi
    done < "$TMP/tfdirs.z"
  fi
  # Providers are downloaded from the network but need no cloud credentials.
  # The shared plugin cache keeps repeated runs inside the 3 minute budget.
  TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
  export TF_PLUGIN_CACHE_DIR
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  while IFS= read -r -d '' d; do
    run "validate $d" tf_validate "$d"
  done < "$TMP/tfdirs.z"
}

stage_python() {
  if [ "$(count -name '*.py')" -eq 0 ]; then
    skip "$(msg skip_python)"
    return
  fi
  echo "== python =="
  # ruff runs in pre-commit; only the slow semantic checks are here.
  if [ -d src ]; then
    need mypy "src/ with python files" && run "mypy --strict" mypy --strict src/
  else
    skip "$(msg skip_mypy)"
  fi
  # A bare --cov measures the test files too. Tests are close to fully covered
  # by definition, so they lift the total and the floor can be cleared while the
  # code under test sits far below it: 75% source plus 100% tests reported 89%
  # and passed an 85% floor. Coverage is therefore scoped to src/, and where
  # there is no src/ the floor is dropped rather than left unscoped, because a
  # threshold that reports green for the wrong reason is worse than none.
  if [ ! -d tests ] || [ ! -f pyproject.toml ]; then
    skip "$(msg skip_pytest)"
  elif [ ! -d src ]; then
    skip "$(msg skip_cov)"
    need uv "python tests" && run "pytest" uv run --with pytest pytest -q
  else
    need uv "python tests" && run "pytest" \
      uv run --with pytest --with pytest-cov pytest -q \
        --cov=src --cov-fail-under=85
  fi
}

stage_e2e() {
  echo "== e2e =="
  if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
    printf '  %swarn%s  %s\n' "$Y" "$O" "$(msg no_cluster)"
    return
  fi
  scan -name 'kustomization.yaml' > "$TMP/kz.z"
  if [ ! -s "$TMP/kz.z" ]; then
    skip "$(msg skip_e2e)"
    return
  fi
  dirs_of "$TMP/kz.z" "$TMP/kzdirs.z"
  while IFS= read -r -d '' d; do
    run "server dry-run $d" kubectl apply --dry-run=server -k "$d"
  done < "$TMP/kzdirs.z"
}

stage_doctor() {
  printf '%s: %s\n\n' "$(msg lang_active)" "$HARNESS_LANG_ACTIVE"
  printf '%-16s %s\n' "$(msg doctor_tool)" "$(msg doctor_status)"
  for t in pre-commit gitleaks yamllint kubeconform helm kyverno terraform \
           tflint terraform-docs trivy actionlint shellcheck hadolint \
           markdownlint ruff mypy uv kubectl; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '%-16s %s%s%s\n' "$t" "$G" "$(msg doctor_ok)" "$O"
    else
      printf '%-16s %s%s%s\n' "$t" "$R" "$(msg doctor_missing)" "$O"
    fi
  done
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

mkdir -p "$TMP"

case "$STAGE" in
  doctor)
    stage_doctor
    exit 0
    ;;
  lint)
    stage_lint
    ;;
  core|full)
    stage_lint
    stage_k8s
    stage_helm
    stage_policy
    stage_terraform
    stage_python
    if [ "$STAGE" = "full" ]; then
      stage_e2e
    fi
    stage_untracked
    ;;
  *)
    printf '%s\n' "$(msg unknown_stage "$STAGE")" >&2
    exit 64
    ;;
esac

if [ -n "$SKIPPED" ]; then
  printf '\n%s\n%s' "$(msg skipped_header)" "$SKIPPED"
fi
if [ -n "$MISSING" ]; then
  printf '\n%s%s%s %s\n%s' \
    "$R" "$(msg missing_tools)" "$O" "$(msg missing_tools_hint)" "$MISSING"
fi
if [ -n "$FAILED" ]; then
  printf '\n%s%s%s\n%s' "$R" "$(msg failed_checks)" "$O" "$FAILED"
fi
if [ -n "$MISSING" ] || [ -n "$FAILED" ]; then
  exit 1
fi

printf '\n%s%s%s\n' "$G" "$(msg verify_ok)" "$O"
