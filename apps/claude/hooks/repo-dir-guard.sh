#!/usr/bin/env bash
# repo-dir-guard.sh: Claude UserPromptSubmit hook
# A prompt citing a gitlab.com/smartadserver/<path>/-/... URL (MR, blob, pipeline)
# maps to the clone $GITLAB_ROOT/<path>. Session inside another git repo: block once
# per session and repo, re-sending passes. Outside any repo (ops/): add context only.
set -uo pipefail

GITLAB_ROOT="${GITLAB_ROOT:-$HOME/Documents/work/git/smartadserver}"
STATE_DIR="${TMPDIR:-/tmp}/claude-repo-dir-guard"

input=$(cat) || exit 0
prompt=$(jq -r '.prompt // empty' <<< "$input" 2> /dev/null) || exit 0
cwd=$(jq -r '.cwd // empty' <<< "$input" 2> /dev/null) || exit 0
session=$(jq -r '.session_id // empty' <<< "$input" 2> /dev/null) || exit 0
[[ -n "$prompt" && -n "$cwd" ]] || exit 0

paths=$(/usr/bin/grep -oE 'https?://gitlab\.com/smartadserver/[^[:space:]/]+(/[^[:space:]/]+)*/-/' <<< "$prompt" 2> /dev/null \
    | sed -E 's#^https?://gitlab\.com/smartadserver/##; s#/-/$##' | sort -u)
[[ -n "$paths" ]] || exit 0
# Several repos in one prompt (batch merge, sibling MRs): no single right directory.
(($(wc -l <<< "$paths") == 1)) || exit 0

target="$GITLAB_ROOT/$paths"
cwd_real=$(cd "$cwd" 2> /dev/null && pwd -P) || exit 0

if [[ ! -d "$target" ]]; then
    ctx="The prompt cites gitlab.com/smartadserver/$paths, which has no local clone. If the task changes code there, clone it first: git clone git@gitlab.com:smartadserver/$paths.git $target"
    jq -nc --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
    exit 0
fi

target_real=$(cd "$target" && pwd -P)
[[ "$cwd_real" == "$target_real" || "$cwd_real" == "$target_real"/* ]] && exit 0

if top=$(git -C "$cwd_real" rev-parse --show-toplevel 2> /dev/null); then
    mkdir -p "$STATE_DIR" 2> /dev/null || exit 0
    marker="$STATE_DIR/${session:-nosession}-$(printf '%s' "$paths" | shasum | cut -c1-12)"
    [[ -f "$marker" ]] && exit 0
    : > "$marker"
    reason="This prompt targets smartadserver/$paths, but the session runs in $top. Relaunch from the right clone: cd $target && claude. Re-send the prompt (up arrow) to go on here anyway."
    jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
    exit 0
fi

ctx="The prompt targets smartadserver/$paths, cloned at $target, but the session runs in $cwd_real (not that clone). Reading, merging or reviewing from here is fine. If the task turns into a code change in that repo, stop and tell the user to relaunch from $target so its CLAUDE.md and project memory load."
jq -nc --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
exit 0
