#!/usr/bin/env python3
"""Second pass: Bash command families, Read patterns, sdk-py origin, cost by token type."""
import json, os, sys, glob, re
from collections import defaultdict, Counter
from datetime import datetime, timezone, timedelta

ROOT = os.path.expanduser("~/.claude/projects")
SINCE = datetime.now(timezone.utc) - timedelta(days=int(os.environ.get("AUDIT_DAYS", "30")))
files = [f for f in glob.glob(f"{ROOT}/**/*.jsonl", recursive=True) if os.path.getmtime(f) >= SINCE.timestamp()]

bash_cmd = {}
fam_n, fam_chars = Counter(), Counter()
read_full, read_partial, read_chars_full = 0, 0, 0
read_ids = {}
sdk = Counter()
sdk_cost_proj = Counter()
gap_hist = Counter()
seen = set()
reread = Counter()  # same file read multiple times in a session
sess_reads = defaultdict(Counter)
prompt_len = []

def family(cmd):
    c = cmd.strip()
    c = re.sub(r"^(cd [^&;]+(&&|;)\s*)+", "", c)
    c = re.sub(r"^(\w+=\S+\s+)+", "", c)
    w = c.split()
    if not w: return "?"
    head = w[0].split("/")[-1]
    if head in ("command", "rtk", "time", "sudo") and len(w) > 1: head = w[1].split("/")[-1]; w = w[1:]
    if head in ("kubectl", "glab", "gcloud", "gcx", "git", "jira", "helm", "terragrunt", "terraform", "gh", "confluence", "argocd") and len(w) > 1:
        sub = next((x for x in w[1:] if not x.startswith("-") and "=" not in x), "")
        if head == "kubectl":
            # kubectl --context X -n Y get pods -> get
            ws = [x for x in w[1:]]
            skip = False; sub = ""
            for x in ws:
                if skip: skip = False; continue
                if x in ("--context", "-n", "--namespace", "-c", "-l", "-o"): skip = True; continue
                if x.startswith("-"): continue
                sub = x; break
        return f"{head} {sub}"
    return head

for f in files:
    is_sub = "/subagents/" in f
    last_t = None
    for line in open(f, errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
        ts = d.get("timestamp")
        if not ts: continue
        t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if t < SINCE: continue
        m = d.get("message") or {}
        if d.get("type") == "assistant":
            if d.get("entrypoint") == "sdk-py":
                key = (m.get("id"), d.get("requestId"))
                if key not in seen and m.get("usage"):
                    seen.add(key); sdk[d.get("cwd")] += 1
            for c in m.get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use": continue
                inp = c.get("input") or {}
                if c.get("name") == "Bash":
                    bash_cmd[c["id"]] = family(inp.get("command", ""))
                elif c.get("name") == "Read":
                    p = inp.get("file_path", "")
                    partial = bool(inp.get("offset") or inp.get("limit"))
                    read_ids[c["id"]] = partial
                    sess_reads[d.get("sessionId")][p] += 1
            if not is_sub and d.get("entrypoint") == "cli":
                if last_t is not None and m.get("usage"):
                    g = (t - last_t).total_seconds() / 60
                    b = "<5m" if g < 5 else "5-60m" if g < 60 else "1-4h" if g < 240 else "4-24h" if g < 1440 else ">1d"
                    gap_hist[b] += 1
                if m.get("usage"): last_t = t
        elif d.get("type") == "user":
            cont = m.get("content")
            if isinstance(cont, str) and not is_sub and not d.get("isMeta") and not cont.startswith("<"):
                prompt_len.append(len(cont))
            if isinstance(cont, list):
                for c in cont:
                    if not isinstance(c, dict) or c.get("type") != "tool_result": continue
                    rc = c.get("content")
                    n = sum(len(x.get("text", "")) for x in rc if isinstance(x, dict)) if isinstance(rc, list) else len(str(rc or ""))
                    tid = c.get("tool_use_id")
                    if tid in bash_cmd:
                        fam_n[bash_cmd[tid]] += 1; fam_chars[bash_cmd[tid]] += n
                    elif tid in read_ids:
                        if read_ids[tid]: read_partial += 1
                        else: read_full += 1; read_chars_full += n

rereads = sum(v - 1 for s in sess_reads.values() for v in s.values() if v > 1)
out = dict(
    bash_fam=[(k, fam_n[k], round(v / 1000)) for k, v in fam_chars.most_common(45)],
    read=dict(full=read_full, partial=read_partial, full_kchars=round(read_chars_full / 1000), rereads=rereads),
    sdk=sdk.most_common(10), gaps=dict(gap_hist),
    prompt_len=dict(n=len(prompt_len), median=sorted(prompt_len)[len(prompt_len)//2], p90=sorted(prompt_len)[int(len(prompt_len)*.9)]),
)
json.dump(out, open(sys.argv[1], "w"), indent=1)
print(json.dumps(out, indent=1))
