#!/usr/bin/env bash
# brew-usage-audit.sh — Audit Homebrew packages vs shell history usage
#
# Usage:
#   ./scripts/brew-usage-audit.sh [--days N] [--threshold N] [--leaves-only]
#
# Options:
#   --days N          Only consider history entries from the last N days (default: all)
#   --threshold N     Flag packages with fewer than N history hits (default: 3)
#   --leaves-only     Only audit leaf packages (not deps of other packages)
#
# Strategy (fast path — no `brew list <pkg>` per package):
#   1. Scan /opt/homebrew/{bin,sbin} symlinks → extract pkg→binaries map
#   2. Single awk pass over history → word frequency table
#   3. Look up each binary's frequency → aggregate per package
#   Total: ~5-15s vs ~3-10min for the naive approach

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
THRESHOLD=3
LEAVES_ONLY=false
HISTORY_FILE="${HISTFILE:-${HOME}/.zsh_history}"
DAYS=""

# ── Help ──────────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Audit Homebrew packages against your shell history to surface tools you never use.

Options:
  --days N          Only consider history entries from the last N days (default: all)
  --threshold N     Report packages with fewer than N history hits (default: 3)
  --leaves-only     Only audit leaf packages (not required by other packages)
  --history FILE    Path to shell history file (default: \$HISTFILE or ~/.zsh_history)
  -h, --help        Show this help

Strategy (fast — no \`brew list <pkg>\` per package):
  1. Scan /opt/homebrew/{bin,sbin} symlinks  → build pkg→binaries map  (~0.05s)
  2. Single awk pass over history            → word frequency table     (~0.5s)
  3. Look up each binary in freq table       → aggregate per package    (~instant)

Examples:
  $(basename "$0")                          # all history, flag < 3 hits
  $(basename "$0") --days 90 --threshold 5  # last 90 days, flag < 5 hits
  $(basename "$0") --leaves-only            # skip dependency-only packages
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --days)
            DAYS="$2"
            shift 2
            ;;
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --leaves-only)
            LEAVES_ONLY=true
            shift
            ;;
        --history)
            HISTORY_FILE="$2"
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
if [[ ! -f "$HISTORY_FILE" ]]; then
    echo "Error: history file not found: $HISTORY_FILE" >&2
    exit 1
fi

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ── Step 1: build pkg→binaries map from symlinks (no brew subprocess) ─────────
echo "==> Scanning /opt/homebrew/{bin,sbin} symlinks…" >&2

BIN_PKG_FILE="${TMPDIR_WORK}/bin_pkg.txt" # "binary<TAB>package"

# Single ls pass — avoids spawning readlink per file (300× faster)
ls -la /opt/homebrew/bin/ /opt/homebrew/sbin/ 2> /dev/null \
    | awk '/ -> / {
        n = split($0, parts, " -> ")
        target = parts[2]; sub(/[[:space:]].*$/, "", target)
        if (target ~ /\/Cellar\//) {
            pkg = target
            sub(/.*\/Cellar\//, "", pkg); sub(/\/.*/, "", pkg)
            bin = parts[1]
            sub(/ -> .*/, "", bin); sub(/.*[[:space:]]/, "", bin)
            print bin "\t" pkg
        }
    }' > "$BIN_PKG_FILE"

BINARY_COUNT=$(wc -l < "$BIN_PKG_FILE" | tr -d ' ')
echo "==> Found ${BINARY_COUNT} binaries across all packages" >&2

# ── Step 2: filter packages ────────────────────────────────────────────────────
echo "==> Collecting package list…" >&2

if [[ "$LEAVES_ONLY" == true ]]; then
    WANTED=$(brew leaves)
else
    WANTED=$(brew list --formula --installed-on-request 2> /dev/null || brew leaves)
fi

# Keep only bin_pkg entries whose package is in WANTED
WANTED_FILE="${TMPDIR_WORK}/wanted.txt"
echo "$WANTED" > "$WANTED_FILE"

FILTERED_BIN_PKG="${TMPDIR_WORK}/filtered_bin_pkg.txt"
awk 'NR==FNR { wanted[$1]=1; next } $2 in wanted { print }' \
    "$WANTED_FILE" "$BIN_PKG_FILE" > "$FILTERED_BIN_PKG"

PKG_COUNT=$(awk '{print $2}' "$FILTERED_BIN_PKG" | sort -u | wc -l | tr -d ' ')
echo "==> Auditing ${PKG_COUNT} packages with CLI binaries…" >&2

# ── Step 3: build word frequency table from history (single pass) ──────────────
echo "==> Building word frequency from shell history…" >&2

HISTORY_TMP="${TMPDIR_WORK}/history.txt"

if [[ -n "$DAYS" ]]; then
    CUTOFF=$(date -v "-${DAYS}d" +%s 2> /dev/null || date -d "-${DAYS} days" +%s)
    strings "$HISTORY_FILE" | awk -v cutoff="$CUTOFF" '
        /^: [0-9]+:[0-9]*;/ {
            split($0, a, ";")
            ts = substr(a[1], 3)
            sub(/:.*/, "", ts)
            if (ts + 0 >= cutoff) { sub(/^[^;]*;/, ""); print }
            next
        }
        { print }
    ' > "$HISTORY_TMP"
else
    strings "$HISTORY_FILE" | sed 's/^: [0-9]*:[0-9]*;//' > "$HISTORY_TMP"
fi

HISTORY_LINES=$(wc -l < "$HISTORY_TMP" | tr -d ' ')
echo "==> ${HISTORY_LINES} history entries" >&2

# Single awk pass: tokenize every line, count word frequencies
# Tokens: split on anything that's not [alnum . _ - @]
FREQ_FILE="${TMPDIR_WORK}/freq.txt"
awk '
{
    n = split($0, words, /[^[:alnum:]._@-]+/)
    for (i = 1; i <= n; i++) {
        w = words[i]
        if (length(w) >= 2) freq[w]++
    }
}
END {
    for (w in freq) print freq[w], w
}
' "$HISTORY_TMP" > "$FREQ_FILE"

WORD_COUNT=$(wc -l < "$FREQ_FILE" | tr -d ' ')
echo "==> Frequency table: ${WORD_COUNT} distinct tokens" >&2

# ── Step 4: aggregate hits per package ────────────────────────────────────────
echo "==> Aggregating…" >&2

RESULTS_FILE="${TMPDIR_WORK}/results.txt"

# Join: for each (binary, package) pair, look up binary count in freq table
# freq.txt format:  "COUNT WORD"
# filtered_bin_pkg: "BINARY\tPACKAGE"
awk '
NR==FNR {
    # Load freq table: freq["curl"] = 42
    freq[$2] = $1 + 0
    next
}
{
    # bin_pkg line: binary<TAB>package
    bin = $1
    pkg = $2
    hits = (bin in freq) ? freq[bin] : 0
    pkg_hits[pkg] += hits
}
END {
    for (p in pkg_hits) print pkg_hits[p], p
}
' "$FREQ_FILE" "$FILTERED_BIN_PKG" | sort -k1,1n -k2,2 > "$RESULTS_FILE"

# ── Report ─────────────────────────────────────────────────────────────────────
echo ""
printf '══════════════════════════════════════════════════════════\n'
printf ' Homebrew Usage Audit   threshold: < %d hits\n' "$THRESHOLD"
printf '══════════════════════════════════════════════════════════\n'
printf '  %-40s  %s\n' "PACKAGE" "HITS"
printf '  %-40s  %s\n' "-------" "----"

while read -r hits pkg; do
    if [[ "$hits" -lt "$THRESHOLD" ]]; then
        printf '  %-40s  %d\n' "$pkg" "$hits"
    fi
done < "$RESULTS_FILE"

echo ""
printf '══════════════════════════════════════════════════════════\n'
printf ' All packages (sorted by usage ascending)\n'
printf '══════════════════════════════════════════════════════════\n'

while read -r hits pkg; do
    printf '  %6d hits  %s\n' "$hits" "$pkg"
done < "$RESULTS_FILE"

echo ""
echo "==> To check dependents before removing:  brew uses --installed <package>"
echo "==> To remove:                            brew uninstall <package>"
