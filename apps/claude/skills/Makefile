SKILLS_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SCRIPT     := $(SKILLS_DIR).update-skills.py

.DEFAULT_GOAL := help

.PHONY: help update check

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  update   Fetch latest SKILL.md from upstream sources"
	@echo "  check    Show diffs without modifying files (dry-run)"
	@echo ""
	@echo "Note: run 'pre-commit run markdownlint' after update to fix lint issues."

update:
	@python3 $(SCRIPT)

check:
	@python3 $(SCRIPT) --check
