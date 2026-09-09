SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# The logic lives in scripts/verify.sh because macOS ships GNU Make 3.81,
# which has no .ONESHELL: every recipe line would otherwise be its own shell.

.PHONY: help bootstrap doctor lint verify verify-full clean

help:
	@echo "bootstrap    install the toolchain that verify expects (brew)"
	@echo "doctor       report which tools are installed and which are missing"
	@echo "lint         fast static pass (pre-commit run --all-files)"
	@echo "verify       canonical gate: lint + semantic validation (<3min, no cloud creds)"
	@echo "verify-full  verify + e2e against a live cluster (slow, run before pushing)"
	@echo "clean        remove scratch and cache directories"

bootstrap:
	@bash scripts/bootstrap.sh

doctor:
	@bash scripts/verify.sh doctor

lint:
	@bash scripts/verify.sh lint

verify:
	@bash scripts/verify.sh core

verify-full:
	@bash scripts/verify.sh full

clean:
	@rm -rf .verify-tmp .pytest_cache .ruff_cache .mypy_cache
