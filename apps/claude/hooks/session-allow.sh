#!/usr/bin/env bash
# session-allow.sh — Claude PermissionRequest hook
# No Python, no multiprocessing overhead — osascript + jq only

SESSION_MAX_AGE=43200 # 12 hours
TEMP_DIR="${TEMP:-${TMP:-/tmp}}"
NL=$'\n'

# ── Output helpers ────────────────────────────────────────────────────────────

allow() {
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
    exit 0
}

deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}\n'
    exit 0
}

escalate() { exit 1; }

# ── Allowlist ─────────────────────────────────────────────────────────────────

allowlist_file() { printf '%s/claude-session-allow-%s.txt' "$TEMP_DIR" "$1"; }

read_allowlist() {
    local file="$1"
    [[ ! -f "$file" ]] && return
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -f %m "$file" 2> /dev/null) || {
        rm -f "$file"
        return
    }
    age=$((now - mtime))
    if ((age >= SESSION_MAX_AGE)); then
        rm -f "$file"
        return
    fi
    grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' || true
}

record_prefix() {
    local prefix="$1" file="$2"
    grep -qxF "$prefix" "$file" 2> /dev/null || printf '%s\n' "$prefix" >> "$file"
}

# ── Command parsing ───────────────────────────────────────────────────────────

# "git commit -m foo" → "git commit"  |  "ls -la" → "ls"
extract_prefix() {
    local w1 w2
    read -r w1 w2 <<< "$1"
    if [[ -n "$w2" && ! "$w2" =~ ^[-/\.~\$\"\'\|\&\>\<] ]]; then
        printf '%s %s' "$w1" "$w2"
    else
        printf '%s' "$w1"
    fi
}

# Split compound command on |  ||  &&  ; → output "TAG:prefix" per sub-command
get_shell_prefixes() {
    local command="$1" tag="$2"
    local split
    split=$(printf '%s' "$command" \
        | sed "s/&&/${NL}/g; s/||/${NL}/g; s/|/${NL}/g; s/;/${NL}/g")
    while IFS= read -r sub; do
        sub="${sub#"${sub%%[![:space:]]*}"}"
        sub="${sub%"${sub##*[![:space:]]}"}"
        [[ -z "$sub" ]] && continue
        local pfx
        pfx=$(extract_prefix "$sub")
        [[ -n "$pfx" ]] && printf '%s:%s\n' "$tag" "$pfx"
    done <<< "$split"
}

# Returns 0 if every sub-command prefix-matches the allowlist
is_shell_allowed() {
    local command="$1" tag="$2" al="$3"
    local split
    split=$(printf '%s' "$command" \
        | sed "s/&&/${NL}/g; s/||/${NL}/g; s/|/${NL}/g; s/;/${NL}/g")
    while IFS= read -r sub; do
        sub="${sub#"${sub%%[![:space:]]*}"}"
        sub="${sub%"${sub##*[![:space:]]}"}"
        [[ -z "$sub" ]] && continue
        local tool_key found=0
        tool_key="${tag}:${sub}"
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            [[ "$tool_key" == "$entry"* ]] && {
                found=1
                break
            }
        done <<< "$al"
        ((found)) || return 1
    done <<< "$split"
    return 0
}

# ── Dialog ────────────────────────────────────────────────────────────────────

as_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

prompt_user() {
    local display="$1" prefix="$2" header="$3"
    ((${#display} > 300)) && display="${display:0:300}…"
    # Flatten embedded newlines to " | " for AppleScript compatibility
    display="${display//$'\n'/ | }"
    local sd sh sp
    sd=$(as_escape "$display")
    sh=$(as_escape "$header")
    sp=$(as_escape "$prefix")
    local out
    out=$(
        osascript << OSASCRIPT 2> /dev/null
display dialog "${sd}
prefix: ${sp}" buttons {"Session", "Once", "Deny", "Claude"} default button "Once" with title "Claude — ${sh}"
OSASCRIPT
    ) || {
        printf 'c'
        return
    }
    local btn
    btn=$(printf '%s' "$out" | sed 's/button returned://' | tr -d '[:space:]')
    case "$btn" in
        Session) printf 's' ;;
        Once) printf 'o' ;;
        Deny) printf 'd' ;;
        *) printf 'c' ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    command -v jq &> /dev/null || escalate

    local input
    input=$(cat) || escalate

    local tool_name session_id
    tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""') || escalate
    session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"') || escalate
    [[ -z "$tool_name" ]] && escalate

    local al_file al_content prefix display header command="" tag=""
    al_file=$(allowlist_file "$session_id")
    al_content=$(read_allowlist "$al_file")

    # ── Build tool identity ──────────────────────────────────────────────────
    if [[ "$tool_name" == "Bash" ]]; then
        tag="Bash"
        header="Allow Bash command:"
        command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""') || escalate
        [[ -z "$command" ]] && escalate
        local raw_prefixes
        raw_prefixes=$(get_shell_prefixes "$command" "$tag")
        prefix=$(printf '%s' "$raw_prefixes" | tr '\n' '|' | sed 's/|$//; s/|/ | /g')
        display="$command"

    elif [[ "$tool_name" == "mcp__plugin_serena_serena__execute_shell_command" ]]; then
        tag="Serena"
        header="Allow Serena shell:"
        command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""') || escalate
        [[ -z "$command" ]] && escalate
        local raw_prefixes
        raw_prefixes=$(get_shell_prefixes "$command" "$tag")
        prefix=$(printf '%s' "$raw_prefixes" | tr '\n' '|' | sed 's/|$//; s/|/ | /g')
        display="$command"

    elif [[ "$tool_name" == mcp__* ]]; then
        header="Allow tool:"
        local action server_raw server
        action=$(printf '%s' "$tool_name" | awk -F'__' '{print $NF}')
        server_raw=$(printf '%s' "$tool_name" | awk -F'__' '{print $(NF-1)}')
        server=$(printf '%s' "$server_raw" | awk -F'_' '{print $NF}')
        display="${server} :: ${action}"
        local fpath
        fpath=$(printf '%s' "$input" | jq -r '.tool_input.relative_path // .tool_input.file_path // ""') || true
        [[ -n "$fpath" ]] && display="${display}"$'\n'"file: ${fpath}"
        prefix="$tool_name"

    else
        header="Allow tool:"
        display="$tool_name"
        local fpath
        fpath=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.relative_path // ""') || true
        [[ -n "$fpath" ]] && display="${display}"$'\n'"file: ${fpath}"
        prefix="$tool_name"
    fi

    # ── Check allowlist ──────────────────────────────────────────────────────
    if [[ -n "$al_content" ]]; then
        if [[ -n "$tag" ]]; then
            is_shell_allowed "$command" "$tag" "$al_content" && allow
        else
            while IFS= read -r entry; do
                [[ -z "$entry" ]] && continue
                [[ "$tool_name" == "$entry"* ]] && allow
            done <<< "$al_content"
        fi
    fi

    # ── Prompt user ──────────────────────────────────────────────────────────
    local key
    key=$(prompt_user "$display" "$prefix" "$header")

    case "$key" in
        s)
            if [[ -n "$tag" ]]; then
                while IFS= read -r p; do
                    [[ -n "$p" ]] && record_prefix "$p" "$al_file"
                done <<< "$(get_shell_prefixes "$command" "$tag")"
            elif [[ -n "$prefix" ]]; then
                record_prefix "$prefix" "$al_file"
            fi
            allow
            ;;
        o) allow ;;
        d) deny ;;
        *) escalate ;;
    esac
}

main
