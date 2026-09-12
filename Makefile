# One command to answer "does this control actually work?"
#
#   make test                 fast checks, no AWS needed (run before every commit)
#   make verify CONTROL=slug  full apply / break / restore / destroy in the sandbox account
#
# Each target is also what CI runs, so green locally means green on GitHub.

CONTROL_DIRS := $(wildcard controls/*/)
TF_DIRS      := $(wildcard controls/*/terraform)

.PHONY: test layout fmt unit validate lint verify

test: layout fmt unit validate lint
	@echo "All fast checks passed."

# Every control folder has every required file.
layout:
	@bash scripts/check-control-layout.sh

# Code is formatted the standard way (so diffs show real changes only).
fmt:
	@opa fmt --fail --list controls >/dev/null && echo "opa fmt   OK" || (echo "Run: opa fmt --write controls" && exit 1)
	@terraform fmt -check -recursive controls >/dev/null && echo "tf fmt    OK" || (echo "Run: terraform fmt -recursive controls" && exit 1)

# Rego unit tests: every policy, every test file, no cloud.
unit:
	@opa test controls -v

# Terraform is syntactically and semantically valid (downloads the provider, no AWS login needed).
validate:
	@for d in $(TF_DIRS); do \
	  echo "validate  $$d"; \
	  (cd $$d && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color) || exit 1; \
	done

# Shell scripts are free of the classic mistakes.
lint:
	@shellcheck controls/*/evidence/*.sh controls/*/tests/*.sh scripts/*.sh && echo "shellcheck OK"

# Real proof in a real (sandbox) account. Requires HB_SANDBOX_ACCOUNT_ID to be set.
verify:
	@test -n "$(CONTROL)" || (echo "Usage: make verify CONTROL=aws-cloudtrail-all-regions" && exit 2)
	@bash scripts/verify-control.sh $(CONTROL)
