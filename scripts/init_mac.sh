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

    # Copy nvim config (explicit glob to include dotfiles like .gitignore)
    if [[ -d "${REPO_DIR}/config/.config/nvim" ]]; then
        mkdir -p "${HOME}/.config/nvim"
        cp -rf "${REPO_DIR}/config/.config/nvim/"* "${HOME}/.config/nvim/"
        cp -f "${REPO_DIR}/config/.config/nvim/".* "${HOME}/.config/nvim/" 2> /dev/null || true
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

    for server in "${lsp_servers[@]}"; do
        log_info "Installing ${server}..."
        nvim --headless -c "MasonInstall ${server}" -c "qall" 2>&1 | grep -v "^$" || true
    done

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
    log_info "Starting macOS initialization..."
    echo

    check_prerequisites
    install_xcode_tools
    install_homebrew
    install_oh_my_zsh
    install_zsh_plugins
    setup_dotfiles
    install_brew_packages
    setup_fzf
    setup_gcloud_auth
    setup_kubeswitch
    install_krew_plugins
    setup_directories
    install_npm_packages
    install_gem_packages
    setup_neovim
    setup_claude
    setup_rtk

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
