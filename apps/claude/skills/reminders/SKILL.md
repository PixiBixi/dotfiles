---
name: reminders
description: Use when the user asks for a reminder ("mets-moi un reminder", "rappelle-moi demain", "remind me at 9:30"), or asks to check, review or close past reminders ("check les reminders de la veille", "qu'est-ce que j'avais à faire", "c'est fait, coche-le"). Also right after opening an MR, or after merging or rolling out a change expected to move performance or cost. Reminders live in Tickler (`tickler` CLI, Tickler.app in the menu bar), which notifies on time and copies them into the calendar.
---

# Reminders

Every reminder Claude creates goes through the `tickler` CLI (`~/.local/bin/tickler`, source in `~/Documents/perso/git/tickler`). Tickler.app shows them in the menu bar, notifies at the due time with a Resume button that reopens the creating session, and copies them into the user's calendar. Use `--json` whenever the output is read back.

| Command | Does |
|---|---|
| `tickler add "<title>" --at "YYYY-MM-DD HH:MM" [--notes -] [--link <url>]...` | Creates the reminder, prints `id<TAB>title<TAB>date` |
| `tickler list --due today --json` | Open reminders due up to the end of today, overdue included |
| `tickler list --due all --json` | Every open reminder |
| `tickler show <id> --json` | One reminder with notes, links, session and folder |
| `tickler done <id>` | Marks it done |
| `tickler edit <id> --at "YYYY-MM-DD HH:MM"` | Reschedules it (also `--title`, `--notes`) |
| `tickler snooze <id> --for 1h` | Pushes it back from now (`15m`, `1h`, `2d`) |
| `tickler rm <id>` | Deletes an obsolete reminder |
| `tickler resume <id>` | Reopens the reminder's Claude session in WezTerm, Ghostty or iTerm2 |
| `tickler status <id> --json` | Live state of the linked MRs, Jira issues and PRs: pipeline, approvals, ticket status |

`add` records the creating session and folder from `CLAUDE_CODE_SESSION_ID` and the cwd. Pass `--session <uuid> --cwd <dir>` to point at another session. Links in the notes are detected (MR, Jira, Slack, Grafana, PR) and become buttons in the app and in the notification, so put the full URLs in the notes.

## Creating

- Resolve relative dates ("demain 9h30") against today's date from the context, in local time. `--at` only takes `YYYY-MM-DD HH:MM`.
- Title: the action, self-contained, readable on a lock screen. Never a relative offset ("J+7", "dans 3 jours", "demain"): it loses its anchor once read later. Write the absolute date of the reference point instead ("7 jours après le fix du 28/09"). Notes: the exact command, file path or trigger phrase needed to resume ("puis dire 'compare ws-ports' à Claude"), since the next session has no memory of this one. Pass multi-line notes on stdin with `--notes -`.
- Spacing: run `tickler list --due all --json` first and keep at least 30 min between two reminders. If the slot is taken, shift the new one to the next free slot and say so in the confirmation.
- Confirm in one line: title and date.
- Rescheduling: `tickler edit <id> --at ...`, never add plus delete (the app counts reschedules). Dropping one: `tickler rm <id>`. Never `done` for either: a completed reminder reads as work actually done.

## Follow-ups to propose unasked

Offer these in one line at the moment they arise, create on a yes:

| Moment | Reminder | Note carries |
|---|---|---|
| An MR was just opened | Two working days later, 10:00: chase the review if still unreviewed | MR URL, reviewer, ticket key |
| A change expected to move CPU, memory, latency or cost was merged or rolled out | 24h after the end of the rollout (7 days for cost): re-measure against the baseline | The metric or dashboard, the baseline value and when it was taken, where to post the result |

At check time, look at the live state first (`tickler status <id> --json` for linked MRs and tickets, the metric for re-measures) so the report says whether the action is still needed.

## Importing tasks from the calendar

Events the user created alone (no other attendee) that describe an action are tasks: propose them as reminders, copying links and steps into the note, plus any follow-up the description implies (a re-measure 24h later). The reminder must point at the session that planned the task, not the importing one: find it with `/usr/bin/grep -rlF --include='*.jsonl' '<event title>' ~/.claude/projects` (excluding the current session), take its `cwd` from the transcript, and pass both as `--session <id> --cwd <dir>` to `add`. No match: keep the current session. Once created, delete the source event from Google Calendar with `notificationLevel: NONE`, since Tickler already copies the reminder into the calendar. Meetings stay in the calendar.

## Checking ("check les reminders de la veille")

1. Run `tickler list --due today --json`. It returns every open reminder due today or earlier, not only yesterday's: an unfinished one from three days ago still matters.
2. For each one: title, due date, and what it asks, then do it or propose to do it when it is something Claude can run (a comparison, a command). Actions needing `sudo` go back to the user as a paste-ready block.
3. Mark a reminder `done` only once its action is actually complete, never just because it was read.
