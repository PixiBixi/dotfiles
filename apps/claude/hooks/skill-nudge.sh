#!/usr/bin/env bash
# Event: UserPromptSubmit.
# A skill whose trigger is a pasted URL gets skipped when the prompt carries other words
# (gitlab-job-triage: 4 loads for 14 sessions with a job URL). Matching the URL here and
# naming the skill makes the load deterministic. One "<regex>\t<skill>" per line in RULES.
set -uo pipefail

input=$(cat) || exit 0
# Bash-only fast path: no rule host in the payload means nothing to do, no process spawned.
[[ "$input" == *gitlab.com* || "$input" == *slack.com* ]] || exit 0
command -v jq > /dev/null 2>&1 || exit 0

prompt=$(jq -r '.prompt // ""' <<< "$input" 2> /dev/null) || exit 0
[ -n "$prompt" ] || exit 0

skills=()
[[ "$prompt" =~ gitlab\.com/[^[:space:]]+/-/(jobs|pipelines)/[0-9]+ ]] && skills+=(gitlab-job-triage)
[[ "$prompt" =~ slack\.com/archives/[A-Z0-9]+/p[0-9]+ ]] && skills+=(slack-thread-triage)

[ ${#skills[@]} -gt 0 ] || exit 0

jq -n --arg s "${skills[*]}" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit",
    additionalContext: ("The prompt matches the trigger of skill(s): " + $s + ". Load them with the Skill tool before any other tool call, unless one is already loaded in this session.")}}'
