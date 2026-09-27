#!/usr/bin/env bash
# Rename the current Claude Code session, as /rename does, from inside the session.
# Appends the custom-title entry /rename writes to the transcript (undocumented format:
# picker and --resume pick it up), and sets the WezTerm tab title so it shows right away.
set -euo pipefail

[[ $# -eq 1 && -n "$1" ]] || {
    echo "Usage: claude-rename.sh <title>" >&2
    exit 2
}
title="$1"
session_id="${CLAUDE_CODE_SESSION_ID:-}"
[[ -n "${session_id}" ]] || {
    echo "error: CLAUDE_CODE_SESSION_ID unset, run from inside a Claude Code session" >&2
    exit 1
}

shopt -s nullglob
transcripts=("${HOME}"/.claude/projects/*/"${session_id}".jsonl)
[[ ${#transcripts[@]} -eq 1 ]] || {
    echo "error: expected one transcript for ${session_id}, found ${#transcripts[@]}" >&2
    exit 1
}

# One short line in a single append: O_APPEND keeps it whole next to the live writer.
jq -cn --arg t "${title}" --arg s "${session_id}" \
    '{type: "custom-title", customTitle: $t, sessionId: $s}' >> "${transcripts[0]}"

# The tab title is best effort: absent outside WezTerm.
if [[ -n "${WEZTERM_PANE:-}" ]] && command -v wezterm > /dev/null; then
    wezterm cli set-tab-title --pane-id "${WEZTERM_PANE}" "${title}" || true
fi
echo "renamed ${session_id} to '${title}'"
