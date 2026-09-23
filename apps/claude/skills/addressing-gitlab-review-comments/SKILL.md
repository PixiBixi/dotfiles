---
name: addressing-gitlab-review-comments
description: Use when a reviewer left inline (line-anchored) comments on a GitLab merge request and you need to fetch them with their file+line, fix the code, then reply to and resolve each thread with glab.
---

# Addressing GitLab MR Review Comments

## Overview

Inline review comments on a GitLab MR live in **discussions** (threads anchored to a file+line). The whole loop (fetch with position → fix → reply → resolve) runs through `glab api`. This skill is the proven command sequence; the gotcha is that the obvious command (`glab mr view --comments`) gives you the comment text but **not the file/line position**, so you can't tell what each comment refers to.

**REQUIRED BACKGROUND:** Use `superpowers:receiving-code-review` for the judgment part: evaluate each comment with technical rigor and verify it's correct *before* applying. This skill only covers the GitLab mechanics.

## Setup

```bash
MR=511                                          # the MR iid
PROJ="<group>%2F<subgroup>%2F<project>"         # URL-encoded full path
API="projects/$PROJ/merge_requests/$MR"
```
URL-encode the path (`/` → `%2F`). Get it from `glab repo view` if unsure.

## 1. Fetch comments WITH position

`glab mr view $MR --comments` does NOT include line positions, so don't use it for inline comments. Hit the discussions API and parse `position`. `--paginate` is mandatory: the endpoint returns 20 threads per page, and without it the rest are dropped with no error. Already-resolved threads are skipped:

```bash
glab api --paginate --output ndjson "$API/discussions" | python3 -c '
import sys, json
for line in sys.stdin:
    d = json.loads(line)
    n = d["notes"][0]
    if n.get("system") or n.get("resolved"): continue
    p = n.get("position") or {}
    print(d["id"], "|", n["author"]["username"], "|", n["body"])
    if p: print("   ->", p.get("new_path"), "new_line:", p.get("new_line"), "old_line:", p.get("old_line"))
'
```

- **`new_line`** = the line in the *current* (post-change) file → this is what you read to interpret the comment.
- A comment on a changed line carries both `old_line` and `new_line`; anchor on `new_path` + `new_line`.
- No `position` → it's a general (non-inline) comment.

## 2. Read the code at each `new_path:new_line`, then fix

Open the file at the cited line so the comment makes sense in context. Apply the fix only after evaluating it (see receiving-code-review). Commit as one review-fix commit and push:

```bash
git commit -am "fix(<scope>): address review on <thing>"   # Conventional Commits, ticket id in the body
git fetch origin <target> && git rebase origin/<target>
git push --force-with-lease   # a plain `git push` is enough only if the rebase was a no-op
```

## 3. Reply to and resolve each thread

Posting to a discussion's `notes` endpoint auto-threads the reply (no `in_reply_to_id` needed). Then PUT `resolved=true`:

```bash
DISC="<discussion id from step 1>"
glab api -X POST "$API/discussions/$DISC/notes" -f "body=Done: <what you changed>."
glab api -X PUT  "$API/discussions/$DISC?resolved=true"
```

Reusable helper:

```bash
reply_resolve() {  # $1=discussion-id  $2=reply text
  glab api -X POST "$API/discussions/$1/notes" -f "body=$2" >/dev/null \
  && glab api -X PUT "$API/discussions/$1?resolved=true" >/dev/null \
  && echo "done: $1"
}
```

## Writing the reply

Keep it to what changed and why. A reviewer wants the delta, not the investigation.

- **Applied**: one or two sentences. What you changed, anything you widened beyond the cited line, the commit sha. `Done, block style everywhere: all six components, not just this line. Rendered output unchanged. f6511f29`
- **Disagreed or deferred**: the decisive fact first, the option second, the ball back in their court. Two short paragraphs is the ceiling. Cut the retention aside, the third supporting argument, the "happy to discuss" closer.
- Never narrate the sequence of your own corrections, and never restate the reviewer's comment back at them.

## Which threads to resolve

Resolve only the ones you actually closed out.

- **Applied the change** -> reply + resolve.
- **Answered a question and the answer settles it** -> reply + resolve.
- **A decision that is not yours** (target environment, scope, priority) -> reply, **do not resolve**. Resolving a thread the reviewer still has to arbitrate reads as brushing it aside, and it drops off their review list.

## Quick Reference

| Step | Command |
|------|---------|
| List inline comments + position | `glab api --paginate --output ndjson "$API/discussions"` → parse `.notes[].position.{new_path,new_line,old_line}` |
| Reply to a thread | `glab api -X POST "$API/discussions/<id>/notes" -f "body=..."` |
| Resolve a thread | `glab api -X PUT "$API/discussions/<id>?resolved=true"` |

## Common Mistakes

- **Using `glab mr view --comments` for inline comments**: gives text without file/line; you can't locate them. Use the discussions API.
- **Inventing `glab mr note resolve`**: resolve via `glab api -X PUT ".../discussions/<id>?resolved=true"`.
- **Reading `old_line` instead of `new_line`**: for a comment on a changed line, the current code is at `new_line`.
- **Forgetting `--paginate`**: past 20 threads the discussions API silently returns only the first page.
- **Bare `--force` after the rebase**: use `--force-with-lease`, so a commit the reviewer pushed meanwhile is not overwritten.
- **Applying comments blindly**: evaluate first (receiving-code-review). Reply with what you actually changed, then resolve.
- **Truncating the discussion id when listing threads**: the API wants the full 40-char id, an 8-char prefix returns `404 Discussion Not Found`. Print `d["id"]` whole.
- **Over-explaining in the reply**: see "Writing the reply". The reasoning belongs in the MR description or the ticket.
- **Resolving a deferred decision**: if the reviewer still has to choose, leave the thread open.
