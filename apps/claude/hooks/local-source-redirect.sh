#!/usr/bin/env bash
# Event: PreToolUse, matcher WebFetch.
# Denies a WebFetch of code on github.com or gitlab.com (blob/tree/raw URLs, repo roots)
# and points Claude at the local clone, or at the clone command when there is none.
# Issues, PRs, releases and any other page pass through untouched.
#
# Clones live under $SRC_DIR, except for prefixes listed in $SOURCE_ROOTS_FILE, one
# "<host/group> <local dir>" per line: those mirror the forge tree and clone over SSH.
set -euo pipefail

SRC_DIR="${SRC_DIR:-$HOME/Documents/work/src}"
SOURCE_ROOTS_FILE="${SOURCE_ROOTS_FILE:-$HOME/.config/claude/source-roots}"

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
clone="" clone_url="https://$project"

if [[ -r "$SOURCE_ROOTS_FILE" ]]; then
    while read -r prefix root _; do
        [[ -z "$prefix" || "$prefix" == \#* ]] && continue
        prefix="$(echo "${prefix%/}" | tr '[:upper:]' '[:lower:]')"
        if [[ "$want" == "$prefix" || "$want" == "$prefix"/* ]]; then
            clone="${root%/}${project:${#prefix}}"
            host="${project%%/*}"
            clone_url="git@$host:${project#*/}.git"
            break
        fi
    done < "$SOURCE_ROOTS_FILE"
fi

# One rg over every .git/config: a git call per repo costs ~2s on 80 clones.
[[ -z "$clone" ]] && while IFS= read -r line; do
    remote="${line#*url = }"
    if [[ "$(normalize "$remote")" == "$want" ]]; then
        clone="${line%%/.git/config:*}"
        break
    fi
done < <(command rg --no-heading --no-line-number -m 1 '^\s*url = ' "$SRC_DIR"/*/.git/config "$SRC_DIR"/helm/*/.git/config 2> /dev/null || true)

steps=""
if [[ -d "$clone" && ! -e "$clone/.git" ]]; then
    # A group page under a source root: the directory holds the group's projects.
    reason="Source code is read from local clones, not fetched over the web."$'\n'"Local group directory: $clone. List it: lsd $clone, or search it: rg <pattern> $clone"
    jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
fi
if [[ -z "$clone" ]]; then
    name="${project##*/}"
    [[ -e "$SRC_DIR/$name" ]] && name="$(basename "$(dirname "$project")")-$name"
    clone="$SRC_DIR/$name"
fi
if [[ ! -e "$clone/.git" ]]; then
    steps="Not cloned yet. Clone it first: git clone --filter=blob:none $clone_url $clone"$'\n'
else
    steps="Local clone: $clone. Refresh it first: git -C $clone fetch --quiet --tags origin"$'\n'
fi

# A branch name is read from origin/<ref> so a stale local branch is never used.
target="${ref:-origin/HEAD}"
if [[ -n "$ref" ]] && git -C "$clone" show-ref --quiet --verify "refs/remotes/origin/$ref" 2> /dev/null; then
    target="origin/$ref"
fi
note=""
if [[ -n "$ref" && ! -e "$clone/.git" ]]; then
    target="origin/$ref"
    note=$'\n'"If $ref is a tag or a commit rather than a branch, drop the origin/ prefix."
fi

if [[ "$kind" == "tree" ]]; then
    steps+="Then list it: git -C $clone ls-tree --name-only ${target}:${path}"$'\n'
    steps+="Or search it: rg <pattern> $clone${path:+/$path}"
else
    steps+="Then read it: git -C $clone show ${target}:${path}"
fi

reason="Source code is read from local clones, not fetched over the web."$'\n'"$steps$note"
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
