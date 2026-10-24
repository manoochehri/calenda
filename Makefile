# One-command hermetic build/test (issue #2, ADR 0001). Run from a fresh worktree:
#   make setup && make test
SHELL := /bin/bash
ROKIT ?= $(shell command -v rokit 2>/dev/null || echo $(HOME)/.rokit/bin/rokit)
# Run tools through Rokit's bin dir first (an Aftman-managed rojo may shadow it otherwise).
# The inline assignment forces a shell, so the PATH override is honoured for every recipe line.
TOOLS := PATH="$(HOME)/.rokit/bin:$$PATH"
LUAU_DIRS := src tests
PLACE := build/Calenda.rbxl

.PHONY: setup fmt lint test-unit build test scan

# Install the pinned toolchain from rokit.toml. The tool specs are pinned there; trusting them
# is what lets `rokit install` run non-interactively (CI, fresh clones).
setup:
	$(ROKIT) trust rojo-rbx/rojo lune-org/lune JohnnyMorganz/StyLua Kampfkarren/selene
	$(ROKIT) install

fmt:
	$(TOOLS) stylua $(LUAU_DIRS)

lint:
	$(TOOLS) stylua --check $(LUAU_DIRS)
	$(TOOLS) selene $(LUAU_DIRS)

test-unit:
	$(TOOLS) lune run tests/run

build:
	mkdir -p build
	$(TOOLS) rojo build default.project.json --output $(PLACE)

test: lint test-unit build
	@test -s $(PLACE) && echo "OK: built $(PLACE)"

# Secret scan: fail if a tracked file contains an obvious credential pattern.
scan:
	@! git grep -nIE '(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|\.ROBLOSECURITY)' -- . ':!Makefile' \
		&& echo "scan: no secret patterns found"
