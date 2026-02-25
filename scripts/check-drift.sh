#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ok=0
warn=0
err=0

# check_file <repo_rel> <deployed_path> <type: symlink|copy|machine>
# - symlink   : must be a symlink pointing to the repo file
# - copy      : must match by md5 (can drift)
# - machine   : machine-specific, diff is expected (informational only)
check_file() {
    local repo_rel="$1"
    local deployed="$2"
    local type="$3"

    local repo_path="${REPO_DIR}/${repo_rel}"
    local label
    label="$(printf '%-45s' "${repo_rel}")"

    # File missing from repo
    if [[ ! -f "${repo_path}" ]]; then
        printf "  ${DIM}~ SKIP       ${NC}  %s  ${DIM}[not in repo]${NC}\n" "${label}"
        return
    fi

    # File not deployed
    if [[ ! -e "${deployed}" && ! -L "${deployed}" ]]; then
        if [[ "${type}" == "machine" ]]; then
            printf "  ${DIM}~ SKIP       ${NC}  %s  ${DIM}[not deployed]${NC}\n" "${label}"
        else
            printf "  ${RED}✗ NOT DEPLOYED${NC}  %s\n" "${label}"
            ((err++)) || true
        fi
        return
    fi

    case "${type}" in
        symlink)
            if [[ -L "${deployed}" ]]; then
                local target
                target="$(readlink "${deployed}")"
                if [[ "${target}" == "${repo_path}" ]]; then
                    printf "  ${GREEN}✓ OK        ${NC}  %s  ${CYAN}[symlink]${NC}\n" "${label}"
                    ((ok++)) || true
                else
                    printf "  ${YELLOW}⚠ WRONG LINK${NC}  %s  → %s\n" "${label}" "${target}"
                    ((warn++)) || true
                fi
            else
                local src_md5 dst_md5
                src_md5=$(md5 -q "${repo_path}")
                dst_md5=$(md5 -q "${deployed}")
                if [[ "${src_md5}" == "${dst_md5}" ]]; then
                    printf "  ${YELLOW}⚠ NOT LINKED${NC}  %s  [copy, in sync — run init_mac.sh]\n" "${label}"
                else
                    printf "  ${RED}✗ NOT LINKED${NC}  %s  [copy, DRIFT — run init_mac.sh]\n" "${label}"
                    ((err++)) || true
                fi
                ((warn++)) || true
            fi
            ;;
        copy)
            local src_md5 dst_md5
            src_md5=$(md5 -q "${repo_path}")
            dst_md5=$(md5 -q "${deployed}")
            if [[ "${src_md5}" == "${dst_md5}" ]]; then
                printf "  ${GREEN}✓ OK        ${NC}  %s  ${CYAN}[copy]${NC}\n" "${label}"
                ((ok++)) || true
            else
                printf "  ${YELLOW}⚠ DRIFT     ${NC}  %s  [copy] sync with: cp %s %s\n" \
                    "${label}" "${deployed}" "${repo_path}"
                ((warn++)) || true
            fi
            ;;
        machine)
            local src_md5 dst_md5
            src_md5=$(md5 -q "${repo_path}")
            dst_md5=$(md5 -q "${deployed}")
            if [[ "${src_md5}" == "${dst_md5}" ]]; then
                printf "  ${GREEN}✓ OK        ${NC}  %s  ${DIM}[machine-specific]${NC}\n" "${label}"
                ((ok++)) || true
            else
                printf "  ${BLUE}~ DIFF      ${NC}  %s  ${DIM}[machine-specific, expected]${NC}\n" "${label}"
            fi
            ;;
    esac
}

echo
printf "${BOLD}Dotfiles drift check${NC}  ${DIM}repo: ${REPO_DIR}${NC}\n"

# ── config/ ────────────────────────────────────────────────────────────────
echo
printf "${BOLD}config/ → \$HOME${NC}\n"

check_file "config/.zshrc" "${HOME}/.zshrc" symlink
check_file "config/.zsh_alias" "${HOME}/.zsh_alias" symlink
check_file "config/.zsh_functions" "${HOME}/.zsh_functions" symlink
check_file "config/.zsh_mac" "${HOME}/.zsh_mac" symlink
check_file "config/.zsh_linux" "${HOME}/.zsh_linux" machine
check_file "config/.wezterm.lua" "${HOME}/.wezterm.lua" symlink
check_file "config/.markdownlint.json" "${HOME}/.markdownlint.json" symlink
check_file "config/.gitconfig" "${HOME}/.gitconfig" symlink
check_file "config/.gitconfig_perso" "${HOME}/.gitconfig_perso" symlink
check_file "config/.tmux.conf" "${HOME}/.tmux.conf" symlink
check_file "config/.vimrc" "${HOME}/.vimrc" symlink
check_file "config/.gitconfig_work" "${HOME}/.gitconfig_work" machine
check_file "config/.ssh/config" "${HOME}/.ssh/config" machine
check_file "config/.kube/switch-config.yaml" "${HOME}/.kube/switch-config.yaml" machine

# ── apps/claude/ ───────────────────────────────────────────────────────────
echo
printf "${BOLD}apps/claude/ → ~/.claude${NC}\n"

check_file "apps/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md" symlink
check_file "apps/claude/settings.json" "${HOME}/.claude/settings.json" symlink

# ── Summary ────────────────────────────────────────────────────────────────
echo
printf "${BOLD}Summary:${NC}  ${GREEN}${ok} ok${NC}  ${YELLOW}${warn} warnings${NC}  ${RED}${err} errors${NC}\n"
echo

[[ ${err} -eq 0 ]]
