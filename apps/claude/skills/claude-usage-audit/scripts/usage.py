#!/usr/bin/env python3
"""Analyze Claude Code transcripts for the last N days. Output: JSON summary."""
import json, os, sys, glob, re
from collections import defaultdict, Counter
from datetime import datetime, timezone, timedelta

ROOT = os.path.expanduser("~/.claude/projects")
DAYS = 30
NOW = datetime.now(timezone.utc)
SINCE = NOW - timedelta(days=DAYS)

# $/MTok: input, output, cache_read ; writes = 1.25x (5m) / 2x (1h) input
PRICES = {
    "claude-fable-5-1": (10, 50, 0.25), "claude-fable-5": (10, 50, 1.0),
    "claude-opus-5-5": (4, 20, 0.20), "claude-opus-5": (5, 25, 0.5),
    "claude-opus-4-8": (5, 25, 0.5), "claude-opus-4-7": (5, 25, 0.5), "claude-opus-4-6": (5, 25, 0.5),
    "claude-sonnet-5-5": (2, 10, 0.20), "claude-sonnet-5": (2, 10, 0.2), "claude-sonnet-4-6": (3, 15, 0.3),
    "claude-haiku-5-5": (0.10, 0.50, 0.01), "claude-haiku-4-5": (1, 5, 0.1),
}

def price_for(model):
    if not model: return None
    for k in sorted(PRICES, key=len, reverse=True):
        if model.startswith(k): return PRICES[k]
    return None

def cost(model, u, speed):
    p = price_for(model)
    if not p: return 0.0
    i, o, cr = p
    mult = 2.0 if speed == "fast" else 1.0
    cc = u.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens", 0) or 0
    w5m = cc.get("ephemeral_5m_input_tokens", 0) or 0
    wtot = u.get("cache_creation_input_tokens", 0) or 0
    if w1h + w5m == 0: w5m = wtot
    return mult * (
        (u.get("input_tokens", 0) or 0) * i
        + (u.get("output_tokens", 0) or 0) * o
        + (u.get("cache_read_input_tokens", 0) or 0) * cr
        + w5m * i * 1.25 + w1h * i * 2.0
    ) / 1e6

def proj_name(path):
    d = os.path.relpath(path, ROOT).split(os.sep)[0]
    d = d.replace("-Users-jeremy-", "~/").replace("-Users-jeremy", "~")
    d = d.replace("Documents-work-git-smartadserver-private-", "work/private/")
    d = d.replace("Documents-work-git-smartadserver-", "work/")
    d = d.replace("Documents-perso-git-", "perso/")
    return d

files = [f for f in glob.glob(f"{ROOT}/**/*.jsonl", recursive=True)
         if os.path.getmtime(f) >= SINCE.timestamp()]

seen = set()
calls = []           # one per API request
tool_uses = Counter()
tool_result_chars = Counter()
tool_result_count = Counter()
tool_id_name = {}
skills = Counter()
agent_spawns = []    # (subagent_type, model, desc)
compactions = 0
user_prompts = []
big_results = []

for f in files:
    is_sub = "/subagents/" in f
    proj = proj_name(f)
    try:
        fh = open(f, errors="replace")
    except Exception:
        continue
    for line in fh:
        try:
            d = json.loads(line)
        except Exception:
            continue
        ts = d.get("timestamp")
        if not ts: continue
        try:
            t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except Exception:
            continue
        if t < SINCE: continue
        typ = d.get("type")
        if typ == "system" and d.get("subtype") == "compact_boundary":
            compactions += 1
        if typ == "assistant":
            m = d.get("message") or {}
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    cid = c.get("id")
                    if cid in tool_id_name: continue
                    name = c.get("name", "?")
                    tool_id_name[cid] = name
                    tool_uses[name] += 1
                    inp = c.get("input") or {}
                    if name == "Skill": skills[inp.get("skill", "?")] += 1
                    if name in ("Agent", "Task"):
                        agent_spawns.append((inp.get("subagent_type") or "general-purpose", inp.get("model") or "inherit", (inp.get("description") or "")[:60], proj))
            key = (m.get("id"), d.get("requestId"))
            u = m.get("usage")
            if not u or key in seen or m.get("model") in (None, "<synthetic>"): continue
            seen.add(key)
            calls.append(dict(
                t=t, model=m.get("model"), u=u, sub=is_sub or d.get("isSidechain", False),
                sess=d.get("sessionId"), proj=proj, effort=d.get("effort"), speed=u.get("speed"),
                entry=d.get("entrypoint"), file=f,
                cost=cost(m.get("model"), u, u.get("speed")),
            ))
        elif typ == "user":
            m = d.get("message") or {}
            cont = m.get("content")
            if isinstance(cont, str) and not is_sub and not d.get("isMeta"):
                if not cont.startswith("<") : user_prompts.append((t, proj, cont[:200]))
            if isinstance(cont, list):
                for c in cont:
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        name = tool_id_name.get(c.get("tool_use_id"), "?")
                        rc = c.get("content")
                        if isinstance(rc, list):
                            n = sum(len(x.get("text", "")) if isinstance(x, dict) else 0 for x in rc)
                            n += sum(6000 for x in rc if isinstance(x, dict) and x.get("type") == "image")
                        else:
                            n = len(str(rc or ""))
                        tool_result_chars[name] += n
                        tool_result_count[name] += 1
                        if n > 40000: big_results.append((n, name, proj, str(d.get("sessionId"))[:8]))

# ---------- aggregates ----------
def tok(u):
    return dict(inp=u.get("input_tokens", 0) or 0, out=u.get("output_tokens", 0) or 0,
                cr=u.get("cache_read_input_tokens", 0) or 0, cw=u.get("cache_creation_input_tokens", 0) or 0,
                think=(u.get("output_tokens_details") or {}).get("thinking_tokens", 0) or 0,
                w1h=(u.get("cache_creation") or {}).get("ephemeral_1h_input_tokens", 0) or 0)

def agg(rows):
    a = Counter()
    for r in rows:
        for k, v in tok(r["u"]).items(): a[k] += v
        a["cost"] += r["cost"]; a["calls"] += 1
    return a

tot = agg(calls)
by = lambda keyf: {k: agg(v) for k, v in _group(keyf).items()}
def _group(keyf):
    g = defaultdict(list)
    for r in calls: g[keyf(r)].append(r)
    return g

daily = by(lambda r: r["t"].astimezone().strftime("%Y-%m-%d"))
models = by(lambda r: r["model"])
main_sub = by(lambda r: "subagent" if r["sub"] else "main")
sub_models = by(lambda r: ("sub:" if r["sub"] else "main:") + r["model"])
projects = by(lambda r: r["proj"])
efforts = by(lambda r: str(r["effort"]))
hours = by(lambda r: r["t"].astimezone().hour)
weekday = by(lambda r: r["t"].astimezone().strftime("%a"))
entry = by(lambda r: str(r["entry"]))
speed = by(lambda r: str(r["speed"]))

# sessions
sess = _group(lambda r: r["sess"])
sessions = []
cache_miss_cost = 0.0
cache_miss_events = 0
idle_rewrites = 0
baseline = []
ctx_hist = Counter()
for sid, rows in sess.items():
    rows.sort(key=lambda r: r["t"])
    mains = [r for r in rows if not r["sub"]]
    a = agg(rows)
    ctxs = [tok(r["u"])["inp"] + tok(r["u"])["cr"] + tok(r["u"])["cw"] for r in mains]
    if mains:
        first = tok(mains[0]["u"]); baseline.append(first["cw"] + first["cr"] + first["inp"])
    for c in ctxs:
        b = "<50k" if c < 50e3 else "50-100k" if c < 100e3 else "100-200k" if c < 200e3 else "200-400k" if c < 400e3 else "400k-1M"
        ctx_hist[b] += 1
    # cache rebuilds: a main call whose cache write > 50% of context, not the first call
    prev = None
    for r in mains:
        k = tok(r["u"])
        ctx = k["inp"] + k["cr"] + k["cw"]
        if prev is not None and ctx > 20000 and k["cw"] > 0.6 * ctx:
            cache_miss_events += 1
            p = price_for(r["model"]) or (0, 0, 0)
            cache_miss_cost += k["cw"] * p[0] * (2.0 if k["w1h"] else 1.25) / 1e6 - k["cw"] * p[2] / 1e6
            if (r["t"] - prev["t"]).total_seconds() > 3600: idle_rewrites += 1
        prev = r
    sessions.append(dict(
        sid=sid[:8] if sid else "?", proj=rows[0]["proj"], start=rows[0]["t"].astimezone().strftime("%m-%d %H:%M"),
        dur_h=round((rows[-1]["t"] - rows[0]["t"]).total_seconds() / 3600, 1),
        calls=a["calls"], main_calls=len(mains), sub_calls=a["calls"] - len(mains),
        cost=round(a["cost"], 2), max_ctx=max(ctxs) if ctxs else 0,
        avg_ctx=int(sum(ctxs) / len(ctxs)) if ctxs else 0,
        out=a["out"], model=Counter(r["model"] for r in mains).most_common(1)[0][0] if mains else rows[0]["model"],
        file=rows[0]["file"],
    ))
sessions.sort(key=lambda s: -s["cost"])

# first user prompt per session file for top sessions
def first_prompt(path):
    try:
        for line in open(path, errors="replace"):
            d = json.loads(line)
            if d.get("type") == "user" and not d.get("isMeta"):
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str) and c.strip() and not c.startswith("<"):
                    return re.sub(r"\s+", " ", c)[:140]
                if isinstance(c, list):
                    for x in c:
                        if isinstance(x, dict) and x.get("type") == "text" and not x["text"].startswith("<"):
                            return re.sub(r"\s+", " ", x["text"])[:140]
    except Exception:
        pass
    return ""
for s in sessions[:40]:
    s["prompt"] = first_prompt(s["file"])
for s in sessions: s.pop("file", None)

cost_bins = Counter()
for s in sessions:
    c = s["cost"]
    b = "<$1" if c < 1 else "$1-5" if c < 5 else "$5-20" if c < 20 else "$20-50" if c < 50 else ">$50"
    cost_bins[b] += c

# cost per call vs context size  (main only)
ctx_cost = defaultdict(lambda: [0, 0.0])
for r in calls:
    if r["sub"]: continue
    k = tok(r["u"]); c = k["inp"] + k["cr"] + k["cw"]
    b = "<50k" if c < 50e3 else "50-100k" if c < 100e3 else "100-200k" if c < 200e3 else "200-400k" if c < 400e3 else "400k-1M"
    ctx_cost[b][0] += 1; ctx_cost[b][1] += r["cost"]

def C(c): return {k: (round(v, 2) if isinstance(v, float) else v) for k, v in c.items()}
out = dict(
    since=SINCE.isoformat(), now=NOW.isoformat(), files=len(files), total=C(tot),
    daily={k: C(v) for k, v in sorted(daily.items())},
    models={k: C(v) for k, v in models.items()},
    main_sub={k: C(v) for k, v in main_sub.items()},
    sub_models={k: C(v) for k, v in sub_models.items()},
    projects={k: C(v) for k, v in sorted(projects.items(), key=lambda kv: -kv[1]["cost"])[:25]},
    efforts={k: C(v) for k, v in efforts.items()},
    hours={k: C(v) for k, v in sorted(hours.items())},
    weekday={k: C(v) for k, v in weekday.items()},
    entry={k: C(v) for k, v in entry.items()}, speed={k: C(v) for k, v in speed.items()},
    sessions_n=len(sessions), top_sessions=sessions[:40],
    session_cost_bins=C(cost_bins),
    ctx_hist=dict(ctx_hist), ctx_cost={k: [v[0], round(v[1], 2)] for k, v in ctx_cost.items()},
    baseline=dict(n=len(baseline), median=sorted(baseline)[len(baseline)//2] if baseline else 0,
                  p90=sorted(baseline)[int(len(baseline)*.9)] if baseline else 0,
                  min=min(baseline) if baseline else 0, max=max(baseline) if baseline else 0),
    cache_miss=dict(events=cache_miss_events, extra_cost=round(cache_miss_cost, 2), after_idle_1h=idle_rewrites),
    compactions=compactions,
    tools=tool_uses.most_common(60),
    tool_result_kchars={k: [tool_result_count[k], round(v/1000)] for k, v in tool_result_chars.most_common(40)},
    skills=skills.most_common(40),
    agents=Counter((a[0], a[1]) for a in agent_spawns).most_common(30),
    agents_n=len(agent_spawns),
    big_results=sorted(big_results, reverse=True)[:30],
    prompts_n=len(user_prompts),
)
json.dump(out, open(sys.argv[1], "w"), indent=1, default=str)
print("ok", len(calls), "calls", round(tot["cost"], 2), "$")
