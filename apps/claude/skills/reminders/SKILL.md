---
name: reminders
description: Use when the user asks for a reminder ("mets-moi un reminder", "rappelle-moi demain", "remind me at 9:30"), or asks to check, review or close past reminders ("check les reminders de la veille", "qu'est-ce que j'avais à faire", "c'est fait, coche-le"). Reminders live in the "Claude" list of Apple Reminders, synced to the phone through iCloud.
---

# Reminders

Every reminder Claude creates goes in the **"Claude"** list of Apple Reminders, never the default list, so the daily check only sees what Claude wrote. Script: `scripts/claude-reminders.sh` (next to this file).

| Command | Does |
|---|---|
| `add "<title>" "<YYYY-MM-DD HH:MM>" ["<note>"]` | Creates the reminder with a notification at that time, prints `id<TAB>title<TAB>date` |
| `check` | Open reminders due up to the end of today (overdue included) |
| `list` | Every open reminder of the list |
| `done "<id>"` | Marks it completed |

`add` appends the creating session to the note (from `CLAUDE_CODE_SESSION_ID` and the cwd). `scripts/claude-resume.sh <session-id> [<folder>]` reopens it in WezTerm: focuses the pane if the session still runs, otherwise opens a new tab with `claude --resume`. When a checked reminder needs its original context, offer to run it.

## Creating

- Resolve relative dates ("demain 9h30") against today's date from the context, in local time.
- Title: the action, self-contained, readable on a lock screen. Note: the exact command, file path or trigger phrase needed to resume ("puis dire 'compare ws-ports' à Claude"), since the next session has no memory of this one.
- Confirm in one line: title and date.

## Importing tasks from the calendar

Events the user created alone (no other attendee) that describe an action are tasks: propose them as reminders, copying links and steps into the note, plus any follow-up the description implies (a re-measure 24h later). Once created, delete the source event from Google Calendar with `notificationLevel: NONE`, since both show up in the Calendar app. Meetings stay in the calendar.

## Checking ("check les reminders de la veille")

1. Run `check`. It returns every open reminder due today or earlier, not only yesterday's: an unfinished one from three days ago still matters.
2. For each one: title, due date, and what it asks, then do it or propose to do it when it is something Claude can run (a comparison, a command). Actions needing `sudo` go back to the user as a paste-ready block.
3. Mark a reminder `done` only once its action is actually complete, never just because it was read.
