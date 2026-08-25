#!/usr/bin/env bash
# Event: PostToolUse, matcher Write|Edit.
# Flags banned characters and banned words that just landed in a written file and tells
# Claude to fix them silently. The em dash and the inclusive-terms rules live in
# apps/claude/CLAUDE.md; a standing rule is diluted with no error raised, so this is the
# floor under it. Adapted from infra/claude-os (Diego Arias).
#
# Chat replies cannot be hooked. This covers the places written text persists: docs, wiki
# pages, commit message files, code comments, MR descriptions written to a file.
#
# Config, first readable file wins:
#   1. $CLAUDE_WORDLIST_CONFIG
#   2. ./.claude/wordlist-guard.json   (per repo, relative to the hook's cwd)
#   3. ~/.claude/wordlist-guard.json
#
# No config: bannedChars defaults to U+2014 / U+2013 and the word list is empty, so the
# hook is useful out of the box and silent about words. Dash codepoints are referenced by
# number everywhere so this file never contains one and never flags itself.
set -uo pipefail

command -v jq > /dev/null 2>&1 || exit 0
command -v python3 > /dev/null 2>&1 || exit 0

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // ""' 2> /dev/null) || exit 0
[ -n "$f" ] && [ -f "$f" ] || exit 0

cfg=""
for c in "${CLAUDE_WORDLIST_CONFIG:-}" "$PWD/.claude/wordlist-guard.json" "$HOME/.claude/wordlist-guard.json"; do
    if [ -n "$c" ] && [ -r "$c" ]; then
        cfg="$c"
        break
    fi
done

exec python3 - "$f" "$cfg" << 'PY'
import fnmatch, json, os, re, sys

path = sys.argv[1]
cfg_path = sys.argv[2] if len(sys.argv) > 2 else ""

DEFAULT_CHARS = ["U+%04X" % 0x2014, "U+%04X" % 0x2013]
cfg = {}
if cfg_path:
    try:
        with open(cfg_path, encoding="utf-8") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            cfg = loaded
    except (OSError, ValueError):
        cfg = {}


def as_list(key):
    v = cfg.get(key)
    return [x for x in v if isinstance(x, str)] if isinstance(v, list) else None


raw_chars = as_list("bannedChars")
if raw_chars is None:
    raw_chars = DEFAULT_CHARS
raw_words = as_list("bannedWords") or []
allow = as_list("allowPaths") or []

# Any allowPaths match means this file is out of scope.
norm = path.replace(os.sep, "/")
base = norm.rsplit("/", 1)[-1]
for pat in allow:
    if "/" in pat:
        if pat in norm or fnmatch.fnmatch(norm, pat):
            sys.exit(0)
    elif fnmatch.fnmatch(base, pat) or fnmatch.fnmatch(norm, pat):
        sys.exit(0)

chars = {}
for entry in raw_chars:
    if re.fullmatch(r"[Uu]\+[0-9A-Fa-f]{1,6}", entry):
        try:
            ch = chr(int(entry[2:], 16))
        except ValueError:
            continue
        chars[ch] = entry.upper()
    elif len(entry) == 1:
        chars[entry] = "U+%04X" % ord(entry)

words = []
for entry in raw_words:
    is_regex = entry.startswith("re:")
    pat = entry[3:] if is_regex else r"\b" + re.escape(entry) + r"s?\b"
    try:
        words.append((entry, re.compile(pat, re.IGNORECASE), is_regex))
    except re.error:
        continue

if not chars and not words:
    sys.exit(0)

try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
except OSError:
    sys.exit(0)

charset = set(chars)
char_hits = []
word_hits = {}
for i, line in enumerate(text.splitlines(), 1):
    if charset & set(line):
        char_hits.append(i)
    for entry, rx, is_regex in words:
        m = rx.search(line)
        if not m:
            continue
        # A regex entry reports the text it actually matched, not the pattern.
        label = m.group(0) if is_regex else entry
        word_hits.setdefault(label, []).append(i)

if not char_hits and not word_hits:
    sys.exit(0)


def shown(nums):
    return ",".join(str(n) for n in nums[:5])


name = norm.rsplit("/", 1)[-1]
summary, detail = [], []

if char_hits:
    present = sorted({chars[c] for c in charset if c in text})
    lines = shown(char_hits)
    summary.append("%d banned-character line(s) (%s)" % (len(char_hits), lines))
    detail.append(
        "contains banned character(s) %s on line(s) %s. Replace each one with a colon, "
        "a comma, parentheses, a plain hyphen, or a sentence break."
        % (", ".join(present), lines)
    )

for label, nums in word_hits.items():
    lines = shown(nums)
    summary.append('%d "%s" line(s) (%s)' % (len(nums), label, lines))
    detail.append(
        'uses the banned word "%s" on line(s) %s. Rewrite it with the inclusive or '
        "concrete term instead." % (label, lines)
    )

print(json.dumps({
    "systemMessage": "Wordlist guard: %s, %s" % (name, "; ".join(summary)),
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            "RULE VIOLATION: %s " % path
            + " Also, it ".join(detail)
            + " Fix it now, silently, no need to narrate the check."
        ),
    },
}))
PY
