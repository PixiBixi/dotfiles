# Top of .zshrc
# Initialize Homebrew (needed for HOMEBREW_PREFIX)
eval "$(/opt/homebrew/bin/brew shellenv)"

DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="true"
DISABLE_COMPFIX="true"

# Smarter completion initialization
autoload -Uz compinit
if [ "$(date +'%j')" != "$(stat -f '%Sm' -t '%j' ~/.zcompdump 2>/dev/null)" ]; then
    compinit
else
    compinit -C
fi

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
# DISABLE_UNTRACKED_FILES_DIRTY="true"

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
plugins=(zsh-defer ssh-agent terraform kubectl kube-ps1 helm battery aws)

# Load differents keys (lazy mode for faster startup)
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent identities id_rsa id_ed25519 gitlab github.com

source $ZSH/oh-my-zsh.sh

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

export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"

# Claude Code Templates - Global Agents
export PATH="/Users/jeremy/.claude-code-templates/bin:$PATH"
