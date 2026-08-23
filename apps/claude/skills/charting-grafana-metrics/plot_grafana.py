#!/usr/bin/env python3
"""Render a dark-themed matplotlib chart from a Grafana Prometheus datasource.

Fetches a PromQL range query through the Grafana datasource proxy (no direct
Prometheus access needed), styles it like a Grafana panel, and writes a PNG.
Optionally attaches the PNG to a Jira issue.

Auth: reads the Grafana SA token from ~/.claude.json (grafana_dynfactory MCP env)
by default; override with --token or the GTOK env var.

Run with --help for all options. See SKILL.md for usage patterns.
"""
import argparse, json, os, re, sys, time, urllib.parse, urllib.request
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

# Grafana "classic" palette: colors are assigned to series in order.
PALETTE = ["#73BF69", "#FF9830", "#5794F2", "#F2495C", "#B877D9",
           "#FADE2A", "#37872D", "#E0B400", "#1F60C4", "#8AB8FF"]


def read_token(args):
    if args.token:
        return args.token
    if os.environ.get("GTOK"):
        return os.environ["GTOK"]
    cfg = json.loads((Path.home() / ".claude.json").read_text())
    env = cfg["mcpServers"][args.mcp_server]["env"]
    return env.get("GRAFANA_SERVICE_ACCOUNT_TOKEN") or env["GRAFANA_API_KEY"]


def resolve_time(t, now):
    """Accept epoch seconds, RFC3339, or Grafana-style 'now-6h'."""
    if t == "now":
        return now
    if t.startswith("now-"):
        units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
        num, unit = t[4:-1], t[-1]
        return now - int(num) * units[unit]
    try:
        return int(float(t))
    except ValueError:
        return int(datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp())


def fetch(args, token):
    now = int(time.time())
    start, end = resolve_time(args.start, now), resolve_time(args.end, now)
    url = (f"{args.grafana_url.rstrip('/')}/api/datasources/proxy/uid/"
           f"{args.datasource_uid}/api/v1/query_range")
    q = urllib.parse.urlencode({"query": args.expr, "start": start,
                                "end": end, "step": args.step})
    req = urllib.request.Request(f"{url}?{q}",
                                 headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        payload = json.load(r)
    if payload.get("status") != "success":
        sys.exit(f"Prometheus query failed: {payload}")
    res = payload["data"]["result"]
    if not res:
        sys.exit("Query returned no series: check expr / datasource / time range.")
    return res


def series_name(metric, key, rename):
    raw = metric.get(key, metric.get("__name__", "series")) if key else \
        metric.get("__name__", ",".join(f"{k}={v}" for k, v in metric.items()))
    clean = re.sub(r":\d+$", "", raw)  # strip node_exporter-style :9100 port
    # rename may target either the raw or the port-stripped form
    return rename.get(raw) or rename.get(clean) or clean


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--datasource-uid", required=True)
    p.add_argument("--expr", required=True, help="PromQL range query")
    p.add_argument("--out", required=True, help="output PNG path")
    p.add_argument("--start", default="now-6h", help="epoch|RFC3339|now-6h (default now-6h)")
    p.add_argument("--end", default="now")
    p.add_argument("--step", type=int, default=60, help="seconds (default 60)")
    p.add_argument("--title", default="")
    p.add_argument("--ylabel", default="")
    p.add_argument("--ymin", type=float, default=None)
    p.add_argument("--ymax", type=float, default=None)
    p.add_argument("--legend-key", default="instance",
                   help="metric label used as series name (default instance)")
    p.add_argument("--rename", default="{}",
                   help='JSON map to prettify series names, e.g. \'{"raw":"Nice"}\'')
    p.add_argument("--annotate-max", default="",
                   help="annotate the global-max point with this text")
    p.add_argument("--grafana-url", default="https://grafana.dynfactory.com/")
    p.add_argument("--mcp-server", default="grafana_dynfactory")
    p.add_argument("--token", default="")
    p.add_argument("--attach-jira", default="",
                   help="Jira issue key to attach the PNG to (e.g. PE-1408)")
    args = p.parse_args()

    rename = json.loads(args.rename)
    token = read_token(args)
    result = fetch(args, token)

    plt.rcParams.update({"font.size": 11, "text.color": "#ccc",
                         "axes.labelcolor": "#ccc", "xtick.color": "#999",
                         "ytick.color": "#999"})
    fig, ax = plt.subplots(figsize=(13, 5.2), dpi=140)
    fig.patch.set_facecolor("#111217"); ax.set_facecolor("#111217")

    gmax, gmax_xy, gmax_color = float("-inf"), None, PALETTE[0]
    stats = []
    for i, r in enumerate(result):
        color = PALETTE[i % len(PALETTE)]
        xs = [datetime.fromtimestamp(float(t)) for t, _ in r["values"]]
        ys = [float(v) for _, v in r["values"]]
        name = series_name(r["metric"], args.legend_key, rename)
        mean = sum(ys) / len(ys)
        ax.plot(xs, ys, color=color, lw=1.6,
                label=f"{name}   (mean {mean:.1f}, max {max(ys):.1f})")
        ax.fill_between(xs, ys, color=color, alpha=0.08)
        stats.append((name, mean, min(ys), max(ys)))
        mi = max(range(len(ys)), key=lambda k: ys[k])
        if ys[mi] > gmax:
            gmax, gmax_xy, gmax_color = ys[mi], (xs[mi], ys[mi]), color

    if args.annotate_max and gmax_xy:
        # offset in points (down-right of the peak) so it never collides with
        # the title/legend regardless of how tall the peak is.
        ax.annotate(args.annotate_max, xy=gmax_xy,
                    xytext=(45, -35), textcoords="offset points",
                    ha="left", color="#eee", fontsize=10,
                    arrowprops=dict(arrowstyle="->", color=gmax_color, lw=1.3),
                    bbox=dict(boxstyle="round,pad=0.4", fc="#1b2a1b",
                              ec=gmax_color, alpha=0.9))

    if args.title:
        ax.set_title(args.title, color="#eee", fontsize=13, pad=12)
    if args.ylabel:
        ax.set_ylabel(args.ylabel)
    if args.ymin is not None or args.ymax is not None:
        ax.set_ylim(args.ymin, args.ymax)
    ax.grid(True, color="#2a2a2a", lw=0.6)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    ax.legend(loc="upper left", facecolor="#1b1c22", edgecolor="#333", labelcolor="#ddd")
    for s in ax.spines.values():
        s.set_color("#333")
    fig.tight_layout()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, facecolor=fig.get_facecolor())
    print(f"saved {args.out}  ({len(result)} series)")
    for name, mean, lo, hi in stats:
        print(f"  {name}: mean {mean:.2f}  min {lo:.2f}  max {hi:.2f}")

    if args.attach_jira:
        attach_to_jira(args.attach_jira, args.out)


def attach_to_jira(key, img):
    """Attach PNG to a Jira issue. Needs JIRA_API_TOKEN + JIRA_EMAIL in env."""
    import subprocess
    email = os.environ.get("JIRA_EMAIL", "jdelgado@equativ.com")
    tok = os.environ["JIRA_API_TOKEN"]
    base = os.environ.get("JIRA_BASE", "https://equativ.atlassian.net")
    out = subprocess.run(
        ["curl", "-s", "-u", f"{email}:{tok}", "-X", "POST",
         f"{base}/rest/api/3/issue/{key}/attachments",
         "-H", "X-Atlassian-Token: no-check",
         "-F", f"file=@{img};type=image/png;filename={Path(img).name}"],
        capture_output=True, text=True)
    try:
        data = json.loads(out.stdout)
        print(f"attached to {key}: {data[0]['filename']} ({data[0]['size']} bytes)")
    except Exception:
        print(f"jira attach failed: {out.stdout[:300]}")


if __name__ == "__main__":
    main()
