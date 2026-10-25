#!/usr/bin/env bash
# Event: UserPromptSubmit.
# Renames the session to the first Jira key the user types (PE-2117), once: the CLAUDE.md rule
# "rename the session to the key" was text-only and kept being skipped. A session that already
# has a title (from /rename or from this hook) is never renamed again.
set -uo pipefail

command -v jq > /dev/null 2>&1 || exit 0

input=$(cat)
prompt=$(jq -r '.prompt // ""' <<< "$input")
session_id=$(jq -r '.session_id // ""' <<< "$input")
transcript=$(jq -r '.transcript_path // ""' <<< "$input")
[ -n "$prompt" ] && [ -n "$session_id" ] && [ -f "$transcript" ] || exit 0

# Projects actually used; a generic [A-Z]+-[0-9]+ also matches UTF-8, SHA-256, ISO-8601.
key=$(printf '%s' "$prompt" | rg -o -m1 '\b(PE|VAI|CVAI|CMB|SEC|CDYN|DBOPS|CB|INC|PIMP)-[0-9]{2,6}\b' | head -1)
[ -n "$key" ] || exit 0

rg -q '"type":"custom-title"' "$transcript" && exit 0

CLAUDE_CODE_SESSION_ID="$session_id" "$HOME/Documents/perso/git/dotfiles/apps/claude/bin/claude-rename.sh" "$key" > /dev/null 2>&1 || exit 0
jq -n --arg k "$key" '{systemMessage: ("Session renamed to " + $k)}'
