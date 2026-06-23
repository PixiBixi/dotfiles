---
name: addressing-gitlab-review-comments
description: Use when a reviewer left inline (line-anchored) comments on a GitLab merge request and you need to fetch them with their file+line, fix the code, then reply to and resolve each thread with glab.
---

# Addressing GitLab MR Review Comments

## Overview

Inline review comments on a GitLab MR live in **discussions** (threads anchored to a file+line). The whole loop — fetch with position → fix → reply → resolve — runs through `glab api`. This skill is the proven command sequence; the gotcha is that the obvious command (`glab mr view --comments`) gives you the comment text but **not the file/line position**, so you can't tell what each comment refers to.

**REQUIRED BACKGROUND:** Use `superpowers:receiving-code-review` for the judgment part — evaluate each comment with technical rigor and verify it's correct *before* applying. This skill only covers the GitLab mechanics.

## Setup

```bash
MR=511                                          # the MR iid
PROJ="smartadserver%2Fprivate%2Finfra%2Fk8s%2Fargocd-pl-tooling"   # URL-encoded full path
API="projects/$PROJ/merge_requests/$MR"
```
URL-encode the path (`/` → `%2F`). Get it from `glab repo view` if unsure.

## 1. Fetch comments WITH position

`glab mr view $MR --comments` does NOT include line positions — don't use it for inline comments. Hit the discussions API and parse `position`:

```bash
glab api "$API/discussions" | python3 -c '
import sys, json
for d in json.load(sys.stdin):
    n = d["notes"][0]
    if n.get("system"): continue
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
git commit -am "PE-XXXX: address review on <thing>"
git push        # plain push — adding a commit, no force needed
```

## 3. Reply to and resolve each thread

Posting to a discussion's `notes` endpoint auto-threads the reply (no `in_reply_to_id` needed). Then PUT `resolved=true`:

```bash
DISC="<discussion id from step 1>"
glab api -X POST "$API/discussions/$DISC/notes" -f "body=Done — <what you changed>."
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

## Quick Reference

| Step | Command |
|------|---------|
| List inline comments + position | `glab api "$API/discussions"` → parse `.notes[].position.{new_path,new_line,old_line}` |
| Reply to a thread | `glab api -X POST "$API/discussions/<id>/notes" -f "body=..."` |
| Resolve a thread | `glab api -X PUT "$API/discussions/<id>?resolved=true"` |

## Common Mistakes

- **Using `glab mr view --comments` for inline comments** — gives text without file/line; you can't locate them. Use the discussions API.
- **Inventing `glab mr note resolve`** — resolve via `glab api -X PUT ".../discussions/<id>?resolved=true"`.
- **Reading `old_line` instead of `new_line`** — for a comment on a changed line, the current code is at `new_line`.
- **Force-pushing to address review** — you're adding a commit on a pushed branch; a plain `git push` is enough (force only if you rebased).
- **Applying comments blindly** — evaluate first (receiving-code-review). Reply with what you actually changed, then resolve.
