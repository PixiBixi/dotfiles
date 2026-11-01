# shellcheck shell=bash
# Environment shared by zsh (.zshrc) and bash (.bashrc). Bash is the shell of
# Claude Code's Bash tool (CLAUDE_CODE_SHELL), so anything a command needs lives
# here, not in .zshrc. Syntax both shells read; aliases, completions, prompt stay in zsh.

# .zshenv realigns USER for zsh; bash does not read it.
[ -n "${ZSH_VERSION:-}" ] || {
    USER="$(id -un)"
    export USER
}

# Static copy of `brew shellenv`: the eval forks Ruby-backed brew, ~90 ms per shell.
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

# First entry wins: gnubin shadows the BSD date/stat on purpose.
PATH="${HOME}/.claude-code-templates/bin\
:${HOME}/.local/bin\
:${HOMEBREW_PREFIX}/opt/coreutils/libexec/gnubin\
:${HOMEBREW_PREFIX}/bin\
:${HOMEBREW_PREFIX}/sbin\
:${HOME}/.krew/bin\
:${HOMEBREW_PREFIX}/opt/openssl@1.1/bin\
:${HOME}/go/bin\
:${HOMEBREW_PREFIX}/opt/postgresql@15/bin\
:${HOMEBREW_PREFIX}/opt/gnu-getopt/bin\
:${HOMEBREW_PREFIX}/share/google-cloud-sdk/bin\
:${HOME}/.orbstack/bin\
${PATH:+:${PATH}}"
export PATH

export EDITOR=nvim

# Ansible better output
export ANSIBLE_CHECK_MODE_MARKERS=True
export ANSIBLE_SHOW_TASK_PATH_ON_FAILURE=True
export ANSIBLE_CALLBACK_RESULT_FORMAT=yaml

# Terragrunt provider cache server. Replaces TF_PLUGIN_CACHE_DIR: the native
# plugin cache is not concurrency-safe, a parallel `run --all` gets the plugin
# SIGKILLed by macOS ("Failed to read any lines from plugin's stdout").
export TG_PROVIDER_CACHE=1
export TG_PROVIDER_CACHE_DIR="${HOME}/.terraform.d/plugin-cache"

# cairocffi (mkdocs social plugin) does not find libcairo: uv's Python does not
# search Homebrew. dyld REPLACES its default list once this is set, hence the copies.
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:${HOME}/lib:/usr/local/lib:/usr/lib"

ulimit -n 9999

# Work environment and secrets: machine-local, never in this public repo.
# shellcheck source=/dev/null
[ -f "${HOME}/.config/shell/work-env.sh" ] && . "${HOME}/.config/shell/work-env.sh"
