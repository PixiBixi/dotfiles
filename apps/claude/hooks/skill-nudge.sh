#!/usr/bin/env bash
# Event: UserPromptSubmit.
# A skill whose trigger is a pasted URL gets skipped when the prompt carries other words
# (gitlab-job-triage: 4 loads for 14 sessions with a job URL). Matching the URL here and
# naming the skill makes the load deterministic. One "<regex>\t<skill>" per line in RULES.
set -uo pipefail

command -v jq > /dev/null 2>&1 || exit 0

prompt=$(jq -r '.prompt // ""' 2> /dev/null) || exit 0
[ -n "$prompt" ] || exit 0

RULES=$(printf '%s\t%s\n' \
    'gitlab\.com/[^ ]+/-/(jobs|pipelines)/[0-9]+' 'gitlab-job-triage')

skills=()
while IFS=$'\t' read -r re skill; do
    [ -n "$re" ] || continue
    if printf '%s' "$prompt" | rg -q -e "$re"; then
        skills+=("$skill")
    fi
done <<< "$RULES"

[ ${#skills[@]} -gt 0 ] || exit 0

jq -n --arg s "${skills[*]}" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit",
    additionalContext: ("The prompt matches the trigger of skill(s): " + $s + ". Load them with the Skill tool before any other tool call, unless one is already loaded in this session.")}}'
