---
name: ticket-conventions
description: Conventions and API gotchas for writing to a tracker - creating a Jira issue or a GitLab issue, posting a comment on an existing ticket. Load BEFORE any tracker write, and on "crée un ticket", "ouvre une issue", "commente le ticket", "poste ça sur PE-xxxx", "le ticket est prêt / à tester". Covers the approval gate, the Jira markdown trap, custom field id discovery, and the glab flags that hang. Not for jira-cli command syntax (that is jira-cli) and not for MR descriptions.
---

# Ticket conventions

Command syntax lives in `jira-cli`. This file is the layer above it: what a write must look like,
and the four ways a tracker write fails silently.

## The approval gate

**Never create or comment before an explicit yes in the current turn.** Show the target and the
full body together in one message, then stop:

```text
Ticket:  PE-1234  (https://<instance>/browse/PE-1234)
Comment:
<the exact text, in full>
```

The user is confirming the wording **and the target**, not the intent, so the gate applies even
when they asked for the ticket in the first place. Showing the id next to the body is what catches
a comment aimed at the wrong ticket, which is visible to the whole team the moment it lands.

Show the full body, never a three-line excerpt: an excerpt hides exactly the mistakes the gate
exists to catch. If the user edits the wording, show the revised draft and wait again. One approval
covers one write.

After posting, output the direct link so it can be verified:
`<baseUrl>/browse/<TICKET-ID>?focusedCommentId=<commentId>`.

## Jira: markdown, never wiki markup

Pass `contentFormat: "markdown"` and write plain markdown. Jira wiki markup (`h2.`,
`[text|url]`, `{code}`) does **not** render through the REST API or the MCP tools: it lands as
literal text in the ticket and nothing errors.

- `###` (h3) is the largest heading allowed, in issues and in comments. Never h1 or h2.
- `- ` for bullets, `1. ` for numbered lists, `[text](url)` for links.
- Default to short and scannable: one or two sentences of context, then a bulleted list, then the
  must-know note. Skip headings entirely unless the comment genuinely has several sections.
- Never paste credentials, tokens, or internal hostnames into a ticket.

## Jira: never invent a custom field id

`customfield_10001` in one instance is not the same field in another. A wrong id either errors or
**writes to the wrong field silently**, which nobody finds out about until an audit.

If a field id is not already known, discover it read-only before writing:

- MCP: `getJiraProjectIssueTypesMetadata`, then `getJiraIssueTypeMetaWithFields` for the target
  issue type. Returns the ids, which are required, and the allowed values.
- REST on a known-good ticket: `GET /rest/api/3/issue/<TICKET-ID>?expand=names` shows the ids next
  to human names, plus the exact value shape already stored in that field.

Report what you found (name, id, value shape, allowed values) before using it. Value shapes differ
per field: plain string, `{"value": ...}`, `{"id": ...}`, or an array. Take the shape from what
discovery returned, never from a guess.

If discovery is blocked, say so and create the ticket without that field, or stop if it is
required. Do not retry with a guessed id.

Sprint and other Agile board fields are usually not writable through the create API. When one
cannot be set, create the ticket and say it needs a manual move on the board, rather than failing
the whole write.

## GitLab issues: the flags that hang

```bash
glab issue create --title "..." --description "$(cat <tempfile>)" --label a,b --yes --no-editor
```

- **`--yes`**: without it, `glab` waits for a submit confirmation keypress nobody can send. It
  reads as a hung tool call, not as a stuck prompt.
- **`--no-editor`**: without it, `glab` opens `$EDITOR` for the description, same outcome.
- There is no `--description-file`. Write the body to a temp file first, then read it into
  `--description`, so newlines and backticks survive the shell.

## Sizing

For a PE ticket, use the `sp-suggest` skill to see the Story Points of the most similar past
tickets before proposing an estimate. It is a lookup, not a prediction: it anchors the number, the
estimate stays yours.
