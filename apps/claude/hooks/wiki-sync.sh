#!/usr/bin/env bash
# Updates the openwiki when a session ends, then ships it. Global: every repo
# gets this hook, so the first guard is what keeps it from spawning a session in
# the repos that have no wiki at all.
#
# It runs detached and unattended, so every exit below is a deliberate no-op
# rather than an error: there is nobody to read one. A wiki left uncommitted is
# recoverable, a background push that swept up somebody's half-finished work is
# not, which is why each guard fails towards doing nothing.
set -uo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

# The reason this can live in dotfiles at all.
[ -d openwiki ] || exit 0

# Detached means nobody sees a failure, so keep a trace. Set up after the
# openwiki guard so the repos without a wiki stay silent, and capped because
# nothing ever prunes it.
LOG="$HOME/.claude/logs/wiki-sync.log"
mkdir -p "${LOG%/*}" 2> /dev/null
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 262144 ]; then
    tail -c 131072 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${PWD##*/}" "$*" >> "$LOG"; }

# One trap for the whole script: a second one later would silently replace this
# one and lose the exit line. MSG is only set much further down.
on_exit() {
    rc=$?
    rm -f "${MSG:-}"
    log "exit rc=$rc"
}
trap on_exit EXIT

log "start"

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

# Only ever act on the repo's own default branch, read from the remote rather
# than assumed to be main. A feature branch, a rebase in progress or a detached
# HEAD all mean somebody is mid-something, and a background commit is the last
# thing that should join in.
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2> /dev/null | sed 's|^origin/||')
[ -n "$DEFAULT" ] || exit 0
[ "$(git rev-parse --abbrev-ref HEAD 2> /dev/null)" = "$DEFAULT" ] || exit 0
[ -d "$(git rev-parse --git-path rebase-merge)" ] && exit 0
[ -d "$(git rev-parse --git-path rebase-apply)" ] && exit 0

# Staged work belongs to whoever staged it. Committing on top of somebody's
# index would fold their change into a docs commit and lose it from theirs.
git diff --cached --quiet || exit 0

# --strict-mcp-config loads no MCP server: this task only edits files, and the
# tool definitions cost startup time and input tokens for nothing. The budget is
# the only bound on a run that goes wrong, there is no interactive Ctrl-C here.
claude -p '/openwiki:wiki update' --permission-mode acceptEdits \
    --strict-mcp-config --max-budget-usd 3 > /dev/null 2>&1
log "wiki update rc=$?"

# Format before staging rather than letting a pre-commit hook find it: such a
# hook aborts the commit when it rewrites a file, and there is nobody here to
# re-add and retry. Harmless where the repo has no Prettier.
npx --no-install prettier --write openwiki/ > /dev/null 2>&1

# -A picks up new pages, which the update mode does add. Scoped to openwiki/ so
# anything else dirty in the tree stays exactly where its owner left it.
git add -A -- openwiki/
git diff --cached --quiet && exit 0

MSG=$(mktemp) || exit 0

# Written from the actual diff rather than a fixed string: a log whose every
# subject reads "sync the wiki" is one nobody reads, and the whole point of the
# update is that it says something specific. Sonnet because describing a diff
# follows a pattern rather than making a judgement. The diff is capped so a
# large update cannot blow up the call.
git diff --cached -- openwiki/ | head -c 60000 | claude -p \
    'Write a Conventional Commits message for this openwiki documentation diff.

First line: docs(wiki): <what changed>, imperative, under 72 characters.
Then a blank line, then one to three short paragraphs saying what the docs
claimed before, why that was wrong or incomplete, and what they say now.

Plain hyphens, never em dashes. No markdown fences, no preamble, no sign-off.
Output the raw commit message and nothing else.' \
    --model sonnet --strict-mcp-config --max-budget-usd 1 > "$MSG" 2> /dev/null

# Fall back rather than lose the update. A generation that failed, timed out or
# returned prose must not leave the wiki uncommitted, and cog check rejects a
# malformed subject outright in the repos that run it.
if ! head -1 "$MSG" | grep -qE '^docs\(wiki\): .{10,}'; then
    printf 'docs(wiki): sync from the session that just ended\n\nWritten by the SessionEnd hook, scoped to openwiki/.\n' > "$MSG"
fi

git commit -F "$MSG" > /dev/null || exit 0
log "committed $(git rev-parse --short HEAD)"

# Never rebase and never force in the background. If the remote moved while this
# ran, the commit stays local and the next session pushes it.
git push origin "$DEFAULT" > /dev/null 2>&1 || {
    log "push failed, commit stays local"
    exit 0
}
log "pushed to $DEFAULT"
