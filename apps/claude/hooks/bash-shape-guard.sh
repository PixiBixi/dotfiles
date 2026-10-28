#!/usr/bin/env bash
# Event: PreToolUse, matcher Bash.
# Denies the command shapes CLAUDE.md bans and that kept coming back anyway (600 calls
# over 20 days): an inline shell function (`q(){ curl ...; }`), a CLI held in a variable
# (`K=kubectl; $K get pods`), and a foreground until/while + sleep poll on kubectl/glab/gcx
# (blocks the session; it belongs in run_in_background or `glab ci status --live`).
# zsh breaks the second, and permission rules and the auto mode classifier cannot match the
# first two. Heredoc bodies are skipped: they are file content, not shell.
set -uo pipefail

input=$(cat) || exit 0
# Bash-only fast path: python only runs when a `()` or a CLI assignment is present at all.
# Must stay a superset of FUNC and CLI_VAR below.
[[ "$input" =~ \(\)([[:space:]]|\\[nt])*\{ || "$input" =~ =(\\\"|\')?(kubectl|gcx|glab|jira|gcloud) || "$input" =~ (until|while)[[:space:]] ]] || exit 0
command -v jq > /dev/null 2>&1 || exit 0
command -v python3 > /dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // ""' <<< "$input" 2> /dev/null) || exit 0
[ -n "$cmd" ] || exit 0
bg=$(jq -r '.tool_input.run_in_background // false' <<< "$input" 2> /dev/null) || bg=false

exec python3 -I - "$cmd" "$bg" << 'PY'
import json, re, sys

cmd, bg = sys.argv[1], sys.argv[2] == "true"

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
POLL = re.compile(r"(?:^|[\s;&|(])(?:until|while)\s", re.M)

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
    elif not bg and POLL.search(shell) and re.search(r"\bsleep\b", shell) and re.search(r"\b(kubectl|glab|gcx)\b", shell):
        reason = (
            "Foreground poll loop denied: it blocks the session. Pipelines: `glab ci status --live`. "
            "ArgoCD sync: the argocd-change-verify waiter (post-merge-verify). Anything else: the "
            "same until-loop with run_in_background, capped in time, so it notifies once."
        )

if reason:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
PY
