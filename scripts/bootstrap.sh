#!/usr/bin/env bash
# Installs the toolchain that `make verify` expects, then wires up git hooks.
#
# The Homebrew path is the tested one: macOS, and Linuxbrew where it is
# installed. The apt/dnf path is NOT TESTED. It installs what those
# repositories reliably carry and then names what you still have to fetch
# yourself. Treat it as a starting point, and check the result with
# `make doctor` rather than trusting that it finished the job.
set -euo pipefail

# shellcheck source=scripts/messages.sh
. "$(dirname "$0")/messages.sh"

have() { command -v "$1" >/dev/null 2>&1; }

# Every tool the gate and its hooks can call. `make doctor` reports on the same
# list. jq is the hooks' own dependency: without it they step aside in silence.
TOOLS="pre-commit gitleaks yamllint kubeconform helm kyverno terraform tflint
       terraform-docs trivy actionlint shellcheck hadolint markdownlint ruff
       mypy uv kubectl jq"

install_with_brew() {
  msg boot_brew; echo
  for pkg in \
    pre-commit gitleaks yamllint kubeconform helm kyverno terraform \
    terraform-docs trivy actionlint shellcheck hadolint markdownlint-cli \
    uv ruff mypy kubernetes-cli jq; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      printf '  %-20s %s\n' "$pkg" "$(msg boot_already)"
    else
      printf '  %-20s %s\n' "$pkg" "$(msg boot_installing)"
      brew install "$pkg" >/dev/null
    fi
  done

  # tflint is not in homebrew-core. It ships from the upstream project's own
  # tap; `brew install tflint` resolves to an unrelated cask named "tint".
  if have tflint; then
    printf '  %-20s %s\n' "tflint" "$(msg boot_already)"
  else
    printf '  %-20s %s\n' "tflint" "$(msg boot_tap)"
    brew install terraform-linters/tap/tflint >/dev/null
  fi
}

# UNTESTED. Only covers what the distribution repositories carry directly.
install_with_apt() {
  msg boot_apt; echo
  sudo apt-get update
  sudo apt-get install -y yamllint shellcheck jq python3-pip
  pip3 install --user pre-commit ruff mypy
}

# UNTESTED. Note that Fedora spells shellcheck with capitals.
install_with_dnf() {
  msg boot_dnf; echo
  sudo dnf install -y yamllint ShellCheck jq python3-pip
  pip3 install --user pre-commit ruff mypy
}

# Anything the package manager could not supply is named here rather than
# silently missing. These all ship prebuilt binaries from their own projects.
report_missing() {
  local missing=""
  for t in $TOOLS; do
    have "$t" || missing="${missing} $t"
  done
  [ -n "$missing" ] || return 0

  echo
  msg boot_still_missing; echo
  for t in $missing; do
    case "$t" in
      pre-commit)     printf '  %-16s github: pre-commit/pre-commit\n' "$t" ;;
      gitleaks)       printf '  %-16s github: gitleaks/gitleaks\n' "$t" ;;
      yamllint)       printf '  %-16s github: adrienverge/yamllint\n' "$t" ;;
      kubeconform)    printf '  %-16s github: yannh/kubeconform\n' "$t" ;;
      helm)           printf '  %-16s github: helm/helm\n' "$t" ;;
      kyverno)        printf '  %-16s github: kyverno/kyverno\n' "$t" ;;
      terraform)      printf '  %-16s github: hashicorp/terraform\n' "$t" ;;
      tflint)         printf '  %-16s github: terraform-linters/tflint\n' "$t" ;;
      terraform-docs) printf '  %-16s github: terraform-docs/terraform-docs\n' "$t" ;;
      trivy)          printf '  %-16s github: aquasecurity/trivy\n' "$t" ;;
      actionlint)     printf '  %-16s github: rhysd/actionlint\n' "$t" ;;
      shellcheck)     printf '  %-16s github: koalaman/shellcheck\n' "$t" ;;
      hadolint)       printf '  %-16s github: hadolint/hadolint\n' "$t" ;;
      markdownlint)   printf '  %-16s npm: markdownlint-cli\n' "$t" ;;
      ruff)           printf '  %-16s github: astral-sh/ruff\n' "$t" ;;
      mypy)           printf '  %-16s github: python/mypy\n' "$t" ;;
      uv)             printf '  %-16s github: astral-sh/uv\n' "$t" ;;
      kubectl)        printf '  %-16s github: kubernetes/kubernetes\n' "$t" ;;
      jq)             printf '  %-16s github: jqlang/jq\n' "$t" ;;
      *)              printf '  %-16s %s\n' "$t" "$(msg boot_from_project)" ;;
    esac
  done
  echo
  msg boot_missing_note; echo
  return 1
}

if have brew; then
  install_with_brew
elif have apt-get; then
  install_with_apt
elif have dnf; then
  install_with_dnf
else
  { msg boot_no_pm; echo; msg boot_no_pm_hint; echo; } >&2
  exit 1
fi

msg boot_hooks; echo
pre-commit install

msg boot_warming; echo
# The first run downloads hook environments. Doing it here is what keeps
# `make verify` inside its budget from then on.
pre-commit run --all-files >/dev/null 2>&1 || true

# A partial install exits non-zero: silence here would read as success.
if ! report_missing; then
  exit 1
fi

msg boot_done; echo
