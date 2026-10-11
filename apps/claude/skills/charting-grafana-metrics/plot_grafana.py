#!/usr/bin/env python3
"""Render a dark-themed matplotlib chart from a Grafana Prometheus datasource.

Fetches a PromQL range query through the Grafana datasource proxy (no direct
Prometheus access needed), styles it like a Grafana panel, and writes a PNG.
Optionally attaches the PNG to a Jira issue.

Auth (see resolve_target): --grafana-url picks the gcx context whose server has
that host, default gcx's current context; --gcx-context / $GCX_CONTEXT forces one.
$GRAFANA_TOKEN (then $GRAFANA_SERVICE_ACCOUNT_TOKEN, $GTOK) is used only for the
host of $GRAFANA_URL, or when gcx is missing. Same chain as the grafana-dashboards
skill's tools.

--attach-jira additionally needs JIRA_API_TOKEN, JIRA_EMAIL and JIRA_BASE. Nothing is
hardcoded on purpose: this repo is public, so no host and no address belong in the source.

Run with --help for all options. See SKILL.md for usage patterns.
"""
import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

# Grafana "classic" palette: colors are assigned to series in order.
PALETTE = ["#73BF69", "#FF9830", "#5794F2", "#F2495C", "#B877D9",
           "#FADE2A", "#37872D", "#E0B400", "#1F60C4", "#8AB8FF"]


STATIC_TOKEN_VARS = ("GRAFANA_TOKEN", "GRAFANA_SERVICE_ACCOUNT_TOKEN", "GTOK")


def env_token():
    """Return the first static token set in the environment, or ""."""
    for name in STATIC_TOKEN_VARS:
        if os.environ.get(name):
            return os.environ[name]
    return ""


def url_host(url):
    """Lowercased host[:port] of a URL, tolerating a missing scheme."""
    return urllib.parse.urlparse(url if "://" in url else f"https://{url}").netloc.lower()


def gcx_context(explicit=""):
    """Resolve the gcx context to use for the gcx-api fallback.

    Order: --gcx-context, $GCX_CONTEXT, else "" (gcx's own current-context).
    """
    return explicit or os.environ.get("GCX_CONTEXT", "")


def gcx_context_for_url(url):
    """Name of the gcx context whose server has the host of `url`, or "".

    The current context wins when several contexts point at the same host.
    """
    try:
        proc = subprocess.run(["gcx", "config", "view", "-o", "json"], capture_output=True,
                              text=True, timeout=10, check=False, env=gcx_env())
        cfg = json.loads(proc.stdout) if proc.returncode == 0 else {}
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return ""
    host = url_host(url)
    stacks = cfg.get("stacks") or {}
    matches = [
        name for name, ctx in (cfg.get("contexts") or {}).items()
        if url_host(((stacks.get((ctx or {}).get("stack", "")) or {}).get("grafana") or {}).get("server", "")) == host
    ]
    current = cfg.get("current-context", "")
    return current if current in matches else (matches[0] if matches else "")


def resolve_target(url="", token="", context=""):
    """Pick the Grafana base URL, static token and gcx context for a run.

    Shared by the Grafana skills, deliberately duplicated so each one stands
    alone. A token from the environment belongs to $GRAFANA_URL and is never
    sent to another host: that is what answered 401 on every other instance.

    Order: --token (with --grafana-url or $GRAFANA_URL); --gcx-context / $GCX_CONTEXT;
    --grafana-url (the env token when its host is $GRAFANA_URL's, else the gcx context
    serving that host); gcx's current context; env token + $GRAFANA_URL when
    gcx is not installed.

    Args:
        url: --grafana-url as passed on the command line, "" when absent.
        token: --token as passed on the command line, "" when absent.
        context: --gcx-context as passed on the command line, "" when absent.

    Returns:
        (base_url, static_token, gcx_context). An empty token means every
        request goes through `gcx api`; base_url may then be "".
    """
    env_url = os.environ.get("GRAFANA_URL", "")
    if token:
        if not (url or env_url):
            sys.exit("no Grafana URL: pass --grafana-url or set GRAFANA_URL (required with --token)")
        return url or env_url, token, ""
    have_gcx = shutil.which("gcx") is not None
    ctx = gcx_context(context)
    if ctx:
        if not have_gcx:
            sys.exit(f"gcx context {ctx!r} requested but gcx is not on PATH (brew install gcx)")
        ctx_url = gcx_default_url(ctx)
        # An exported $GCX_CONTEXT must not silently win over an explicit --grafana-url.
        if url and ctx_url and url_host(url) != url_host(ctx_url):
            sys.exit(f"--grafana-url {url_host(url)} is not the host of gcx context {ctx!r} "
                     f"({url_host(ctx_url)}): drop one of them (unset GCX_CONTEXT?)")
        return url or ctx_url, "", ctx
    static = env_token()
    if url:
        if static and env_url and url_host(url) == url_host(env_url):
            return url, static, ""
        ctx = gcx_context_for_url(url) if have_gcx else ""
        if ctx:
            return url, "", ctx
        sys.exit(
            f"no credentials for {url_host(url)}: no gcx context points at it "
            f"(see `gcx config list-contexts`).\n"
            f"Run `gcx login <name> --server {url.rstrip('/')}`, or pass --token."
        )
    if have_gcx:
        return gcx_default_url(""), "", ""
    if static and env_url:
        return env_url, static, ""
    sys.exit(
        "no Grafana credentials: gcx is not on PATH and GRAFANA_TOKEN/GRAFANA_URL are unset.\n"
        "Install gcx (brew install gcx) and run `gcx login`."
    )


def gcx_env():
    """Environment for gcx without the static-token variables.

    gcx treats GRAFANA_TOKEN and friends as an auth override, which silently
    replaces the context's OAuth login and answers 401.
    """
    return {k: v for k, v in os.environ.items()
            if k not in ("GRAFANA_TOKEN", "GRAFANA_SERVICE_ACCOUNT_TOKEN", "GRAFANA_URL")}


def gcx_api_json(path, params, context, timeout=60):
    """GET a Grafana API path through `gcx api`, so OAuth refresh stays gcx's job.

    Used when no static token is configured: gcx resolves auth (OAuth or a
    static token, per its own context) instead of this script reading or
    caching a credential itself.
    """
    url = f"{path}?{urllib.parse.urlencode(params)}" if params else path
    cmd = ["gcx", "api", url, "-o", "json"]
    if context:
        cmd += ["--context", context]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False, env=gcx_env())
    except subprocess.TimeoutExpired:
        sys.exit(f"gcx api timed out after {timeout:.0f}s")
    if proc.returncode != 0:
        try:
            summary = json.loads(proc.stdout)["error"]["summary"]
        except (json.JSONDecodeError, KeyError, TypeError):
            summary = (proc.stdout or proc.stderr or "").strip()[:300]
        sys.exit(f"gcx api failed: {summary}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        sys.exit(f"gcx api: unparseable response: {exc}")


def gcx_default_url(context=""):
    """Ask gcx for the current context's Grafana base URL, best effort.

    Used only when --grafana-url/$GRAFANA_URL is unset and gcx is doing the
    auth, so the URL still comes from gcx's own config, never a hardcoded
    default (this repo is public: no host belongs in the source).
    """
    cmd = [
        "gcx", "config", "view", "--minify", "--jq",
        ".stacks | to_entries[0].value.grafana.server", "-o", "json",
    ]
    if context:
        cmd += ["--context", context]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=False, env=gcx_env())
        if proc.returncode == 0:
            return json.loads(proc.stdout) or ""
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return ""


UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 7 * 86400, "y": 365 * 86400}
DURATION = re.compile(r"(?:\d+[smhdwy])+")


def resolve_time(t, now):
    """Accept epoch seconds, RFC3339 (naive means UTC), or Grafana-style 'now-6h', 'now-1h30m', 'now-1w'."""
    if t == "now":
        return now
    if t.startswith("now-"):
        if not DURATION.fullmatch(t[4:]):
            sys.exit(f"bad relative time {t!r}: use now-<n><s|m|h|d|w|y>, e.g. now-6h, now-1h30m")
        return now - sum(int(n) * UNITS[u] for n, u in re.findall(r"(\d+)([smhdwy])", t[4:]))
    try:
        return int(float(t))
    except ValueError:
        pass
    try:
        parsed = datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        sys.exit(f"bad time {t!r}: use epoch seconds, RFC3339 or now-<duration>")
    # A naive timestamp is read as UTC, so the chart does not depend on the laptop's timezone.
    return int((parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp())


def fetch(args, token, gcx_ctx):
    now = int(time.time())
    start, end = resolve_time(args.start, now), resolve_time(args.end, now)
    path = f"/api/datasources/proxy/uid/{args.datasource_uid}/api/v1/query_range"
    params = {"query": args.expr, "start": start, "end": end, "step": args.step}
    if token:
        url = f"{args.grafana_url.rstrip('/')}{path}"
        q = urllib.parse.urlencode(params)
        req = urllib.request.Request(f"{url}?{q}",
                                     headers={"Authorization": f"Bearer {token}"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                payload = json.load(r)
        except urllib.error.HTTPError as exc:
            # The body carries Prometheus' own error, e.g. the PromQL parse error.
            sys.exit(f"Prometheus query failed: HTTP {exc.code}: {exc.read().decode(errors='replace')[:500]}")
        except (urllib.error.URLError, TimeoutError) as exc:
            sys.exit(f"Grafana unreachable at {args.grafana_url}: {exc}")
    else:
        payload = gcx_api_json(path, params, gcx_ctx)
    if not payload or payload.get("status") != "success":
        sys.exit(f"Prometheus query failed: {payload}")
    res = payload["data"]["result"]
    if not res:
        sys.exit("Query returned no series: check expr / datasource / time range.")
    return res


def series_name(metric, key, rename):
    # Fallback is every label, sorted: `sum by (pod)` has neither `instance` nor `__name__`,
    # and a constant fallback would name every line "series".
    labels = ",".join(f"{k}={v}" for k, v in sorted(metric.items()))
    raw = metric.get(key) or metric.get("__name__") or labels or "series"
    clean = re.sub(r":\d+$", "", raw)  # strip node_exporter-style :9100 port
    # rename may target either the raw or the port-stripped form
    return rename.get(raw) or rename.get(clean) or clean


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--datasource-uid", required=True)
    p.add_argument("--expr", required=True, help="PromQL range query")
    p.add_argument("--out", required=True, help="output PNG path")
    p.add_argument("--start", default="now-6h", help="epoch|RFC3339 (naive = UTC)|now-6h|now-1h30m|now-1w (default now-6h)")
    p.add_argument("--end", default="now")
    p.add_argument("--step", type=int, default=60, help="seconds (default 60)")
    p.add_argument("--title", default="")
    p.add_argument("--ylabel", default="")
    p.add_argument("--ymin", type=float, default=None)
    p.add_argument("--ymax", type=float, default=None)
    p.add_argument("--legend-key", default="instance",
                   help="metric label used as series name (default instance); "
                        "when absent, __name__, then all labels")
    p.add_argument("--rename", default="{}",
                   help='JSON map to prettify series names, e.g. \'{"raw":"Nice"}\'')
    p.add_argument("--annotate-max", default="",
                   help="annotate the global-max point with this text")
    p.add_argument("--grafana-url", default="",
                   help="Grafana base URL; picks the matching gcx context "
                        "(default: gcx current context)")
    p.add_argument("--gcx-context", default="",
                   help="gcx context for the gcx-api fallback (default: $GCX_CONTEXT, "
                        "else gcx's current-context)")
    p.add_argument("--token", default="")
    p.add_argument("--attach-jira", default="",
                   help="Jira issue key to attach the PNG to (e.g. ABC-123)")
    args = p.parse_args()

    rename = json.loads(args.rename)
    args.grafana_url, token, gcx_ctx = resolve_target(args.grafana_url, args.token, args.gcx_context)
    result = fetch(args, token, gcx_ctx)

    plt.rcParams.update({"font.size": 11, "text.color": "#ccc",
                         "axes.labelcolor": "#ccc", "xtick.color": "#999",
                         "ytick.color": "#999"})
    fig, ax = plt.subplots(figsize=(13, 5.2), dpi=140)
    fig.patch.set_facecolor("#111217")
    ax.set_facecolor("#111217")

    gmax, gmax_xy, gmax_color = float("-inf"), None, PALETTE[0]
    stats = []
    for i, r in enumerate(result):
        color = PALETTE[i % len(PALETTE)]
        # UTC, like the dashboards (lint enforces timezone utc): a chart must read the same on any laptop.
        xs = [datetime.fromtimestamp(float(t), tz=timezone.utc) for t, _ in r["values"]]
        ys = [float(v) for _, v in r["values"]]
        name = series_name(r["metric"], args.legend_key, rename)
        # Prometheus returns "NaN"/"+Inf" for a division by zero: plot them as gaps, keep them out of the stats.
        finite = [k for k, y in enumerate(ys) if math.isfinite(y)]
        if not finite:
            print(f"  {name}: no finite sample, skipped", file=sys.stderr)
            continue
        fys = [ys[k] for k in finite]
        mean = sum(fys) / len(fys)
        ys = [y if math.isfinite(y) else float("nan") for y in ys]
        ax.plot(xs, ys, color=color, lw=1.6,
                label=f"{name}   (mean {mean:.1f}, max {max(fys):.1f})")
        ax.fill_between(xs, ys, color=color, alpha=0.08)
        stats.append((name, mean, min(fys), max(fys)))
        mi = max(finite, key=lambda k: ys[k])
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
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M", tz=timezone.utc))
    ax.set_xlabel("UTC", color="#999")
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
    """Attach PNG to a Jira issue.

    Needs JIRA_API_TOKEN, JIRA_EMAIL and JIRA_BASE in the environment. No default:
    an email address and a Jira host are org-identifying, and this repo is public.
    """
    try:
        email = os.environ["JIRA_EMAIL"]
        tok = os.environ["JIRA_API_TOKEN"]
        base = os.environ["JIRA_BASE"].rstrip("/")
    except KeyError as e:
        sys.exit(f"--attach-jira needs {e.args[0]} in the environment")
    # Credentials go through a curl config on stdin: on argv they would show in `ps`.
    cred = f"{email}:{tok}".replace("\\", "\\\\").replace('"', '\\"')
    out = subprocess.run(
        ["curl", "-sS", "--fail-with-body", "-K", "-", "-X", "POST",
         f"{base}/rest/api/3/issue/{key}/attachments",
         "-H", "X-Atlassian-Token: no-check",
         "-F", f"file=@{img};type=image/png;filename={Path(img).name}"],
        input=f'user = "{cred}"\n', capture_output=True, text=True)
    try:
        data = json.loads(out.stdout)
        print(f"attached to {key}: {data[0]['filename']} ({data[0]['size']} bytes)")
    except Exception:
        sys.exit(f"jira attach failed (curl exit {out.returncode}): "
                 f"{(out.stdout or out.stderr)[:300]}")


if __name__ == "__main__":
    main()
