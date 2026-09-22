#!/usr/bin/env bash
# Nightly Slack restart: the Electron renderer never returns its heap to the OS.
# Cmd+R reloads the webview but reuses the process, so only a fresh process reclaims it.
set -euo pipefail

# Overridable so the restart path can be exercised on demand, both guards would
# otherwise skip any run made while sitting at the machine.
IDLE_THRESHOLD="${IDLE_THRESHOLD:-600}"
MIN_UPTIME="${MIN_UPTIME:-21600}"
QUIT_TIMEOUT="${QUIT_TIMEOUT:-30}"
readonly IDLE_THRESHOLD MIN_UPTIME QUIT_TIMEOUT
readonly LOG="${HOME}/Library/Logs/slack-restart.log"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "${LOG}"; }

mkdir -p "$(dirname "${LOG}")"

# The || true matters: pgrep exits 1 when Slack is down and pipefail would kill
# the script here, before it ever logs why.
slack_pid="$(pgrep -x Slack | head -1 || true)"
if [[ -z "${slack_pid}" ]]; then
    log "skip: Slack not running"
    exit 0
fi

# Three daily slots means three chances to catch an away-from-keyboard window.
# This keeps it to one restart a day instead of three.
# BSD ps has no etimes, only etime as [[dd-]hh:]mm:ss, hence the awk.
uptime_s="$(ps -o etime= -p "${slack_pid}" 2> /dev/null | tr -d ' ' | awk -F'[-:]' '
    NF == 4 {print (($1 * 24 + $2) * 60 + $3) * 60 + $4}
    NF == 3 {print ($1 * 60 + $2) * 60 + $3}
    NF == 2 {print $1 * 60 + $2}')"
if [[ -n "${uptime_s:-}" ]] && ((uptime_s < MIN_UPTIME)); then
    log "skip: Slack started ${uptime_s}s ago (< ${MIN_UPTIME}s)"
    exit 0
fi

# Never kill Slack while someone is at the keyboard: a restart mid on-call page is worse
# than the RAM it frees. Skipped runs just wait for the next night.
# awk exits on the first match, which SIGPIPEs ioreg: pipefail would make that
# a 141 and set -e would kill the script right before the restart it exists for.
idle="$(ioreg -c IOHIDSystem 2> /dev/null | awk '/HIDIdleTime/ {print int($NF / 1000000000); exit}' || true)"
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
