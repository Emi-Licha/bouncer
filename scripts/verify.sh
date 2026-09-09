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

STAGE="${1:-core}"
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
  MISSING="${MISSING}  - $1 (required by: $2)"$'\n'
  return 1
}

# run <label> <command...>: execute, print a one-line verdict, record failures.
# The command runs inside $( ), i.e. a subshell, so a callee may cd freely.
run() {
  printf '  %-28s' "$1"
  local out rc
  out=$("${@:2}" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%sok%s\n' "$G" "$O"
  else
    printf '%sFAIL%s\n' "$R" "$O"
    printf '%s\n' "$out" | sed 's/^/      /'
    FAILED="${FAILED}  - $1"$'\n'
  fi
}

# scan <find-expr...>: NUL-separated paths with vendor directories pruned.
# NUL rather than newline because filenames may contain spaces.
# examples/broken holds fixtures that are invalid on purpose, so the gate can be
# demonstrated catching them. They are pruned here and excluded in
# .pre-commit-config.yaml; `make demo` is what runs the linters against them.
scan() {
  find . \( -name .git -o -name .terraform -o -name node_modules -o -name .venv \
            -o -name vendor -o -name "$TMP" -o -path './examples/broken' \) -prune \
       -o \( "$@" \) -type f -print0 2>/dev/null
}

count() { scan "$@" | tr -cd '\0' | wc -c | tr -d ' '; }

# ---------------------------------------------------------------------------
# stages
# ---------------------------------------------------------------------------

stage_lint() {
  echo "== static (pre-commit) =="
  if [ ! -f .pre-commit-config.yaml ]; then
    skip "pre-commit (no .pre-commit-config.yaml)"
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
  printf '\n%swarn%s  untracked files are invisible to pre-commit:\n' "$Y" "$O"
  printf '%s\n' "$u" | sed 's/^/        /'
}

stage_k8s() {
  scan \( -name '*.yaml' -o -name '*.yml' \) > "$TMP/yaml.z"
  : > "$TMP/k8s.z"
  # One pass, NUL in and NUL out. Chaining two `grep -l` calls would reintroduce
  # newline separation halfway through and mis-split any filename containing one.
  # The patterns tolerate indentation and a list dash so that a manifest nested
  # inside a list is not silently skipped — a file that slips past detection is
  # never validated and nothing says so.
  while IFS= read -r -d '' f; do
    if grep -qE '^[[:space:]]*(-[[:space:]]+)?apiVersion:' "$f" 2>/dev/null &&
       grep -qE '^[[:space:]]*(-[[:space:]]+)?kind:' "$f" 2>/dev/null; then
      printf '%s\0' "$f" >> "$TMP/k8s.z"
    fi
  done < "$TMP/yaml.z"
  if [ ! -s "$TMP/k8s.z" ]; then
    skip "kubeconform (no kubernetes manifests)"
    return
  fi
  echo "== kubernetes =="
  need kubeconform "kubernetes manifests" || return
  # kubeconform fetches JSON schemas over HTTP. Without a cache that is a
  # network round trip on every run, which makes the gate slow and flaky; with
  # one, only the first run needs the network. -ignore-missing-schemas covers
  # unknown CRDs but not download failures, so a cold cache with no network is
  # still a hard failure — you genuinely cannot validate in that state.
  KUBECONFORM_CACHE="${KUBECONFORM_CACHE:-$HOME/.cache/kubeconform}"
  mkdir -p "$KUBECONFORM_CACHE"
  run "kubeconform" bash -c \
    "xargs -0 kubeconform -strict -summary -ignore-missing-schemas \
       -cache '$KUBECONFORM_CACHE' < '$TMP/k8s.z'"
}

stage_helm() {
  scan -name 'Chart.yaml' > "$TMP/charts.z"
  if [ ! -s "$TMP/charts.z" ]; then
    skip "helm (no charts)"
    return
  fi
  echo "== helm =="
  need helm "helm charts" || return
  xargs -0 -n1 dirname < "$TMP/charts.z" | sort -u > "$TMP/charts.txt"
  # --validate is deliberately absent: it requires a live API server, and
  # verify must run without a cluster. Server-side validation is in verify-full.
  while IFS= read -r c; do
    run "helm template $c" helm template "$c"
  done < "$TMP/charts.txt"
}

stage_policy() {
  scan \( -name 'kyverno-test.yaml' -o -name 'kyverno-test.yml' \) > "$TMP/kyv.z"
  if [ ! -s "$TMP/kyv.z" ]; then
    skip "kyverno (no policy tests)"
    return
  fi
  echo "== policy =="
  need kyverno "kyverno test manifests" || return
  xargs -0 -n1 dirname < "$TMP/kyv.z" | sort -u > "$TMP/kyv.txt"
  while IFS= read -r d; do
    run "kyverno test $d" kyverno test "$d"
  done < "$TMP/kyv.txt"
}

# Called through run(), which executes it inside $( ) — the cd stays contained.
tf_validate() {
  cd "$1" || return 1
  terraform init -backend=false -input=false -no-color >/dev/null || return 1
  terraform validate -no-color
}

stage_terraform() {
  if [ "$(count -name '*.tf')" -eq 0 ]; then
    skip "terraform (no .tf files)"
    return
  fi
  echo "== terraform =="
  # `terraform fmt` is handled by pre-commit; not repeated here.
  need terraform ".tf files" || return
  need tflint ".tf files" && run "tflint" tflint --recursive
  need trivy ".tf files"  && run "trivy config" trivy config --exit-code 1 --quiet .
  if [ -f .terraform-docs.yml ]; then
    need terraform-docs ".terraform-docs.yml" \
      && run "terraform-docs" terraform-docs markdown table --output-check .
  else
    skip "terraform-docs (no .terraform-docs.yml)"
  fi
  # Providers are downloaded from the network but need no cloud credentials.
  # The shared plugin cache keeps repeated runs inside the 3 minute budget.
  TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
  export TF_PLUGIN_CACHE_DIR
  mkdir -p "$TF_PLUGIN_CACHE_DIR"
  scan -name '*.tf' | xargs -0 -n1 dirname | sort -u > "$TMP/tfdirs.txt"
  while IFS= read -r d; do
    run "validate $d" tf_validate "$d"
  done < "$TMP/tfdirs.txt"
}

stage_python() {
  if [ "$(count -name '*.py')" -eq 0 ]; then
    skip "python (no .py files)"
    return
  fi
  echo "== python =="
  # ruff runs in pre-commit; only the slow semantic checks are here.
  if [ -d src ]; then
    need mypy "src/ with python files" && run "mypy --strict" mypy --strict src/
  else
    skip "mypy (no src/)"
  fi
  if [ -d tests ] && [ -f pyproject.toml ]; then
    need uv "python tests" && run "pytest" \
      uv run --with pytest --with pytest-cov pytest -q --cov --cov-fail-under=85
  else
    skip "pytest (needs tests/ and pyproject.toml)"
  fi
}

stage_e2e() {
  echo "== e2e =="
  if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
    printf '  %swarn%s  skipped: no reachable cluster\n' "$Y" "$O"
    return
  fi
  scan -name 'kustomization.yaml' > "$TMP/kz.z"
  if [ ! -s "$TMP/kz.z" ]; then
    skip "e2e (no kustomizations)"
    return
  fi
  xargs -0 -n1 dirname < "$TMP/kz.z" | sort -u > "$TMP/kz.txt"
  while IFS= read -r d; do
    run "server dry-run $d" kubectl apply --dry-run=server -k "$d"
  done < "$TMP/kz.txt"
}

stage_doctor() {
  printf '%-16s %s\n' "TOOL" "STATUS"
  for t in pre-commit gitleaks yamllint kubeconform helm kyverno terraform \
           tflint terraform-docs trivy actionlint shellcheck hadolint \
           markdownlint ruff mypy uv kubectl; do
    if command -v "$t" >/dev/null 2>&1; then
      printf '%-16s %sok%s\n' "$t" "$G" "$O"
    else
      printf '%-16s %smissing%s\n' "$t" "$R" "$O"
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
    printf 'unknown stage: %s (expected: lint, core, full, doctor)\n' "$STAGE" >&2
    exit 64
    ;;
esac

if [ -n "$SKIPPED" ]; then
  printf '\nskipped (no such content in this repo):\n%s' "$SKIPPED"
fi
if [ -n "$MISSING" ]; then
  printf '\n%sMISSING TOOLS%s (the repo has content that requires them) — run: make bootstrap\n%s' \
    "$R" "$O" "$MISSING"
fi
if [ -n "$FAILED" ]; then
  printf '\n%sFAILED CHECKS%s:\n%s' "$R" "$O" "$FAILED"
fi
if [ -n "$MISSING" ] || [ -n "$FAILED" ]; then
  exit 1
fi

printf '\n%sverify OK%s\n' "$G" "$O"
