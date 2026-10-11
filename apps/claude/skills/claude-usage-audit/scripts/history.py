#!/usr/bin/env python3
"""Prompt-level activity from ~/.claude/history.jsonl (kept beyond the 30-day
transcript cleanup) joined with weekly cost from the transcripts. Output: JSON."""
import json, os, sys, glob
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta

DAYS = int(os.environ.get("AUDIT_DAYS", "90"))
NOW = datetime.now(timezone.utc)
SINCE = NOW - timedelta(days=DAYS)
HOME = os.path.expanduser("~")
PRICES = {"claude-opus-5-5": (4, 20, .2), "claude-opus-5": (5, 25, .5), "claude-opus-4-8": (5, 25, .5),
          "claude-opus-4-7": (5, 25, .5), "claude-sonnet-5-5": (2, 10, .2), "claude-sonnet-5": (2, 10, .2),
          "claude-sonnet-4-6": (3, 15, .3), "claude-haiku-4-5": (1, 5, .1)}

def price(m):
    for k in sorted(PRICES, key=len, reverse=True):
        if m and m.startswith(k): return PRICES[k]
    return (0, 0, 0)

def week(t):
    y, w, _ = t.isocalendar()
    monday = (t - timedelta(days=t.weekday())).strftime("%Y-%m-%d")
    return monday

def short_proj(p):
    p = (p or "?").replace(HOME, "~")
    for a, b in (("~/Documents/work/git/smartadserver/", "work/"), ("~/Documents/perso/git/", "perso/")):
        p = p.replace(a, b)
    return p

# ---- prompts ----
prompts = []
for line in open(f"{HOME}/.claude/history.jsonl", errors="replace"):
    try: d = json.loads(line)
    except Exception: continue
    t = datetime.fromtimestamp(d.get("timestamp", 0) / 1000, timezone.utc)
    if t < SINCE: continue
    pasted = sum(len(str(v.get("content", ""))) for v in (d.get("pastedContents") or {}).values() if isinstance(v, dict))
    prompts.append(dict(t=t.astimezone(), text=d.get("display", ""), proj=short_proj(d.get("project")), sess=d.get("sessionId"), pasted=pasted))

wk_prompts, wk_sessions = Counter(), defaultdict(set)
slash = Counter()
by_proj = Counter()
per_sess = Counter()
heat = Counter()
late = weekend = 0
paste_big = 0
for p in prompts:
    w = week(p["t"]); wk_prompts[w] += 1; wk_sessions[w].add(p["sess"])
    tx = p["text"].strip()
    if tx.startswith("/"):
        slash[tx.split()[0]] += 1
    by_proj[p["proj"]] += 1
    per_sess[p["sess"]] += 1
    heat[(p["t"].weekday(), p["t"].hour)] += 1
    if p["t"].hour >= 22 or p["t"].hour < 6: late += 1
    if p["t"].weekday() >= 5: weekend += 1
    if p["pasted"] > 5000: paste_big += 1

sess_bins = Counter()
for s, n in per_sess.items():
    sess_bins["1-5" if n <= 5 else "6-20" if n <= 20 else "21-50" if n <= 50 else "51-100" if n <= 100 else ">100"] += 1

# ---- weekly cost from transcripts ----
seen = set()
wk_cost, wk_model, wk_ctx = Counter(), defaultdict(Counter), defaultdict(list)
first_tx = None
for f in glob.glob(f"{HOME}/.claude/projects/**/*.jsonl", recursive=True):
    if os.path.getmtime(f) < SINCE.timestamp(): continue
    sub = "/subagents/" in f
    for line in open(f, errors="replace"):
        if '"assistant"' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        if d.get("type") != "assistant": continue
        m = d.get("message") or {}; u = m.get("usage"); key = (m.get("id"), d.get("requestId"))
        if not u or key in seen or m.get("model") in (None, "<synthetic>"): continue
        seen.add(key)
        t = datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00"))
        if t < SINCE: continue
        first_tx = min(first_tx or t, t)
        i, o, cr = price(m["model"])
        cc = u.get("cache_creation") or {}
        w1 = cc.get("ephemeral_1h_input_tokens", 0) or 0
        w5 = (u.get("cache_creation_input_tokens", 0) or 0) - w1
        c = (u.get("input_tokens", 0) * i + u.get("output_tokens", 0) * o + u.get("cache_read_input_tokens", 0) * cr + w5 * i * 1.25 + w1 * i * 2) / 1e6
        w = week(t.astimezone())
        wk_cost[w] += c
        wk_model[w][m["model"].replace("-20251001", "")] += c
        if not sub:
            wk_ctx[w].append(u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0))

weeks = sorted(set(wk_prompts) | set(wk_cost))
weekly = []
for w in weeks:
    ctx = sorted(wk_ctx.get(w, []))
    weekly.append(dict(week=w, prompts=wk_prompts.get(w, 0), sessions=len(wk_sessions.get(w, ())),
                       cost=round(wk_cost.get(w, 0), 2) if w in wk_cost else None,
                       cost_per_prompt=round(wk_cost[w] / wk_prompts[w], 3) if w in wk_cost and wk_prompts.get(w) else None,
                       median_ctx_k=round(ctx[len(ctx) // 2] / 1000) if ctx else None,
                       models={k: round(v, 2) for k, v in wk_model.get(w, {}).items()}))

out = dict(
    since=SINCE.isoformat(), transcripts_from=first_tx.isoformat() if first_tx else None,
    prompts=len(prompts), sessions=len(per_sess), late_share=round(late / max(1, len(prompts)), 3),
    weekend_share=round(weekend / max(1, len(prompts)), 3), big_pastes=paste_big,
    weekly=weekly, slash=slash.most_common(25), projects=by_proj.most_common(15),
    session_prompt_bins=dict(sess_bins),
    heat=[dict(dow=k[0], hour=k[1], prompts=v) for k, v in sorted(heat.items())],
)
json.dump(out, open(sys.argv[1], "w"), indent=1, default=str)
print(json.dumps({k: v for k, v in out.items() if k not in ("heat", "weekly")}, indent=1, default=str))
for w in weekly: print(w)
