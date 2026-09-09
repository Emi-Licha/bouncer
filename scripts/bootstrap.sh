#!/usr/bin/env bash
# Installs the toolchain that `make verify` expects, then wires up git hooks.
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "homebrew is required: https://brew.sh" >&2
  exit 1
fi

echo "== installing toolchain =="
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

# tflint is not in homebrew-core. It ships from the upstream project's own tap;
# `brew install tflint` resolves to an unrelated cask named "tint".
if command -v tflint >/dev/null 2>&1; then
  printf '  %-20s already installed\n' "tflint"
else
  printf '  %-20s installing from terraform-linters/tap...\n' "tflint"
  brew install terraform-linters/tap/tflint >/dev/null
fi

echo "== installing git hooks =="
pre-commit install

echo "== warming pre-commit environments =="
# First run downloads hook environments. Doing it here keeps `make verify`
# inside its 3 minute budget from then on.
pre-commit run --all-files >/dev/null 2>&1 || true

echo "bootstrap done — run: make doctor"
