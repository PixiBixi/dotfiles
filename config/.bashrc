# shellcheck shell=bash
# Bash is the shell of Claude Code's Bash tool (CLAUDE_CODE_SHELL in
# apps/claude/settings.json); zsh stays the interactive shell.
# shellcheck source=/dev/null
[ -f ~/.config/shell/env.sh ] && . ~/.config/shell/env.sh
# shellcheck source=/dev/null
[ -f ~/.fzf.bash ] && . ~/.fzf.bash

alias claude-mem='/Users/jeremy/.bun/bin/bun "/Users/jeremy/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs"'
