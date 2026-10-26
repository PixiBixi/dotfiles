#!/usr/bin/env bash
# Event: UserPromptSubmit.
# Renames the session to the first Jira key the user types (PE-2117), once: the CLAUDE.md rule
# "rename the session to the key" was text-only and kept being skipped. A session that already
# has a title (from /rename or from this hook) is never renamed again.
set -uo pipefail

input=$(cat) || exit 0
# Projects actually used; a generic [A-Z]+-[0-9]+ also matches UTF-8, SHA-256, ISO-8601.
KEY_RE='(^|[^A-Za-z0-9_])((PE|VAI|CVAI|CMB|SEC|CDYN|DBOPS|CB|INC|PIMP)-[0-9]{2,6})([^A-Za-z0-9_]|$)'
# Bash-only fast path: most prompts carry no key, so no process is spawned for them. No
# boundary here: the raw JSON escapes a newline as \n, which would hide a key opening a line.
[[ "$input" =~ (PE|VAI|CVAI|CMB|SEC|CDYN|DBOPS|CB|INC|PIMP)-[0-9]{2} ]] || exit 0
command -v jq > /dev/null 2>&1 || exit 0

IFS=$'\x1f' read -r session_id transcript < <(jq -r '[.session_id // "", .transcript_path // ""] | join("\u001f")' <<< "$input")
prompt=$(jq -r '.prompt // ""' <<< "$input")
[ -n "$prompt" ] && [ -n "$session_id" ] && [ -f "$transcript" ] || exit 0

[[ "$prompt" =~ $KEY_RE ]] || exit 0
key=${BASH_REMATCH[2]}

rg -q '"type":"custom-title"' "$transcript" && exit 0

CLAUDE_CODE_SESSION_ID="$session_id" "$HOME/Documents/perso/git/dotfiles/apps/claude/bin/claude-rename.sh" "$key" > /dev/null 2>&1 || exit 0
jq -n --arg k "$key" '{systemMessage: ("Session renamed to " + $k)}'
