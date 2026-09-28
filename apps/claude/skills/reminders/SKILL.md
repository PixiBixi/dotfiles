---
name: reminders
description: Use when the user asks for a reminder ("mets-moi un reminder", "rappelle-moi demain", "remind me at 9:30"), or asks to check, review or close past reminders ("check les reminders de la veille", "qu'est-ce que j'avais à faire", "c'est fait, coche-le"). Also right after opening an MR, or after merging or rolling out a change expected to move performance or cost. Reminders live in the "Claude" list of Apple Reminders, synced to the phone through iCloud.
---

# Reminders

Every reminder Claude creates goes in the **"Claude"** list of Apple Reminders, never the default list, so the daily check only sees what Claude wrote. Script: `scripts/claude-reminders.sh` (next to this file).

| Command | Does |
|---|---|
| `add "<title>" "<YYYY-MM-DD HH:MM>" ["<note>"]` | Creates the reminder with a notification at that time, prints `id<TAB>title<TAB>date` |
| `check` | Open reminders due up to the end of today (overdue included) |
| `list` | Every open reminder of the list |
| `done "<id>"` | Marks it completed |

`add` appends the creating session to the note (from `CLAUDE_CODE_SESSION_ID` and the cwd). `scripts/claude-resume.sh <session-id> [<folder>]` reopens it in WezTerm: focuses the pane if the session still runs, otherwise opens a new tab with `claude --resume`.

## Creating

- Resolve relative dates ("demain 9h30") against today's date from the context, in local time.
- Title: the action, self-contained, readable on a lock screen. Never a relative offset ("J+7", "dans 3 jours", "demain"): it loses its anchor once read later. Write the absolute date of the reference point instead ("7 jours après le fix du 28/09"). Note: the exact command, file path or trigger phrase needed to resume ("puis dire 'compare ws-ports' à Claude"), since the next session has no memory of this one.
- Confirm in one line: title and date.

## Follow-ups to propose unasked

Offer these in one line at the moment they arise, create on a yes:

| Moment | Reminder | Note carries |
|---|---|---|
| An MR was just opened | Two working days later, 10:00: chase the review if still unreviewed | MR URL, reviewer, ticket key |
| A change expected to move CPU, memory, latency or cost was merged or rolled out | 24h after the end of the rollout (7 days for cost): re-measure against the baseline | The metric or dashboard, the baseline value and when it was taken, where to post the result |

At check time, look at the live state first (`glab mr view`, the metric) so the report says whether the action is still needed.

## Importing tasks from the calendar

Events the user created alone (no other attendee) that describe an action are tasks: propose them as reminders, copying links and steps into the note, plus any follow-up the description implies (a re-measure 24h later). The footer must point at the session that planned the task, not the importing one: find it with `/usr/bin/grep -rlF --include='*.jsonl' '<event title>' ~/.claude/projects` (excluding the current session), take its `cwd` from the transcript, and pass both as `REMINDER_SESSION_ID=<id> REMINDER_CWD=<dir>` to `add`. No match: keep the current session. Once created, delete the source event from Google Calendar with `notificationLevel: NONE`, since both show up in the Calendar app. Meetings stay in the calendar.

## Checking ("check les reminders de la veille")

1. Run `check`. It returns every open reminder due today or earlier, not only yesterday's: an unfinished one from three days ago still matters.
2. For each one: title, due date, and what it asks, then do it or propose to do it when it is something Claude can run (a comparison, a command). Actions needing `sudo` go back to the user as a paste-ready block.
3. Mark a reminder `done` only once its action is actually complete, never just because it was read.
