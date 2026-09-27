#!/usr/bin/env bash
# Manage the reminders Claude writes for the user, in the dedicated "Claude" list of Apple Reminders.
set -euo pipefail

readonly LIST_NAME="Claude"

usage() {
    cat << 'EOF'
Usage:
  claude-reminders.sh add "<title>" "<YYYY-MM-DD HH:MM>" ["<note>"]
  claude-reminders.sh check     # open reminders due up to the end of today, oldest first
  claude-reminders.sh list      # every open reminder of the list
  claude-reminders.sh done "<id>"
EOF
    exit 2
}

[[ $# -ge 1 ]] || usage
cmd="$1"
shift

case "${cmd}" in
    add)
        [[ $# -ge 2 ]] || usage
        title="$1"
        due="$2"
        note="${3:-}"
        # Resume footer, so the reminder can reopen the session that created it.
        if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
            footer="Session Claude : ${CLAUDE_CODE_SESSION_ID}"$'\n'"Reprendre : ~/.claude/skills/reminders/scripts/claude-resume.sh ${CLAUDE_CODE_SESSION_ID} '${PWD}'"
            note="${note:+${note}$'\n\n'}${footer}"
        fi
        if ! [[ "${due}" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2}):([0-9]{2})$ ]]; then
            echo "error: due date must be 'YYYY-MM-DD HH:MM', got '${due}'" >&2
            exit 2
        fi
        osascript - "${LIST_NAME}" "${title}" "${note}" \
            "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" << 'EOF'
on run argv
  set {listName, t, n, y, mo, d, h, mi} to argv
  set dueDate to current date
  set day of dueDate to 1
  set year of dueDate to (y as integer)
  set month of dueDate to (mo as integer)
  set day of dueDate to (d as integer)
  set hours of dueDate to (h as integer)
  set minutes of dueDate to (mi as integer)
  set seconds of dueDate to 0
  tell application "Reminders"
    if not (exists list listName) then make new list with properties {name:listName}
    set r to make new reminder at end of list listName with properties {name:t, body:n, remind me date:dueDate}
    return (id of r) & tab & (name of r) & tab & ((remind me date of r) as string)
  end tell
end run
EOF
        ;;
    check | list)
        osascript - "${LIST_NAME}" "${cmd}" << 'EOF'
on run argv
  set {listName, mode} to argv
  set cutoff to current date
  set hours of cutoff to 23
  set minutes of cutoff to 59
  set seconds of cutoff to 59
  tell application "Reminders"
    if not (exists list listName) then return "no list '" & listName & "'"
    set rs to (reminders of list listName whose completed is false)
    set out to ""
    repeat with r in rs
      set dd to remind me date of r
      -- A whose clause on the date fails on undated reminders (-1700): filter here instead.
      set isDue to (dd is not missing value)
      if isDue then set isDue to (dd ≤ cutoff)
      if mode is "list" or isDue then
        if dd is missing value then
          set ds to "no date"
        else
          set ds to dd as string
        end if
        set b to body of r
        if b is missing value then set b to ""
        set out to out & (id of r) & tab & ds & tab & (name of r) & tab & b & linefeed
      end if
    end repeat
    if out is "" then return "nothing due"
    return out
  end tell
end run
EOF
        ;;
    done)
        [[ $# -eq 1 ]] || usage
        osascript - "$1" << 'EOF'
on run argv
  tell application "Reminders"
    set r to reminder id (item 1 of argv)
    set completed of r to true
    return "done: " & (name of r)
  end tell
end run
EOF
        ;;
    *)
        usage
        ;;
esac
