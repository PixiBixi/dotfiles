#!/usr/bin/env bash
# Event: PreToolUse, matcher Bash.
# Denies the two command shapes CLAUDE.md bans and that kept coming back anyway (600 calls
# over 20 days): an inline shell function (`q(){ curl ...; }`) and a CLI held in a variable
# (`K=kubectl; $K get pods`). zsh breaks the second, and permission rules and the auto mode
# classifier cannot match either. Heredoc bodies are skipped: they are file content, not shell.
set -uo pipefail

input=$(cat) || exit 0
# Bash-only fast path: python only runs when a `()` or a CLI assignment is present at all.
# Must stay a superset of FUNC and CLI_VAR below.
[[ "$input" =~ \(\)([[:space:]]|\\[nt])*\{ || "$input" =~ =(\\\"|\')?(kubectl|gcx|glab|jira|gcloud) ]] || exit 0
command -v jq > /dev/null 2>&1 || exit 0
command -v python3 > /dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // ""' <<< "$input" 2> /dev/null) || exit 0
[ -n "$cmd" ] || exit 0

exec python3 -I - "$cmd" << 'PY'
import json, re, sys

cmd = sys.argv[1]

# Drop heredoc bodies: everything between `<<[-]['"]?TAG['"]?` and a line equal to TAG.
lines, out, tag = cmd.splitlines(), [], None
for line in lines:
    if tag is not None:
        if line.strip() == tag:
            tag = None
        continue
    out.append(line)
    m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line)
    if m:
        tag = m.group(1)
shell = "\n".join(out)

FUNC = re.compile(r"(?:^|[\s;&|(])(?:function\s+)?([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)\s*\{", re.M)
CLI_VAR = re.compile(r"(?:^|[\s;&|(])([A-Za-z_][A-Za-z0-9_]*)=[\"']?(kubectl|gcx|glab|jira|gcloud)(?=[\s\"';&|)]|$)", re.M)

reason = None
m = FUNC.search(shell)
if m:
    reason = (
        "Inline shell function `%s()` denied: CLAUDE.md bans wrapper functions (zsh parse "
        "errors, and permission rules cannot match them). Write each command in full. For "
        "PromQL use `thq` (`thq r '<expr>' --since 6h`, `-c <gcx context>`, `--ds <alias>`), "
        "never a curl wrapper." % m.group(1)
    )
else:
    m = CLI_VAR.search(shell)
    if m:
        reason = (
            "`%s=%s` denied: never hold a CLI in a variable, `$%s ...` fails under zsh and "
            "permission rules only match the literal command. Write `%s --context X ...` in "
            "full each time; put repeated flags in an array instead." % (m.group(1), m.group(2), m.group(1), m.group(2))
        )

if reason:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
PY
