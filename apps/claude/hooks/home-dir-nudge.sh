#!/usr/bin/env bash
# home-dir-nudge.sh: Claude SessionStart hook (startup only)
# A session started from $HOME loads no project CLAUDE.md and no project memory.
# Points to the ops workspace named on the first line of ~/.config/claude/ops-dir.
set -uo pipefail

input=$(cat) || exit 0
cwd=$(jq -r '.cwd // empty' <<< "$input" 2> /dev/null) || exit 0
[[ "$cwd" == "$HOME" ]] || exit 0

msg="Started from ~: no project CLAUDE.md is loaded."
target=$(head -n 1 "$HOME/.config/claude/ops-dir" 2> /dev/null)
target="${target/#\~/$HOME}"
if [[ -n "$target" && -d "$target" ]]; then
    msg="$msg For Jira, MR, Grafana or cluster chores, relaunch from the ops workspace: cd ${target/#$HOME/\~} && claude"
fi
jq -nc --arg m "$msg" '{systemMessage: $m}'
exit 0
