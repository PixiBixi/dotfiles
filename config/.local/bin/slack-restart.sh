#!/usr/bin/env bash
# Nightly Slack restart: the Electron renderer never returns its heap to the OS.
# Cmd+R reloads the webview but reuses the process, so only a fresh process reclaims it.
set -euo pipefail

readonly IDLE_THRESHOLD=600
readonly QUIT_TIMEOUT=30
readonly LOG="${HOME}/Library/Logs/slack-restart.log"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "${LOG}"; }

mkdir -p "$(dirname "${LOG}")"

pgrep -x Slack > /dev/null 2>&1 || {
    log "skip: Slack not running"
    exit 0
}

# Never kill Slack while someone is at the keyboard: a restart mid on-call page is worse
# than the RAM it frees. Skipped runs just wait for the next night.
idle=$(ioreg -c IOHIDSystem 2> /dev/null | awk '/HIDIdleTime/ {print int($NF / 1000000000); exit}')
if [[ -n "${idle:-}" ]] && ((idle < IDLE_THRESHOLD)); then
    log "skip: user active (idle ${idle}s < ${IDLE_THRESHOLD}s)"
    exit 0
fi

rss_before=$(ps -Ao rss,comm | awk '/Slack/ {s += $1} END {printf "%.0f", s / 1024}')

# AppleScript quit rather than SIGTERM: it lets Slack flush its drafts.
osascript -e 'tell application "Slack" to quit' > /dev/null 2>&1 || true
for ((i = 0; i < QUIT_TIMEOUT; i++)); do
    pgrep -x Slack > /dev/null 2>&1 || break
    sleep 1
done
if pgrep -x Slack > /dev/null 2>&1; then
    log "warn: graceful quit timed out after ${QUIT_TIMEOUT}s, forcing"
    pkill -x Slack || true
    sleep 3
fi

open -g -j -a Slack
log "restarted (was ${rss_before}MB)"
