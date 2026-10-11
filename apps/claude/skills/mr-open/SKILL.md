---
name: mr-open
description: >
  Use when committing work and opening or updating a GitLab MR or GitHub PR from the current
  repo: "fais la MR", "ouvre la MR", "commit & push", "fais des commits propres et push",
  "fix ça et ouvre la MR après", "push et MR", "ajoute un commit à la MR", "update la MR".
  Covers the branch base, author identity, signed per-scope commits, rebase, creation, the
  description update and the URL handover. Org rules (labels, ticket key in the title) come
  from the project CLAUDE.md. Not for merging, reviewing, or answering review threads.
---

# Open an MR

## 1. Preflight

| Check | Command | Fix |
|---|---|---|
| Target branch, never assumed `main` | `git symbolic-ref --short refs/remotes/origin/HEAD` | |
| Author email set on this repo (there is no global one) | `git config user.email` | `PixiBixi@users.noreply.github.com` on anything public; the work address on internal GitLab |
| Signing not disabled locally | `git config --get commit.gpgsign` is `true` | `git config --local --unset commit.gpgsign` |
| An MR already open for the branch | `glab mr list --source-branch <branch> -F json` / `gh pr list --head <branch>` | Push to it and update it, never a second one |
| Currently on the target branch | `git branch --show-current` | Branch first, below |

New branch, always from the freshly fetched remote: a local target branch may carry unpushed commits that would leak into the MR.

```bash
TARGET=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||')
git fetch origin "$TARGET"
git checkout -b fix/store-memory-cap "origin/$TARGET"
```

## 2. Commits

- One commit per scope (`fix(tflint):`, `feat(module):`, `chore(live):`): two scopes in the diff means two commits, staged by path, never `git add -A`.
- Conventional Commits, English, ticket key in the subject or body when there is one. The body says why, wrapped at 72.
- README updated in the same change when a flag, feature or behavior changed.
- Every commit signed: `git log --format="%h %G? %s" "origin/$TARGET..HEAD"` shows `G` on each line. Repair unsigned ones with `git rebase --exec "git commit --amend --no-edit -S --quiet" "origin/$TARGET"`, never `reset --hard`.

## 3. Push

```bash
git fetch origin "$TARGET"
git rebase "origin/$TARGET"
git push --force-with-lease -u origin HEAD
```

Rebase locally: a server-side rebase (`glab mr rebase`, the web button) rewrites the commits unsigned.

## 4. Create

Description in a file so newlines and backticks survive: what, why, test evidence, rollback for infra changes. English, no narrated investigation, no hard wrap. Wording and length rules: `ticket-conventions`.

```bash
glab mr create \
  --target-branch "$TARGET" \
  --title "fix(store): cap memory at 6Gi" \
  --description-file "$BODY" \
  --remove-source-branch \
  --yes
```

- `--yes` is mandatory: without it `glab` waits for a confirmation nobody can send.
- Labels, ticket key placement and any compliance label: whatever the project CLAUDE.md says, applied at creation.
- GitHub: `gh pr create --base "$TARGET" --title ... --body-file "$BODY"`.

## 5. After

1. `echo "<url>" | pbcopy`, then answer with the link and one line.
2. New commits on an open MR: push, then rewrite the description to cover them (`glab mr update <iid> --description-file "$BODY"`).
3. Offer the follow-up reminder in one line (`tickler`) when the change should move performance or cost.

## Common mistakes

| Mistake | Instead |
|---|---|
| Branching from the local target branch | `origin/<target>` after a fetch |
| One commit mixing two scopes | One commit per scope |
| `glab mr create` without `--yes` | Hangs; always `--yes` |
| `--description "$(...)"` with inline backticks | `--description-file` |
| Server-side rebase | Local rebase, commits stay signed |
| Description left stale after new commits | `glab mr update --description-file` |
| French in the MR | English, even in a French session |
