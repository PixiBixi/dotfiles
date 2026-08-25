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
                    printf "  ${YELLOW}⚠ NOT LINKED${NC}  %s  [copy, in sync: run init_mac.sh]\n" "${label}"
                else
                    printf "  ${RED}✗ NOT LINKED${NC}  %s  [copy, DRIFT: run init_mac.sh]\n" "${label}"
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

# Directory variant of check_file: skills deploy as symlinked directories.
check_dir() {
    local repo_rel="$1"
    local deployed="$2"

    local repo_path="${REPO_DIR}/${repo_rel}"
    local label
    label="$(printf '%-45s' "${repo_rel}")"

    if [[ ! -d "${repo_path}" ]]; then
        printf "  ${DIM}~ SKIP       ${NC}  %s  ${DIM}[not in repo]${NC}\n" "${label}"
        return
    fi

    if [[ ! -e "${deployed}" && ! -L "${deployed}" ]]; then
        printf "  ${RED}✗ NOT DEPLOYED${NC}  %s\n" "${label}"
        ((err++)) || true
        return
    fi

    if [[ -L "${deployed}" ]]; then
        local target
        target="$(readlink "${deployed}")"
        # setup_claude() links with a trailing slash, strip it before comparing
        if [[ "${target%/}" == "${repo_path%/}" ]]; then
            printf "  ${GREEN}✓ OK        ${NC}  %s  ${CYAN}[symlink]${NC}\n" "${label}"
            ((ok++)) || true
        else
            printf "  ${YELLOW}⚠ WRONG LINK${NC}  %s  → %s\n" "${label}" "${target}"
            ((warn++)) || true
        fi
    else
        # A real directory means an external installer owns it, see CLAUDE.md
        printf "  ${YELLOW}⚠ NOT LINKED${NC}  %s  [real dir, run init_mac.sh]\n" "${label}"
        ((warn++)) || true
    fi
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
check_file "config/.config/git/allowed_signers" "${HOME}/.config/git/allowed_signers" symlink
check_file "config/.config/git/ignore" "${HOME}/.config/git/ignore" symlink

# ── apps/claude/ ───────────────────────────────────────────────────────────
echo
printf "${BOLD}apps/claude/ → ~/.claude${NC}\n"

check_file "apps/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md" symlink
check_file "apps/claude/settings.json" "${HOME}/.claude/settings.json" symlink

for hook in "${REPO_DIR}/apps/claude/hooks/"*.sh; do
    [[ -f "${hook}" ]] || continue
    name="$(basename "${hook}")"
    check_file "apps/claude/hooks/${name}" "${HOME}/.claude/hooks/${name}" symlink
done

# Orphans: a deployed hook with no repo counterpart is still wired into
# settings.json but nothing versions it. session-allow.py survived this way.
for deployed in "${HOME}/.claude/hooks/"*; do
    [[ -e "${deployed}" ]] || continue
    name="$(basename "${deployed}")"
    [[ -e "${REPO_DIR}/apps/claude/hooks/${name}" ]] && continue
    printf "  ${YELLOW}⚠ ORPHAN    ${NC}  %-45s  [deployed, absent from repo]\n" \
        "hooks/${name}"
    ((warn++)) || true
done

# Hook configs. A hook whose config is missing falls back to its built-in defaults
# instead of erroring, so the only visible symptom is a rule quietly not enforced.
for conf in "${REPO_DIR}/apps/claude/config/"*.json; do
    [[ -f "${conf}" ]] || continue
    name="$(basename "${conf}")"
    check_file "apps/claude/config/${name}" "${HOME}/.claude/${name}" symlink
done

for skill_dir in "${REPO_DIR}/apps/claude/skills"/*/; do
    [[ -d "${skill_dir}" ]] || continue
    name="$(basename "${skill_dir}")"
    check_dir "apps/claude/skills/${name}" "${HOME}/.claude/skills/${name}"
done

# ── packages/krew-indexes.txt → krew ───────────────────────────────────────
# A missing index is silent until brew bundle hits a `krew "<index>/<plugin>"`
# entry and fails: krew never auto-adds anything but `default`.
echo
printf "${BOLD}packages/krew-indexes.txt → krew${NC}\n"

krew_index_file="${REPO_DIR}/packages/krew-indexes.txt"

if ! command -v kubectl-krew &> /dev/null; then
    printf "  ${DIM}~ SKIP       ${NC}  %-45s  ${DIM}[krew not installed]${NC}\n" \
        "packages/krew-indexes.txt"
elif [[ ! -f "${krew_index_file}" ]]; then
    printf "  ${DIM}~ SKIP       ${NC}  %-45s  ${DIM}[not in repo]${NC}\n" \
        "packages/krew-indexes.txt"
else
    # stderr carries krew's PATH warning, drop it so awk only sees the table
    registered="$(kubectl-krew index list 2> /dev/null | awk 'NR > 1 {print $1"\t"$2}')"

    while read -r idx_name idx_url; do
        [[ -z "${idx_name}" || "${idx_name}" == \#* ]] && continue

        label="$(printf '%-45s' "krew index ${idx_name}")"
        current="$(printf '%s\n' "${registered}" | awk -F'\t' -v n="${idx_name}" '$1 == n {print $2}')"

        if [[ -z "${current}" ]]; then
            printf "  ${RED}✗ NOT REGISTERED${NC}  %s  [kubectl krew index add %s %s]\n" \
                "${label}" "${idx_name}" "${idx_url}"
            ((err++)) || true
        elif [[ "${current}" != "${idx_url}" ]]; then
            printf "  ${YELLOW}⚠ WRONG URL ${NC}  %s  → %s\n" "${label}" "${current}"
            ((warn++)) || true
        else
            printf "  ${GREEN}✓ OK        ${NC}  %s  ${CYAN}[index]${NC}\n" "${label}"
            ((ok++)) || true
        fi
    done < "${krew_index_file}"

    # Orphans: an index used locally but unversioned is lost on the next machine
    while IFS=$'\t' read -r idx_name _; do
        [[ -z "${idx_name}" || "${idx_name}" == "default" ]] && continue
        awk -v n="${idx_name}" '$1 == n {found = 1} END {exit !found}' \
            "${krew_index_file}" && continue
        printf "  ${YELLOW}⚠ ORPHAN    ${NC}  %-45s  [registered, absent from repo]\n" \
            "krew index ${idx_name}"
        ((warn++)) || true
    done <<< "${registered}"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo
printf "${BOLD}Summary:${NC}  ${GREEN}${ok} ok${NC}  ${YELLOW}${warn} warnings${NC}  ${RED}${err} errors${NC}\n"
echo

[[ ${err} -eq 0 ]]
