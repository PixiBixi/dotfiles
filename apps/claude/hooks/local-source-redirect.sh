#!/usr/bin/env bash
# Event: PreToolUse, matcher WebFetch.
# Denies a WebFetch of public code on github.com or gitlab.com (blob/tree/raw URLs, repo
# roots) and points Claude at the local clone under $SRC_DIR, or at the clone command when
# there is none. Issues, PRs, releases and any other page pass through untouched.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/Documents/work/src}"

url="$(jq -r '.tool_input.url // empty')"
[[ -z "$url" ]] && exit 0
url="${url%%[?#]*}"
url="${url%/}"

project="" ref="" path="" kind="blob"
if [[ "$url" =~ ^https?://(www\.)?github\.com/([^/]+)/([^/]+)(/(blob|tree|raw)/([^/]+)(/(.*))?)?$ ]]; then
    project="github.com/${BASH_REMATCH[2]}/${BASH_REMATCH[3]%.git}"
    kind="${BASH_REMATCH[5]:-tree}" ref="${BASH_REMATCH[6]}" path="${BASH_REMATCH[8]}"
elif [[ "$url" =~ ^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)$ ]]; then
    project="github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    ref="${BASH_REMATCH[3]}" path="${BASH_REMATCH[4]}"
elif [[ "$url" =~ ^https?://gitlab\.com/(.+)/-/(blob|tree|raw)/([^/]+)(/(.*))?$ ]]; then
    project="gitlab.com/${BASH_REMATCH[1]}"
    kind="${BASH_REMATCH[2]}" ref="${BASH_REMATCH[3]}" path="${BASH_REMATCH[5]}"
elif [[ "$url" =~ ^https?://gitlab\.com/([^/-][^/]*(/[^/-][^/]*)+)$ ]]; then
    project="gitlab.com/${BASH_REMATCH[1]%.git}" kind="tree"
    [[ "$project" =~ ^gitlab\.com/(explore|users|dashboard|help|search|groups|projects)/ ]] && exit 0
else
    exit 0
fi
# github.com/<org>/<repo>/<anything but blob|tree|raw> is an issue, PR, release... page.
if [[ "$project" == github.com/* && "$url" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/ && -z "$ref" ]]; then
    exit 0
fi

# https://host/a/b.git, git@host:a/b.git, ssh://git@host/a/b -> host/a/b
normalize() {
    local u="${1%.git}"
    u="${u%/}"
    u="${u#*://}"
    u="${u#*@}"
    echo "${u/://}" | tr '[:upper:]' '[:lower:]'
}

want="$(echo "$project" | tr '[:upper:]' '[:lower:]')"
# One rg over every .git/config: a git call per repo costs ~2s on 80 clones.
clone=""
while IFS= read -r line; do
    remote="${line#*url = }"
    if [[ "$(normalize "$remote")" == "$want" ]]; then
        clone="${line%%/.git/config:*}"
        break
    fi
done < <(command rg --no-heading --no-line-number -m 1 '^\s*url = ' "$SRC_DIR"/*/.git/config "$SRC_DIR"/helm/*/.git/config 2> /dev/null || true)

steps=""
if [[ -z "$clone" ]]; then
    name="${project##*/}"
    [[ -e "$SRC_DIR/$name" ]] && name="$(basename "$(dirname "$project")")-$name"
    clone="$SRC_DIR/$name"
    steps="Not cloned yet. Clone it first: git clone --filter=blob:none https://$project $clone"$'\n'
else
    steps="Local clone: $clone. Refresh it first: git -C $clone fetch --quiet --tags origin"$'\n'
fi

# A branch name is read from origin/<ref> so a stale local branch is never used.
target="${ref:-origin/HEAD}"
if [[ -n "$ref" ]] && git -C "$clone" show-ref --quiet --verify "refs/remotes/origin/$ref" 2> /dev/null; then
    target="origin/$ref"
elif [[ -n "$ref" && ! -d "$clone" ]]; then
    target="$ref (use origin/$ref if it is a branch)"
fi

if [[ "$kind" == "tree" ]]; then
    steps+="Then list it: git -C $clone ls-tree --name-only ${target}:${path}"$'\n'
    steps+="Or search it: rg <pattern> $clone${path:+/$path}"
else
    steps+="Then read it: git -C $clone show ${target}:${path}"
fi

reason="Public source code is read from local clones in $SRC_DIR, not fetched over the web."$'\n'"$steps"
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
