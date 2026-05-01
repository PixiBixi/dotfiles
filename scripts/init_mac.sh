#!/usr/bin/env bash
set -euo pipefail

# Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Script and repo directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SCRIPT_DIR
readonly REPO_DIR

# Logging functions
log_info() {
    echo -e "${BLUE}▶${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*" >&2
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
    fi
}
trap cleanup EXIT

# Ordered step registry: name:function
STEPS=(
    "xcode:install_xcode_tools"
    "homebrew:install_homebrew"
    "oh-my-zsh:install_oh_my_zsh"
    "zsh-plugins:install_zsh_plugins"
    "dotfiles:setup_dotfiles"
    "brew-packages:install_brew_packages"
    "fzf:setup_fzf"
    "gcloud:setup_gcloud_auth"
    "kubeswitch:setup_kubeswitch"
    "krew:install_krew_plugins"
    "directories:setup_directories"
    "npm:install_npm_packages"
    "gems:install_gem_packages"
    "neovim:setup_neovim"
    "claude:setup_claude"
    "rtk:setup_rtk"
)

ONLY_STEPS=()
SKIP_STEPS=()

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --only <step> [step...]   Run only the specified steps
  --skip <step> [step...]   Skip the specified steps
  --list                    List available steps and exit
  -h, --help                Show this help and exit

Examples:
  $(basename "$0") --only dotfiles claude
  $(basename "$0") --skip gcloud neovim
  $(basename "$0") --list
EOF
}

list_steps() {
    echo "Available steps:"
    for entry in "${STEPS[@]}"; do
        echo "  ${entry%%:*}"
    done
}

validate_step_names() {
    local -a provided=("$@")
    for name in "${provided[@]}"; do
        local found=0
        for entry in "${STEPS[@]}"; do
            [[ "${entry%%:*}" == "${name}" ]] && found=1 && break
        done
        if [[ ${found} -eq 0 ]]; then
            log_error "Unknown step: ${name}"
            log_info "Run '$(basename "$0") --list' to see available steps"
            exit 1
        fi
    done
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only)
                shift
                while [[ $# -gt 0 && "${1}" != --* ]]; do
                    ONLY_STEPS+=("$1")
                    shift
                done
                ;;
            --skip)
                shift
                while [[ $# -gt 0 && "${1}" != --* ]]; do
                    SKIP_STEPS+=("$1")
                    shift
                done
                ;;
            --list)
                list_steps
                exit 0
                ;;
            -h | --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ ${#ONLY_STEPS[@]} -gt 0 && ${#SKIP_STEPS[@]} -gt 0 ]]; then
        log_error "--only and --skip are mutually exclusive"
        exit 1
    fi

    validate_step_names "${ONLY_STEPS[@]+"${ONLY_STEPS[@]}"}"
    validate_step_names "${SKIP_STEPS[@]+"${SKIP_STEPS[@]}"}"
}

should_run() {
    local step="$1"

    if [[ ${#ONLY_STEPS[@]} -gt 0 ]]; then
        for s in "${ONLY_STEPS[@]}"; do
            [[ "${s}" == "${step}" ]] && return 0
        done
        return 1
    fi

    for s in "${SKIP_STEPS[@]}"; do
        [[ "${s}" == "${step}" ]] && return 1
    done

    return 0
}

run_step() {
    local name="$1"
    local func="$2"

    if should_run "${name}"; then
        "${func}"
    else
        log_info "Skipping ${name}"
    fi
}

# Deploy a single file: symlink or copy
# Usage: deploy_file symlink|copy <src_rel>
deploy_file() {
    local mode="$1"
    local src_rel="$2"
    local src="${REPO_DIR}/${src_rel}"
    local dest="${HOME}/${src_rel#config/}"

    if [[ ! -f "${src}" ]]; then
        log_warning "${src_rel} not found in repo, skipping"
        return 0
    fi

    mkdir -p "$(dirname "${dest}")"
    if [[ "${mode}" == "symlink" ]]; then
        ln -sf "${src}" "${dest}"
        log_success "Symlinked ${src_rel} → ${dest}"
    else
        cp -f "${src}" "${dest}"
        log_success "Copied ${src_rel} to ${dest}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only"
        exit 1
    fi

    log_success "Running on macOS"
}

# Install Xcode Command Line Tools
install_xcode_tools() {
    log_info "Checking Xcode Command Line Tools..."

    if xcode-select -p &> /dev/null; then
        log_success "Xcode Command Line Tools already installed"
        return 0
    fi

    log_info "Installing Xcode Command Line Tools..."
    xcode-select --install

    log_warning "Please complete the Xcode installation and re-run this script"
    exit 0
}

# Install Homebrew
install_homebrew() {
    log_info "Checking Homebrew installation..."

    if command -v brew &> /dev/null; then
        log_success "Homebrew already installed"
        return 0
    fi

    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    log_success "Homebrew installed"
}

# Install oh-my-zsh
install_oh_my_zsh() {
    log_info "Checking oh-my-zsh installation..."

    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        log_success "oh-my-zsh already installed"
        return 0
    fi

    log_info "Installing oh-my-zsh..."
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    log_success "oh-my-zsh installed"
}

# Install ZSH plugins
install_zsh_plugins() {
    log_info "Installing ZSH plugins..."

    local custom_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
    local plugins=(
        "zsh-defer|https://github.com/romkatv/zsh-defer"
        "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
        "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
    )

    for plugin_info in "${plugins[@]}"; do
        local plugin_name="${plugin_info%%|*}"
        local plugin_url="${plugin_info##*|}"
        local plugin_path="${custom_dir}/plugins/${plugin_name}"

        if [[ -d "${plugin_path}" ]]; then
            log_success "Plugin ${plugin_name} already installed"
        else
            log_info "Installing ${plugin_name}..."
            git clone "${plugin_url}" "${plugin_path}"
            log_success "Plugin ${plugin_name} installed"
        fi
    done
}

# Setup dotfiles
setup_dotfiles() {
    log_info "Setting up dotfiles..."

    # Non-machine-specific: symlink so live and repo stay in sync
    local symlink_files=(
        "config/.zshrc"
        "config/.zsh_alias"
        "config/.zsh_functions"
        "config/.zsh_mac"
        "config/.zsh_linux"
        "config/.wezterm.lua"
        "config/.markdownlint.json"
        "config/.gitconfig"
        "config/.gitconfig_perso"
        "config/.tmux.conf"
        "config/.vimrc"
    )

    for src_rel in "${symlink_files[@]}"; do
        deploy_file symlink "${src_rel}"
    done

    # Machine-specific: copy (do not symlink, differs per machine)
    local copy_files=(
        "config/.gitconfig_work"
    )

    for src_rel in "${copy_files[@]}"; do
        deploy_file copy "${src_rel}"
    done
}

# Configure RTK hook for Claude Code
setup_rtk() {
    log_info "Setting up RTK hook for Claude Code..."

    if ! command -v rtk &> /dev/null; then
        log_warning "rtk not found, skipping hook configuration"
        return 0
    fi

    rtk init --global
    log_success "RTK hook configured ($(rtk --version))"
}

# Setup Claude Code configuration
setup_claude() {
    log_info "Setting up Claude Code configuration..."

    mkdir -p "${HOME}/.claude"

    # Non-machine-specific: symlink
    ln -sf "${REPO_DIR}/apps/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
    log_success "Symlinked apps/claude/CLAUDE.md → ${HOME}/.claude/CLAUDE.md"

    if [[ -f "${REPO_DIR}/apps/claude/settings.json" ]]; then
        ln -sf "${REPO_DIR}/apps/claude/settings.json" "${HOME}/.claude/settings.json"
        log_success "Symlinked apps/claude/settings.json → ${HOME}/.claude/settings.json"
    else
        log_warning "apps/claude/settings.json not found, skipping"
    fi
}

# Setup Neovim with Mason
setup_neovim() {
    log_info "Setting up Neovim configuration..."

    if ! command -v nvim &> /dev/null; then
        log_warning "Neovim not found, skipping configuration"
        return 0
    fi

    # Sync nvim config (rsync preserves dotfiles correctly)
    if [[ -d "${REPO_DIR}/config/.config/nvim" ]]; then
        mkdir -p "${HOME}/.config/nvim"
        rsync -a "${REPO_DIR}/config/.config/nvim/" "${HOME}/.config/nvim/"
        log_success "Copied Neovim configuration"
    else
        log_warning "Neovim config not found in ${REPO_DIR}/config/.config/nvim"
        return 0
    fi

    # Install Packer if not present
    local packer_path="${HOME}/.local/share/nvim/site/pack/packer/start/packer.nvim"
    if [[ ! -d "${packer_path}" ]]; then
        log_info "Installing Packer..."
        git clone --depth 1 https://github.com/wbthomason/packer.nvim "${packer_path}"
        log_success "Packer installed"
    fi

    # Install plugins with Packer
    log_info "Installing Neovim plugins (this may take a minute)..."
    nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync' 2>&1 | grep -v "^$" || true
    log_success "Neovim plugins installed"

    # Install LSP servers with Mason
    log_info "Installing LSP servers with Mason..."
    local lsp_servers=(
        "ansible-language-server"
        "bash-language-server"
        "dockerfile-language-server"
        "pyright"
        "terraform-ls"
        "tflint"
        "yaml-language-server"
    )

    local install_cmd
    install_cmd="MasonInstall $(printf '%s ' "${lsp_servers[@]}")"
    nvim --headless -c "${install_cmd}" -c "qall" 2>&1 | grep -v "^$" || true
    log_success "LSP servers installed via Mason"
    log_info "Run ':Mason' in Neovim to verify installations"
}

# Install Homebrew packages
install_brew_packages() {
    log_info "Installing Homebrew packages..."

    if [[ ! -f "${REPO_DIR}/packages/Brewfile" ]]; then
        log_error "Brewfile not found in ${REPO_DIR}/packages"
        return 1
    fi

    brew bundle install --file="${REPO_DIR}/packages/Brewfile"
    log_success "Homebrew packages installed"
}

# Setup fzf
setup_fzf() {
    log_info "Setting up fzf..."

    local fzf_prefix
    fzf_prefix="$(brew --prefix fzf 2> /dev/null)" || true

    if [[ -f "${fzf_prefix}/install" ]]; then
        "${fzf_prefix}/install" --all
        log_success "fzf configured"
    else
        log_warning "fzf not found, skipping configuration"
    fi
}

# Setup Google Cloud Application Default Credentials
setup_gcloud_auth() {
    log_info "Setting up Google Cloud Application Default Credentials..."

    if ! command -v gcloud &> /dev/null; then
        log_warning "gcloud not found, skipping ADC setup"
        return 0
    fi

    local adc_file="${HOME}/.config/gcloud/application_default_credentials.json"
    if [[ -f "${adc_file}" ]]; then
        log_success "Google Cloud ADC already configured"
        return 0
    fi

    log_info "Configuring Application Default Credentials (a browser window will open)..."
    gcloud auth application-default login
    log_success "Google Cloud ADC configured"
}

# Setup kubeswitch
setup_kubeswitch() {
    log_info "Setting up kubeswitch..."

    if [[ ! -d "${HOME}/.kube" ]]; then
        if [[ -d "${REPO_DIR}/config/.kube" ]]; then
            cp -r "${REPO_DIR}/config/.kube" "${HOME}/.kube"
            log_success "Copied .kube directory"
        else
            log_warning ".kube directory not found in ${REPO_DIR}/config, skipping"
        fi
    else
        if [[ -f "${REPO_DIR}/config/.kube/switch-config.yaml" ]]; then
            cp "${REPO_DIR}/config/.kube/switch-config.yaml" "${HOME}/.kube/"
            log_success "Copied switch-config.yaml"
        else
            log_warning "switch-config.yaml not found, skipping"
        fi
    fi
}

# Install krew plugins
install_krew_plugins() {
    log_info "Installing krew plugins..."

    if ! command -v kubectl-krew &> /dev/null; then
        log_warning "kubectl-krew not found, skipping plugin installation"
        return 0
    fi

    if [[ ! -f "${REPO_DIR}/packages/krew.txt" ]]; then
        log_warning "packages/krew.txt file not found, skipping"
        return 0
    fi

    while IFS= read -r plugin; do
        [[ -z "${plugin}" ]] && continue
        [[ "${plugin}" =~ ^# ]] && continue
        if kubectl krew list | grep -qx "${plugin}"; then
            log_success "Krew plugin ${plugin} already installed"
        else
            log_info "Installing krew plugin: ${plugin}"
            kubectl krew install "${plugin}" || log_warning "Failed to install ${plugin}"
        fi
    done < "${REPO_DIR}/packages/krew.txt"

    log_success "Krew plugins processed"
}

# Setup directory structure
setup_directories() {
    log_info "Setting up directory structure..."

    mkdir -p "${HOME}/Documents/perso/git"
    mkdir -p "${HOME}/Documents/work/git"

    log_success "Directory structure created"
}

# Install NPM packages
install_npm_packages() {
    log_info "Installing NPM packages..."

    if ! command -v npm &> /dev/null; then
        log_warning "npm not found, skipping NPM packages"
        return 0
    fi

    if [[ ! -f "${REPO_DIR}/packages/npm.txt" ]]; then
        log_warning "packages/npm.txt not found, skipping"
        return 0
    fi

    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        [[ "${pkg}" =~ ^# ]] && continue
        log_info "Installing npm package: ${pkg}"
        npm install --global "${pkg}" || log_warning "Failed to install npm package ${pkg}"
    done < "${REPO_DIR}/packages/npm.txt"

    log_success "NPM packages installed"
}

# Install Gem packages
install_gem_packages() {
    log_info "Installing Gem packages..."

    if ! command -v gem &> /dev/null; then
        log_warning "gem not found, skipping Gem packages"
        return 0
    fi

    if [[ ! -f "${REPO_DIR}/packages/gems.txt" ]]; then
        log_warning "packages/gems.txt not found, skipping"
        return 0
    fi

    while IFS= read -r gem_name; do
        [[ -z "${gem_name}" ]] && continue
        [[ "${gem_name}" =~ ^# ]] && continue
        log_info "Installing gem: ${gem_name}"
        gem install "${gem_name}" || log_warning "Failed to install ${gem_name}"
    done < "${REPO_DIR}/packages/gems.txt"

    log_success "Gem packages processed"
}

# Main execution
main() {
    parse_args "$@"

    log_info "Starting macOS initialization..."
    echo

    check_prerequisites
    run_step "xcode" install_xcode_tools
    run_step "homebrew" install_homebrew
    run_step "oh-my-zsh" install_oh_my_zsh
    run_step "zsh-plugins" install_zsh_plugins
    run_step "dotfiles" setup_dotfiles
    run_step "brew-packages" install_brew_packages
    run_step "fzf" setup_fzf
    run_step "gcloud" setup_gcloud_auth
    run_step "kubeswitch" setup_kubeswitch
    run_step "krew" install_krew_plugins
    run_step "directories" setup_directories
    run_step "npm" install_npm_packages
    run_step "gems" install_gem_packages
    run_step "neovim" setup_neovim
    run_step "claude" setup_claude
    run_step "rtk" setup_rtk

    echo
    log_success "macOS initialization complete!"
    echo
    log_info "Next steps:"
    echo "  • Split your kubeconfig file using: kubectl konfig split"
    echo "  • Restart your terminal or run: source ~/.zshrc"
    echo "  • Configure your git identity in ~/.gitconfig_perso and ~/.gitconfig_work"
    echo "  • Open Neovim and verify LSP servers with :Mason"
}

main "$@"
