#!/usr/bin/env bash
# Installs the toolchain that `make verify` expects, then wires up git hooks.
#
# The Homebrew path is the tested one: macOS, and Linuxbrew where it is
# installed. The apt/dnf path is NOT TESTED. It installs what those
# repositories reliably carry and then names what you still have to fetch
# yourself. Treat it as a starting point, and check the result with
# `make doctor` rather than trusting that it finished the job.
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

# Every tool the gate can call. `make doctor` reports on the same list.
TOOLS="pre-commit gitleaks yamllint kubeconform helm kyverno terraform tflint
       terraform-docs trivy actionlint shellcheck hadolint markdownlint ruff
       mypy uv kubectl"

install_with_brew() {
  echo "== installing toolchain with homebrew =="
  for pkg in \
    pre-commit gitleaks yamllint kubeconform helm kyverno terraform \
    terraform-docs trivy actionlint shellcheck hadolint markdownlint-cli \
    uv ruff mypy kubernetes-cli; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      printf '  %-20s already installed\n' "$pkg"
    else
      printf '  %-20s installing...\n' "$pkg"
      brew install "$pkg" >/dev/null
    fi
  done

  # tflint is not in homebrew-core. It ships from the upstream project's own
  # tap; `brew install tflint` resolves to an unrelated cask named "tint".
  if have tflint; then
    printf '  %-20s already installed\n' "tflint"
  else
    printf '  %-20s installing from terraform-linters/tap...\n' "tflint"
    brew install terraform-linters/tap/tflint >/dev/null
  fi
}

# UNTESTED. Only covers what the distribution repositories carry directly.
install_with_apt() {
  echo "== installing what apt carries (UNTESTED PATH) =="
  sudo apt-get update
  sudo apt-get install -y yamllint shellcheck python3-pip
  pip3 install --user pre-commit ruff mypy
}

# UNTESTED. Note that Fedora spells shellcheck with capitals.
install_with_dnf() {
  echo "== installing what dnf carries (UNTESTED PATH) =="
  sudo dnf install -y yamllint ShellCheck python3-pip
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
  echo "Still missing, install these yourself:"
  for t in $missing; do
    case "$t" in
      gitleaks)       printf '  %-16s github: gitleaks/gitleaks\n' "$t" ;;
      kubeconform)    printf '  %-16s github: yannh/kubeconform\n' "$t" ;;
      kyverno)        printf '  %-16s github: kyverno/kyverno\n' "$t" ;;
      tflint)         printf '  %-16s github: terraform-linters/tflint\n' "$t" ;;
      terraform-docs) printf '  %-16s github: terraform-docs/terraform-docs\n' "$t" ;;
      actionlint)     printf '  %-16s github: rhysd/actionlint\n' "$t" ;;
      hadolint)       printf '  %-16s github: hadolint/hadolint\n' "$t" ;;
      markdownlint)   printf '  %-16s npm: markdownlint-cli\n' "$t" ;;
      uv)             printf '  %-16s github: astral-sh/uv\n' "$t" ;;
      *)              printf '  %-16s from its own project\n' "$t" ;;
    esac
  done
  echo
  echo "The gate only fails on a missing tool when the repository actually has"
  echo "content that needs it, so an incomplete toolchain is not necessarily a"
  echo "problem. Run 'make doctor' to see where you stand."
  return 1
}

if have brew; then
  install_with_brew
elif have apt-get; then
  install_with_apt
elif have dnf; then
  install_with_dnf
else
  echo "No supported package manager found (brew, apt-get, dnf)." >&2
  echo "Install the tools listed by 'make doctor' by hand." >&2
  exit 1
fi

echo "== installing git hooks =="
pre-commit install

echo "== warming pre-commit environments =="
# The first run downloads hook environments. Doing it here is what keeps
# `make verify` inside its budget from then on.
pre-commit run --all-files >/dev/null 2>&1 || true

# A partial install exits non-zero: silence here would read as success.
if ! report_missing; then
  exit 1
fi

echo "bootstrap done. Run: make doctor"
