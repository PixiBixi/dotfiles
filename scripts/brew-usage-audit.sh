#!/usr/bin/env bash
# brew-usage-audit.sh: surface the Homebrew packages you never use
#
# Usage:
#   ./scripts/brew-usage-audit.sh [--stale-days N] [--leaves-only] [--all] [--json FILE]
#
# Signal: access time (atime) of each package's binaries in the Cellar.
# APFS bumps atime on exec, so this catches every invocation path: aliases,
# shell functions, pre-commit hooks, LSP servers, scripts, and commands run by
# coding agents. Shell history catches none of those and is kept only as
# corroborating evidence.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
STALE_DAYS=90
LEAVES_ONLY=false
SHOW_ALL=false
JSON_OUT=""
HISTORY_FILE="${HISTFILE:-${HOME}/.zsh_history}"
BREW_PREFIX="$(brew --prefix 2> /dev/null || echo /opt/homebrew)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# atime within this many seconds of the install receipt means "never run since
# install". A `brew upgrade` rewrites the keg and resets atime to install time.
INSTALL_GRACE=600

# ── Help ──────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Audit installed Homebrew packages and surface the ones you never run.

Options:
  --stale-days N    Flag packages unused for more than N days (default: 90)
  --leaves-only     Only audit leaves (skip packages other formulas depend on)
  --all             List every audited package, not just the flagged ones
  --history FILE    Shell history for corroborating hits (default: \$HISTFILE)
  --json FILE       Also write the full result set as JSON
  -h, --help        Show this help

How usage is measured:
  1. atime of every binary in \$(brew --prefix)/{bin,sbin}, dereferenced into
     the Cellar. Most recent atime across a package's binaries wins.
  2. Compared against the install receipt mtime. A package whose atime never
     moved past its install date is reported as NEVER, with the install date so
     you can tell a year-old unused tool from one reinstalled last week.
  3. Evidence columns resolve the invocation paths atime cannot explain:
     aliases from .zsh_alias, kubectl plugin subcommands, references in
     pre-commit / nvim LSP / init_mac.sh, and raw shell-history hits.

Examples:
  $(basename "$0")                            # flag anything unused 90+ days
  $(basename "$0") --stale-days 180 --leaves-only
  $(basename "$0") --all --json /tmp/audit.json
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stale-days)
            STALE_DAYS="$2"
            shift 2
            ;;
        --leaves-only)
            LEAVES_ONLY=true
            shift
            ;;
        --all)
            SHOW_ALL=true
            shift
            ;;
        --history)
            HISTORY_FILE="$2"
            shift 2
            ;;
        --json)
            JSON_OUT="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
    esac
done

# ── Sanity checks ─────────────────────────────────────────────────────────────
if ! command -v brew &> /dev/null; then
    echo "Error: brew not found" >&2
    exit 1
fi

# GNU coreutils shadows stat(1) and date(1) with incompatible flags when its
# gnubin is on PATH: GNU `date -r` reads a file's mtime instead of formatting an
# epoch. Pin the BSD builds so the report works on any machine.
STAT=/usr/bin/stat
DATE=/bin/date
for tool in "$STAT" "$DATE"; do
    if [[ ! -x "$tool" ]]; then
        echo "Error: $tool not found (this script targets macOS)" >&2
        exit 1
    fi
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

NOW=$("$DATE" +%s)

# ── Step 1: package → binaries, from the bin/ and sbin/ symlinks ─────────────
echo "==> Mapping $BREW_PREFIX/{bin,sbin} symlinks to packages…" >&2

BIN_PKG="${WORK}/bin_pkg.txt" # "binary<TAB>package<TAB>fullpath"

# The symlink target is relative (../Cellar/jq/1.8.1/bin/jq) and identical
# from bin/ and sbin/, so rebuild the absolute Cellar path from it rather than
# guessing which of the two directories the link lived in.
ls -la "${BREW_PREFIX}/bin/" "${BREW_PREFIX}/sbin/" 2> /dev/null \
    | awk -v prefix="$BREW_PREFIX" '/ -> / {
        n = split($0, parts, " -> ")
        target = parts[n]; sub(/[[:space:]].*$/, "", target)
        if (target !~ /\/Cellar\//) next
        pkg = target; sub(/.*\/Cellar\//, "", pkg); sub(/\/.*/, "", pkg)
        bin = parts[1]; sub(/.*[[:space:]]/, "", bin)
        path = target; sub(/^.*\/Cellar\//, prefix "/Cellar/", path)
        print bin "\t" pkg "\t" path
    }' > "$BIN_PKG"

echo "==> $(wc -l < "$BIN_PKG" | tr -d ' ') binaries found" >&2

# ── Step 2: restrict to what we actually asked for ────────────────────────────
if [[ "$LEAVES_ONLY" == true ]]; then
    brew leaves > "${WORK}/wanted.txt"
else
    brew list --formula --installed-on-request 2> /dev/null > "${WORK}/wanted.txt" \
        || brew leaves > "${WORK}/wanted.txt"
fi
brew leaves > "${WORK}/leaves.txt"

awk -F'\t' 'NR==FNR { w[$1]=1; next } $2 in w' \
    "${WORK}/wanted.txt" "$BIN_PKG" > "${WORK}/filtered.txt"

PKG_COUNT=$(cut -f2 "${WORK}/filtered.txt" | sort -u | wc -l | tr -d ' ')
echo "==> Auditing ${PKG_COUNT} packages that ship a CLI binary…" >&2

# ── Step 3: atime per binary (single stat call, never executes anything) ──────
echo "==> Reading binary access times…" >&2

ATIMES="${WORK}/atimes.txt" # "atime<TAB>binary"
# stat(1) exits non-zero if any single path is gone (a keg removed mid-run),
# which pipefail would turn into a hard failure. Tolerate it and keep going.
cut -f3 "${WORK}/filtered.txt" \
    | { xargs "$STAT" -L -f '%a %N' 2> /dev/null || true; } \
    | awk '{ n = split($2, p, "/"); print $1 "\t" p[n] }' > "$ATIMES"

echo "==> $(wc -l < "$ATIMES" | tr -d ' ') access times read" >&2

# ── Step 4: alias resolution, the big blind spot of history-based auditing ───
# `alias cat='bat --style=plain'` means bat is invoked as `cat`, so counting the
# token "bat" in history yields 0 for a tool used all day.
echo "==> Resolving aliases…" >&2

ALIAS_SRC=""
for candidate in "${REPO_DIR}/config/.zsh_alias" "${HOME}/.zsh_alias"; do
    if [[ -f "$candidate" ]]; then
        ALIAS_SRC="$candidate"
        break
    fi
done

ALIAS_MAP="${WORK}/alias_map.txt" # "binary<TAB>alias"
: > "$ALIAS_MAP"
if [[ -n "$ALIAS_SRC" ]]; then
    # alias NAME=TARGET, where TARGET may be quoted, absolute, or wrapped in
    # sudo/command/env (alias mtr="sudo trip" really exercises the trip binary).
    # tr strips " and ' by octal code to keep the awk program quote-free.
    sed -n 's/^[[:space:]]*alias \([A-Za-z0-9_-]*\)=/\1 /p' "$ALIAS_SRC" \
        | tr -d '\42\47' \
        | awk '{
            name = $1
            i = 2
            while (i <= NF && ($i == "sudo" || $i == "command" || $i == "env" || $i == "exec")) i++
            if (i > NF) next
            target = $i
            sub(/^.*\//, "", target)
            if (target == "" || target == name) next
            print target "\t" name
        }' > "$ALIAS_MAP"
    echo "==> $(wc -l < "$ALIAS_MAP" | tr -d ' ') aliases parsed from ${ALIAS_SRC#"$REPO_DIR"/}" >&2
else
    echo "==> No .zsh_alias found, alias evidence unavailable" >&2
fi

# ── Step 5: history frequency, alias-aware and kubectl-plugin-aware ──────────
HISTFREQ="${WORK}/freq.txt"
if [[ -f "$HISTORY_FILE" ]]; then
    strings "$HISTORY_FILE" | sed 's/^: [0-9]*:[0-9]*;//' > "${WORK}/history.txt"
    awk '{
        n = split($0, words, /[^[:alnum:]._@-]+/)
        for (i = 1; i <= n; i++) if (length(words[i]) >= 1) freq[words[i]]++
    }
    END { for (w in freq) print freq[w], w }' "${WORK}/history.txt" > "$HISTFREQ"
else
    : > "$HISTFREQ"
    echo "==> History file not found: $HISTORY_FILE (hits will read 0)" >&2
fi

# ── Step 6: config references: pre-commit, LSP, aliases, provisioning ───────
# A tool wired into a hook or an editor never appears in history and its atime
# only moves when that machinery runs, so name the consumer explicitly.
echo "==> Scanning config for non-interactive consumers…" >&2

CONFIG_FILES=()
while IFS= read -r f; do
    CONFIG_FILES+=("$f")
done < <(
    find \
        "${REPO_DIR}/.pre-commit-config.yaml" \
        "${REPO_DIR}/Makefile" \
        "${REPO_DIR}/scripts" \
        "${REPO_DIR}/config/.zshrc" \
        "${REPO_DIR}/config/.zsh_alias" \
        "${REPO_DIR}/config/.zsh_functions" \
        "${REPO_DIR}/config/.config/nvim/lua" \
        "${REPO_DIR}/config/.tmux.conf" \
        "${REPO_DIR}/apps/claude/settings.json" \
        "${REPO_DIR}/apps/claude/hooks" \
        "${REPO_DIR}/.github" \
        -type f ! -name "$(basename "${BASH_SOURCE[0]}")" 2> /dev/null
)

# ── Step 7: aggregate per package and report ──────────────────────────────────
echo "==> Aggregating…" >&2

RESULTS="${WORK}/results.txt"
: > "$RESULTS"

for pkg in $(cut -f2 "${WORK}/filtered.txt" | sort -u); do
    # most recent atime across the package's binaries
    last_at=$(awk -F'\t' -v p="$pkg" '
        NR==FNR { if ($2 == p) mine[$1]=1; next }
        $2 in mine { if ($1+0 > max) max = $1+0 }
        END { print max+0 }' "${WORK}/filtered.txt" "$ATIMES")

    receipt="${BREW_PREFIX}/opt/${pkg}/INSTALL_RECEIPT.json"
    installed=0
    if [[ -f "$receipt" ]]; then
        installed=$("$STAT" -f '%m' "$receipt")
    fi

    days=$(((NOW - last_at) / 86400))
    never=false
    if [[ "$installed" -gt 0 && "$last_at" -le $((installed + INSTALL_GRACE)) ]]; then
        never=true
    fi

    leaf=dep
    if grep -qxF "$pkg" "${WORK}/leaves.txt"; then
        leaf=leaf
    fi

    size=$({ du -sk "${BREW_PREFIX}/opt/${pkg}/" 2> /dev/null || true; } \
        | awk '{print int($1/1024)}')
    if [[ -z "$size" ]]; then
        size=0
    fi

    # ── evidence ─────────────────────────────────────────────────────────────
    evidence=""

    # aliases pointing at any of this package's binaries
    al=$(awk -F'\t' -v p="$pkg" '
        NR==FNR { if ($2 == p) mine[$1]=1; next }
        $1 in mine { printf "%s%s", (seen++ ? "/" : ""), $2 }
        END { print "" }' "${WORK}/filtered.txt" "$ALIAS_MAP")
    if [[ -n "$al" ]]; then
        evidence="alias ${al}"
    fi

    # kubectl plugins: `kubectl-foo` is typed `kubectl foo`, never `kubectl-foo`
    sub=$(awk -F'\t' -v p="$pkg" '$2 == p && $1 ~ /^kubectl-/ {
        s = $1; sub(/^kubectl-/, "", s); print s; exit }' "${WORK}/filtered.txt")
    if [[ -n "$sub" ]]; then
        evidence="${evidence:+$evidence, }kubectl ${sub}"
    fi

    # config consumers (word-boundary match, first two files only)
    if [[ ${#CONFIG_FILES[@]} -gt 0 ]]; then
        # pipefail turns grep's "no match" exit 1 into a fatal error here
        ref=$({ grep -lwF "$pkg" "${CONFIG_FILES[@]}" 2> /dev/null || true; } \
            | head -2 | sed "s#${REPO_DIR}/##" | tr '\n' ' ' | sed 's/ $//')
        if [[ -n "$ref" ]]; then
            evidence="${evidence:+$evidence, }${ref}"
        fi
    fi

    # raw history hits, counting alias names too
    hits=$(awk -v p="$pkg" '
        FILENAME ~ /filtered/ { if ($2 == p) names[$1]=1; next }
        FILENAME ~ /alias_map/ { if ($1 in names) names[$2]=1; next }
        { if ($2 in names) total += $1 }
        END { print total+0 }' \
        "${WORK}/filtered.txt" "$ALIAS_MAP" "$HISTFREQ")

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$days" "$pkg" "$last_at" "$installed" "$never" "$leaf" "$size" \
        "${evidence:--} [${hits} hits]" >> "$RESULTS"
done

sort -t"$(printf '\t')" -k1,1rn -o "$RESULTS" "$RESULTS"

# ── Report ────────────────────────────────────────────────────────────────────
echo ""
printf '═══════════════════════════════════════════════════════════════════════════════\n'
printf ' Homebrew usage audit   signal: binary atime   stale after %s days\n' "$STALE_DAYS"
printf '═══════════════════════════════════════════════════════════════════════════════\n'
printf '  %-24s %-12s %6s %7s %5s  %s\n' PACKAGE "LAST USE" DAYS SIZE KIND EVIDENCE
printf '  %-24s %-12s %6s %7s %5s  %s\n' ------- -------- ---- ---- ---- --------

flagged=0
freeable=0
while IFS=$'\t' read -r days pkg last_at installed never leaf size evidence; do
    if [[ "$days" -lt "$STALE_DAYS" && "$SHOW_ALL" == false ]]; then
        continue
    fi
    last_str=$("$DATE" -r "$last_at" '+%Y-%m-%d' 2> /dev/null || echo '?')
    mark=""
    if [[ "$never" == true ]]; then
        inst_str=$("$DATE" -r "$installed" '+%Y-%m-%d' 2> /dev/null || echo '?')
        mark=" [never run since install ${inst_str}]"
    fi
    printf '  %-24s %-12s %6s %6sM %5s  %s%s\n' \
        "$pkg" "$last_str" "$days" "$size" "$leaf" "$evidence" "$mark"
    if [[ "$days" -ge "$STALE_DAYS" ]]; then
        flagged=$((flagged + 1))
        if [[ "$leaf" == leaf ]]; then
            freeable=$((freeable + size))
        fi
    fi
done < "$RESULTS"

printf '═══════════════════════════════════════════════════════════════════════════════\n'
printf ' %s package(s) unused for %s+ days, %s MB reclaimable from leaves alone\n' \
    "$flagged" "$STALE_DAYS" "$freeable"

# ── JSON ──────────────────────────────────────────────────────────────────────
if [[ -n "$JSON_OUT" ]]; then
    awk -F'\t' 'BEGIN { print "[" }
    {
        gsub(/"/, "\\\"", $8)
        printf "%s {\"package\":\"%s\",\"days_since_use\":%s,\"last_use_epoch\":%s,", \
            (NR > 1 ? "," : ""), $2, $1, $3
        printf "\"installed_epoch\":%s,\"never_run_since_install\":%s,", $4, $5
        printf "\"kind\":\"%s\",\"size_mb\":%s,\"evidence\":\"%s\"}\n", $6, $7, $8
    }
    END { print "]" }' "$RESULTS" > "$JSON_OUT"
    echo "==> JSON written to $JSON_OUT" >&2
fi

cat << 'EOF'

Reading the report
  EVIDENCE names the invocation path atime cannot show you. A package with an
  alias, a kubectl subcommand, or a pre-commit / LSP consumer is in use even at
  0 history hits. Do not remove it on the day count alone.

  "never run since install" plus a recent install date is inconclusive, not a
  verdict: `brew upgrade` rewrites the keg and resets atime. Let a few weeks
  pass before trusting that line.

Before removing
  brew uses --installed <package>    # who depends on it
  brew uninstall <package>           # then: make update-brew && git commit
EOF
