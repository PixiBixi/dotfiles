ROOT_DIR   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PKGS_DIR   := $(ROOT_DIR)packages/
SKILLS_DIR := $(ROOT_DIR)apps/claude/skills/
SCRIPT     := $(SKILLS_DIR).update-skills.py

.DEFAULT_GOAL := help

.PHONY: help update update-brew update-npm update-gems update-skills check

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

update: update-brew update-npm update-gems update-skills ## Update all (brew, npm, gems, skills)

update-brew: ## Dump installed Homebrew packages → packages/Brewfile
	@echo "Updating packages/Brewfile..."
	@brew bundle dump --force --no-describe --file="$(PKGS_DIR)Brewfile"
	@echo "Done."

update-npm: ## Dump global npm packages → packages/npm.txt
	@npm list -g --depth=0 --json 2>/dev/null | python3 -c "import json,sys; [print(k) for k in sorted(json.load(sys.stdin).get('dependencies',{})) if k != 'npm']" > "$(PKGS_DIR)npm.txt"
	@echo "Done."

update-gems: ## Dump installed gems → packages/gems.txt (skips stdlib default: gems)
	@gem list --local 2>/dev/null | python3 -c "import re,sys; [print('{} --version {}'.format(m.group(1),v)) for line in sys.stdin for m in [re.match(r'^(\S+) \((.+)\)',line.strip())] if m for v in [m.group(2).split(',')[0].strip()] if not v.startswith('default:')]" | sort > "$(PKGS_DIR)gems.txt"
	@echo "Done."

update-skills: ## Fetch latest SKILL.md from upstream sources
	@python3 $(SCRIPT)

check: ## Show skills diffs without modifying files (dry-run)
	@python3 $(SCRIPT) --check
