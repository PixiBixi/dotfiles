ROOT_DIR   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PKGS_DIR   := $(ROOT_DIR)packages/
SKILLS_DIR := $(ROOT_DIR)apps/claude/skills/
SCRIPT     := $(SKILLS_DIR).update-skills.py

.DEFAULT_GOAL := help

.PHONY: help update update-brew update-npm update-gems update-skills check

help:
	@echo "Usage: make [TARGET]"
	@echo ""
	@echo "  update           Update all (brew, npm, gems, skills)"
	@echo "  update-brew      Dump installed Homebrew packages → packages/Brewfile"
	@echo "  update-npm       Dump global npm packages → packages/npm.txt"
	@echo "  update-gems      Dump installed gems → packages/gems.txt"
	@echo "  update-skills    Fetch latest SKILL.md from upstream sources"
	@echo "  check            Show skills diffs without modifying (dry-run)"

update: update-brew update-npm update-gems update-skills

update-brew:
	@echo "Updating packages/Brewfile..."
	@brew bundle dump --force --file="$(PKGS_DIR)Brewfile"
	@echo "Done."

# Dumps installed global npm packages (excluding npm itself) as a sorted list of names.
update-npm:
	@echo "Updating packages/npm.txt..."
	@npm list -g --depth=0 --json 2>/dev/null | python3 -c "import json,sys; [print(k) for k in sorted(json.load(sys.stdin).get('dependencies',{})) if k != 'npm']" > "$(PKGS_DIR)npm.txt"
	@echo "Done."

# Dumps user-installed gems (skips stdlib default: gems) as "name --version x.y.z".
update-gems:
	@echo "Updating packages/gems.txt..."
	@gem list --local 2>/dev/null | python3 -c "import re,sys; [print('{} --version {}'.format(m.group(1),v)) for line in sys.stdin for m in [re.match(r'^(\S+) \((.+)\)',line.strip())] if m for v in [m.group(2).split(',')[0].strip()] if not v.startswith('default:')]" | sort > "$(PKGS_DIR)gems.txt"
	@echo "Done."

update-skills:
	@python3 $(SCRIPT)

check:
	@python3 $(SCRIPT) --check
