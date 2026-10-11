#!/usr/bin/env bash
# cold-resume-guard.sh: Claude UserPromptSubmit hook
# Blocks the first prompt sent to a large session idle for over an hour: the
# 1h prompt cache has expired, so that prompt re-writes the whole context at
# the 2x cache-write price. Blocks once per idle period; re-sending passes.
set -uo pipefail

IDLE_MIN_SECONDS=${COLD_RESUME_IDLE_SECONDS:-3600}
CTX_MIN_TOKENS=${COLD_RESUME_CTX_TOKENS:-150000}
STATE_DIR="${TMPDIR:-/tmp}/claude-cold-resume"

input=$(cat) || exit 0
transcript=$(jq -r '.transcript_path // empty' <<< "$input" 2> /dev/null) || exit 0
session=$(jq -r '.session_id // empty' <<< "$input" 2> /dev/null) || exit 0
[[ -n "$transcript" && -n "$session" && -f "$transcript" ]] || exit 0

# Last main-conversation API call: its start time and the context it sent.
last=$(tail -n 400 "$transcript" | jq -Rrc '
    fromjson? | select(.type == "assistant" and .message.usage != null and (.isSidechain | not))
    | [.timestamp, (.message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)), .message.model]
    | @tsv' 2> /dev/null | tail -n 1)
[[ -n "$last" ]] || exit 0
IFS=$'\t' read -r ts ctx model <<< "$last"
[[ "$ctx" =~ ^[0-9]+$ ]] || exit 0
((ctx >= CTX_MIN_TOKENS)) || exit 0

last_epoch=$(TZ=UTC /bin/date -j -f '%Y-%m-%dT%H:%M:%S' "${ts%%.*}" +%s 2> /dev/null) || exit 0
idle=$(($(/bin/date +%s) - last_epoch))
((idle >= IDLE_MIN_SECONDS)) || exit 0

# One warning per idle period: the marker holds the timestamp already warned about.
mkdir -p "$STATE_DIR" 2> /dev/null || exit 0
marker="$STATE_DIR/$session"
[[ -f "$marker" && "$(cat "$marker")" == "$ts" ]] && exit 0
printf '%s' "$ts" > "$marker"

# 1h cache write = 2x input price ($/MTok): Opus 5.5 $4, Sonnet $2, older Opus $5.
case "$model" in
    claude-opus-5-5*) price=4 ;;
    claude-sonnet-*) price=2 ;;
    claude-haiku-*) price=1 ;;
    *) price=5 ;;
esac
cost=$(awk -v t="$ctx" -v p="$price" 'BEGIN { printf "%.2f", t * p * 2 / 1e6 }')
hours=$(awk -v s="$idle" 'BEGIN { printf "%.1f", s / 3600 }')
kctx=$((ctx / 1000))

reason="Session idle for ${hours}h with ${kctx}k tokens of context: the prompt cache has expired, so this prompt re-writes the whole context (about \$${cost}). Re-send it (up arrow) to go on anyway, or /clear (new topic) or /compact first."
jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
