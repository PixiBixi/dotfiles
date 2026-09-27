#!/usr/bin/env bash
# Bring a Claude Code session back to the front in WezTerm: focus its pane if it is still running,
# otherwise open a new tab in its folder with `claude --resume`.
set -euo pipefail

usage() {
    echo "Usage: claude-resume.sh <session-id> [<folder>]" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
session_id="$1"
folder="${2:-}"
[[ "${session_id}" =~ ^[0-9a-f-]{36}$ ]] || usage

for bin in jq wezterm; do
    command -v "${bin}" > /dev/null || {
        echo "error: ${bin} not found" >&2
        exit 1
    }
done

# Claude Code writes one ~/.claude/sessions/<pid>.json per live session; the file can outlive the process.
live_pid=""
for f in "${HOME}"/.claude/sessions/*.json; do
    [[ -e "${f}" ]] || continue
    if [[ "$(jq -r '.sessionId // empty' "${f}")" == "${session_id}" ]]; then
        pid="$(jq -r '.pid' "${f}")"
        if kill -0 "${pid}" 2> /dev/null; then
            live_pid="${pid}"
            [[ -n "${folder}" ]] || folder="$(jq -r '.cwd' "${f}")"
            break
        fi
    fi
done

# A session launched from inside another Claude session has no registry file: match its command line too.
if [[ -z "${live_pid}" ]]; then
    live_pid="$(ps -axo pid=,command= | awk -v id="${session_id}" '$2 == "claude" && $0 ~ ("--resume " id) {print $1; exit}')"
fi

wezterm_running() { wezterm cli list > /dev/null 2>&1; }

if [[ -n "${live_pid}" ]] && wezterm_running; then
    tty="/dev/$(ps -o tty= -p "${live_pid}" | tr -d ' ')"
    pane_id="$(wezterm cli list --format json | jq -r --arg tty "${tty}" '.[] | select(.tty_name == $tty) | .pane_id' | head -1)"
    if [[ -n "${pane_id}" ]]; then
        wezterm cli activate-pane --pane-id "${pane_id}"
        open -a WezTerm
        echo "focused running session ${session_id} (pid ${live_pid}, pane ${pane_id})"
        exit 0
    fi
    echo "error: session ${session_id} runs as pid ${live_pid} but not in a WezTerm pane" >&2
    exit 1
fi

if [[ -z "${folder}" ]]; then
    echo "error: session ${session_id} is not running, pass its folder as second argument" >&2
    exit 2
fi
[[ -d "${folder}" ]] || {
    echo "error: folder ${folder} does not exist" >&2
    exit 1
}

# Scrub the calling session's markers: an inherited CLAUDE_CODE_CHILD_SESSION turns transcript saving off.
# Login + interactive shell, so PATH and the user's env match a normal tab.
resume_cmd=(env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_SESSION_ATTENDED
    -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_EXECPATH -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN
    -u CLAUDE_PID -u CLAUDE_EFFORT zsh -lic "claude --resume ${session_id}")
if wezterm_running; then
    pane_id="$(wezterm cli spawn --cwd "${folder}" -- "${resume_cmd[@]}")"
    wezterm cli activate-pane --pane-id "${pane_id}"
    open -a WezTerm
    echo "resumed ${session_id} in new tab (pane ${pane_id})"
else
    nohup wezterm start --cwd "${folder}" -- "${resume_cmd[@]}" > /dev/null 2>&1 &
    echo "resumed ${session_id} in a new WezTerm window"
fi
