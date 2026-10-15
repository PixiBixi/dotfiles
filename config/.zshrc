# Top of .zshrc
# Same fpath in login, non-login and child shells (inherited FPATH, OrbStack's
# .zprofile hook): any difference makes oh-my-zsh rebuild the compdump, ~1 s.
typeset -U path fpath
fpath=(${fpath:#(/opt/homebrew/share/zsh/site-functions|$HOME/.oh-my-zsh/*)})
fpath+=/Users/jeremy/.orbstack/shell/completions/zsh

# Static copy of `brew shellenv`: the eval forks Ruby-backed brew, ~90 ms per shell.
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
fpath[1,0]="/opt/homebrew/share/zsh/site-functions"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="true"
# oh-my-zsh reads ZSH_DISABLE_COMPFIX; the unprefixed name was a no-op.
ZSH_DISABLE_COMPFIX="true"

# NOTE: compinit runs once, in the oh-my-zsh loader below. A second compinit
# doubles the compdump cost.

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export EDITOR=nvim

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
HIST_STAMPS="mm/dd/yyyy"
export HISTSIZE=1000000000
export SAVEHIST=$HISTSIZE

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder
#


# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(zsh-defer ssh-agent terraform kubectl kube-ps1 helm aws)

# Load differents keys (lazy mode for faster startup)
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent identities id_rsa id_ed25519 gitlab github.com

# Minimal replacement for `source $ZSH/oh-my-zsh.sh`: same libs, plugins and theme,
# without its per-shell compdump checks (git, grep, mkdir, rm) and fork-based probes.
ZSH_CUSTOM="$ZSH/custom"
ZSH_CACHE_DIR="$ZSH/cache"
# ssh-agent names its cache file after it: unset, every shell starts a new agent.
SHORT_HOST="${HOST/.*/}"
fpath=($ZSH_CACHE_DIR/completions $ZSH/{functions,completions} $ZSH_CUSTOM/{functions,completions}
  $ZSH_CUSTOM/plugins/${^plugins}(N/) $ZSH/plugins/${^plugins}(N/) $fpath)

# -C trusts the dump without rescanning fpath: rebuilt when older than 24h.
# After installing a tool that ships a completion: zcomp-rebuild
autoload -Uz compinit
ZSH_COMPDUMP="$HOME/.zcompdump-lite-$ZSH_VERSION"
_zcomp_stale=($ZSH_COMPDUMP(N.mh+24))
if [[ -f $ZSH_COMPDUMP && -z $_zcomp_stale ]]; then
  compinit -C -d "$ZSH_COMPDUMP"
else
  compinit -u -d "$ZSH_COMPDUMP"
  { zcompile "$ZSH_COMPDUMP" } &!
fi
unset _zcomp_stale
zcomp-rebuild() { rm -f "$ZSH_COMPDUMP"{,.zwc} && exec zsh }

# lib/grep.zsh and lib/theme-and-appearance.zsh are inlined below: they fork
# grep, diff and ls on every shell only to detect flags that never change here.
for _lib (async_prompt clipboard cli completion directories functions git history
  key-bindings misc prompt_info_functions termsupport); do
  source "$ZSH/lib/$_lib.zsh"
done
unset _lib
alias grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox,.venv,venv}'
alias egrep='grep -E'
alias fgrep='grep -F'
autoload -U colors && colors
setopt prompt_subst
diff() { command diff --color "$@" }
export LSCOLORS="Gxfxcxdxbxegedabagacad"
export LS_COLORS="di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43"
alias ls='ls -G'

for _plugin ($plugins); do
  if [[ -f $ZSH_CUSTOM/plugins/$_plugin/$_plugin.plugin.zsh ]]; then
    source "$ZSH_CUSTOM/plugins/$_plugin/$_plugin.plugin.zsh"
  else
    source "$ZSH/plugins/$_plugin/$_plugin.plugin.zsh"
  fi
done
unset _plugin
source "$ZSH/themes/$ZSH_THEME.zsh-theme"
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# User configuration

# Defer loading non-critical files for faster startup
zsh-defer -c '[ -f ~/.zsh_functions ] && source ~/.zsh_functions'
zsh-defer -c '[ -f ~/.zsh_work ] && source ~/.zsh_work'
zsh-defer -c '[[ -f ~/.zsh_alias ]] && source ~/.zsh_alias'
zsh-defer -c '[[ $(uname) == "Darwin" ]] && source ~/.zsh_mac'
zsh-defer -c '[[ $(uname) == "Linux" ]] && source ~/.zsh_linux'

# Add kube context to right prompt
RPROMPT='$(kube_ps1)'

# Defer fzf loading
zsh-defer -c '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh'

# Ansible better output
export ANSIBLE_CHECK_MODE_MARKERS=True
export ANSIBLE_SHOW_TASK_PATH_ON_FAILURE=True
export ANSIBLE_CALLBACK_RESULT_FORMAT=yaml

ulimit -n 9999

# Gcloud - lazy load completions for faster startup
source "${HOMEBREW_PREFIX}/share/google-cloud-sdk/path.zsh.inc"

# Lazy load gcloud completion (loads only when first used)
gcloud() {
    unfunction gcloud
    source "${HOMEBREW_PREFIX}/share/google-cloud-sdk/completion.zsh.inc"
    gcloud "$@"
}

# Lazy load kafkactl completion
kafkactl() {
    unfunction kafkactl
    eval "$(command kafkactl completion zsh)"
    kafkactl "$@"
}

# Lazy load delta completion
delta() {
    unfunction delta
    eval "$(command delta --generate-completion=zsh)"
    delta "$@"
}

PATH_DIRS=(
    "/Users/jeremy/.local/bin"
    ${HOMEBREW_PREFIX}/opt/coreutils/libexec/gnubin
    ${HOMEBREW_PREFIX}/bin
    ${HOMEBREW_PREFIX}/sbin
    ${HOME}/.krew/bin
    ${HOME}/.nvm/versions/node/v18.0.0/bin
    ${HOMEBREW_PREFIX}/opt/openssl@1.1/bin
    ${HOME}/go/bin
    ${HOMEBREW_PREFIX}/opt/postgresql@15/bin
    ${HOMEBREW_PREFIX}/opt/gnu-getopt/bin
	${HOME}/.local/bin
)
export PATH=${"${PATH_DIRS[*]}"// /:}:${PATH}

# Terragrunt provider cache server. Replaces TF_PLUGIN_CACHE_DIR: the native
# plugin cache is not concurrency-safe, so a parallel `run --all` has several
# processes writing the same provider binary at once. That leaves the kernel
# with a stale cdhash for the inode and macOS SIGKILLs the plugin on exec
# ("Failed to read any lines from plugin's stdout"). The cache server
# serializes installs instead, and reuses the existing cache
# directory, whose layout is identical to plugin_cache_dir.
export TG_PROVIDER_CACHE=1
export TG_PROVIDER_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
# cairocffi (plugin social de mkdocs) ne trouve pas libcairo : le Python de uv
# ne cherche pas dans Homebrew. Les 3 chemins par défaut sont recopiés exprès,
# dyld REMPLACE sa liste au lieu de l'étendre dès que la variable est définie.
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/lib:$HOME/lib:/usr/local/lib:/usr/lib"

# Claude Code Templates - Global Agents
export PATH="/Users/jeremy/.claude-code-templates/bin:$PATH"

alias claude-mem='bun "/Users/jeremy/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs"'
# Tickler CLI completion: reminder ids with their title.
(( $+commands[tickler] )) && zsh-defer -c 'source <(tickler completion zsh)'
