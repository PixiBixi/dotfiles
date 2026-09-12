#!/usr/bin/env python3
"""Check which dashboards actually read a Grafana datasource.

The counterpart of grafana_metric_usage.py, for the question you must answer
before deleting a datasource or migrating it to another stack: "is anything
actually reading this?".

The whole point is the direct / variable-only split. A dashboard carrying a
`type: datasource` template variable lists **every** datasource of that type,
so the uid appears in hundreds of dashboards nobody ever pointed at it. Measured
on a real instance: one Prometheus datasource showed up in 304 dashboards and
had exactly 1 real consumer. Grepping the uid answers 304 and gets the decision
wrong.

References are collected in all three shapes Grafana emits (the string
"${ds}", the object {"uid": ...}, and a plain datasource name) at the four
sites that carry one: panel, panel target, template variable, annotation.

Dashboards are cached on disk, shared with grafana_metric_usage.py, so repeated
runs only fetch what changed.

Examples:
    # who really reads this datasource?
    ./grafana_datasource_usage.py -d wfWf8AG4k -v

    # by name, several at once, machine readable
    ./grafana_datasource_usage.py -d 'Thanos' -d 'Thanos Dev' --json

    # CI gate before a terraform destroy: exit 1 while something still reads it
    ./grafana_datasource_usage.py -d wfWf8AG4k --quiet || echo "still in use"

    # include the selector-only hits in the count (off by default)
    ./grafana_datasource_usage.py -d wfWf8AG4k --count-variable-only

Environment:
    GRAFANA_URL    base URL, e.g. https://grafana.example.com
    GRAFANA_TOKEN  API token with dashboard read access. GRAFANA_SERVICE_ACCOUNT_TOKEN,
                   GTOK and the grafana MCP server in ~/.claude.json are also read,
                   in that order, same as the charting-grafana-metrics skill.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

sys.path.insert(0, str(Path(__file__).resolve().parent))

# Imported rather than duplicated: same skill directory, so the two tools ship
# together. The token chain, the HTTP client and the on-disk cache are the
# pieces that must not drift between them.
from grafana_metric_usage import (  # noqa: E402
    DEFAULT_CACHE,
    DEFAULT_MAX_AGE,
    DEFAULT_WORKERS,
    Cache,
    Client,
    Stats,
    fetch_dashboards,
    list_dashboards,
    GrafanaError,
    resolve_datasources,
    resolve_token,
)


def datasource_types(client: Client) -> dict[str, str]:
    """Map datasource uid to plugin type.

    Needed to decide what a `type: datasource` variable reaches: it selects by
    plugin type and never names a uid, so without this the selector count is
    wrong by two orders of magnitude.

    Args:
        client: An initialised Grafana client.

    Returns:
        A uid to type mapping. Empty when the token cannot list datasources.
    """
    try:
        items = client.get_json("/api/datasources") or []
    except GrafanaError:
        return {}
    return {item["uid"]: str(item.get("type", "")) for item in items if "uid" in item}

# Where a datasource reference can sit, and what each site means for the
# verdict. A variable's `current`/`options` is the selector trap: it records
# whatever was selected when the dashboard was last saved, which is not a
# dependency, so it never counts as direct.
SITE_PANEL = "panel"
SITE_TARGET = "target"
SITE_VARIABLE_QUERY = "variable-query"
SITE_ANNOTATION = "annotation"
SITE_SELECTOR = "variable-selector"

DIRECT_SITES = frozenset({SITE_PANEL, SITE_TARGET, SITE_VARIABLE_QUERY, SITE_ANNOTATION})


@dataclass(slots=True)
class Ref:
    """One dashboard that references a datasource, with every site it uses."""

    uid: str
    title: str
    folder: str
    sites: set[str]

    @property
    def direct(self) -> bool:
        """True when the dashboard really reads the datasource.

        A dashboard whose only reference is the variable selector merely offers
        the datasource in a dropdown, alongside every other one of the same
        type. Deleting the datasource costs it nothing.
        """
        return bool(self.sites & DIRECT_SITES)

    def location(self, base_url: str) -> str:
        """Return a clickable URL for the dashboard."""
        return f"{base_url}/d/{self.uid}"


def datasource_refs(node: Any) -> Iterator[str]:
    """Yield every datasource reference carried by a node, in either shape.

    Args:
        node: A decoded JSON value.

    Yields:
        The uid, variable reference or datasource name, as written.
    """
    ds = node.get("datasource") if isinstance(node, dict) else None
    if isinstance(ds, str):
        yield ds
    elif isinstance(ds, dict) and isinstance(ds.get("uid"), str):
        yield ds["uid"]


def _matches(ref: str, wanted: str, aliases: set[str], ds_vars: dict[str, set[str]]) -> bool:
    """Decide whether a raw reference designates the wanted datasource.

    Args:
        ref: The reference as written in the JSON.
        wanted: The uid being searched for.
        aliases: Other spellings of the same datasource, typically its name.
        ds_vars: Template variable name to the uids that variable can resolve to.

    Returns:
        True when this reference points at the wanted datasource.
    """
    ref = ref.strip()
    if ref.startswith("$"):
        # "${ds}" resolves to whatever the variable can select. Handled by the
        # caller as a selector hit, never as a direct one, so the variable's
        # own reach is what matters here.
        return wanted in ds_vars.get(ref.lstrip("$").strip("{}"), set())
    return ref == wanted or ref in aliases


def variable_reach(
    payload: dict[str, Any], wanted: str, aliases: set[str], ds_type: str = ""
) -> dict[str, set[str]]:
    """Map each datasource variable to the uids it can select.

    A `type: datasource` variable selects by plugin type, so it reaches every
    datasource of that type. That is exactly why a uid appears in hundreds of
    dashboards, and why those hits are not consumers.

    Args:
        payload: The dashboard JSON.
        wanted: The uid being searched for.
        aliases: Other spellings of the same datasource.
        ds_type: Plugin type of the wanted datasource, e.g. "prometheus".

    Returns:
        Variable name to the set of uids it covers, restricted to `wanted`.
    """
    reach: dict[str, set[str]] = {}
    for var in (payload.get("templating") or {}).get("list") or []:
        if not isinstance(var, dict) or var.get("type") != "datasource":
            continue
        name = var.get("name")
        if not isinstance(name, str):
            continue
        # A datasource variable selects by plugin type and never names a uid,
        # so a type match is what makes it reach this datasource. `current` is
        # only the value saved last time, which is why it is not the criterion.
        query = var.get("query")
        by_type = bool(ds_type) and isinstance(query, str) and query.strip() == ds_type
        blob = json.dumps([var.get("current"), var.get("options"), query])
        if by_type or wanted in blob or any(a in blob for a in aliases):
            reach.setdefault(name, set()).add(wanted)
    return reach


def scan_dashboard(
    row: dict[str, Any], payload: dict[str, Any], wanted: str, aliases: set[str], ds_type: str = ""
) -> Ref | None:
    """Find every site in one dashboard that references the datasource.

    Args:
        row: The search index row, carrying uid, title and folder.
        payload: The dashboard payload as returned by the API.
        wanted: The uid being searched for.
        aliases: Other spellings of the same datasource.
        ds_type: Plugin type of the wanted datasource.

    Returns:
        A Ref when the dashboard references the datasource, else None.
    """
    dash = payload.get("dashboard") or payload
    ds_vars = variable_reach(dash, wanted, aliases, ds_type)
    sites: set[str] = set()

    def note(ref: str, site: str) -> None:
        if ref.strip().startswith("$"):
            if _matches(ref, wanted, aliases, ds_vars):
                sites.add(SITE_SELECTOR)
        elif _matches(ref, wanted, aliases, ds_vars):
            sites.add(site)

    def walk_panels(panels: Any) -> None:
        if not isinstance(panels, list):
            return
        for panel in panels:
            if not isinstance(panel, dict):
                continue
            for ref in datasource_refs(panel):
                note(ref, SITE_PANEL)
            for target in panel.get("targets") or []:
                if isinstance(target, dict):
                    for ref in datasource_refs(target):
                        note(ref, SITE_TARGET)
            # Rows hold their own panels when collapsed, which a flat sweep of
            # $.panels[*] silently skips.
            walk_panels(panel.get("panels"))

    walk_panels(dash.get("panels"))

    for var in (dash.get("templating") or {}).get("list") or []:
        if isinstance(var, dict):
            for ref in datasource_refs(var):
                note(ref, SITE_VARIABLE_QUERY)
    for ann in (dash.get("annotations") or {}).get("list") or []:
        if isinstance(ann, dict):
            for ref in datasource_refs(ann):
                note(ref, SITE_ANNOTATION)

    if not sites:
        return None
    return Ref(
        uid=row.get("uid", dash.get("uid", "")),
        title=row.get("title", dash.get("title", "")),
        folder=row.get("folderTitle", "General"),
        sites=sites,
    )


def report(
    wanted: list[str],
    found: dict[str, list[Ref]],
    names: dict[str, str],
    stats: Stats,
    base_url: str,
    verbose: bool,
    count_selectors: bool,
) -> int:
    """Print the human-readable report.

    Args:
        wanted: Datasource uids searched for, in input order.
        found: uid to the dashboards referencing it.
        names: uid to datasource name.
        stats: Fetch counters.
        base_url: Grafana base URL, for building links.
        verbose: When true, list every dashboard instead of a count.
        count_selectors: When true, selector-only hits count as usage.

    Returns:
        Number of datasources still in use.
    """
    width = min(max((len(names.get(u, u)) for u in wanted), default=12), 48)
    print(f"\n{'datasource':{width}}  {'direct':>6}  {'selector':>8}  verdict")
    print("-" * (width + 30))
    in_use = 0
    for uid in wanted:
        refs = found.get(uid, [])
        direct = [r for r in refs if r.direct]
        selector = len(refs) - len(direct)
        used = bool(direct) or (count_selectors and selector)
        in_use += bool(used)
        label = names.get(uid, uid)
        print(f"{label:{width}}  {len(direct):>6}  {selector:>8}  {'IN USE' if used else 'UNUSED'}")

    if verbose:
        for uid in wanted:
            direct = [r for r in found.get(uid, []) if r.direct]
            if not direct:
                continue
            print(f"\n{names.get(uid, uid)} ({uid}) is read by:")
            for ref in sorted(direct, key=lambda r: r.title.lower()):
                print(f"  {ref.title}  [{ref.folder}]")
                print(f"    {ref.location(base_url)}")
                print(f"    at {','.join(sorted(ref.sites & DIRECT_SITES))}")

    print(
        f"\n{len(wanted)} datasource(s): {len(wanted) - in_use} unused, {in_use} in use"
        f"  |  {stats.total} dashboards ({stats.from_cache} cached, {stats.fetched} fetched)"
    )
    if not count_selectors:
        print("selector-only hits are not usage: a datasource variable lists every "
              "datasource of its type. Pass --count-variable-only to include them.")
    for failure in stats.failed:
        print(f"  fetch error: {failure}", file=sys.stderr)
    return in_use


def build_parser() -> argparse.ArgumentParser:
    """Return the command line parser."""
    p = argparse.ArgumentParser(
        description="Check which dashboards actually read a Grafana datasource.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("Examples:", 1)[-1],
    )
    p.add_argument("-d", "--datasource", action="append", default=[], metavar="UID_OR_NAME",
                   help="datasource uid or name, repeatable")
    p.add_argument("-v", "--verbose", action="store_true", help="list every dashboard that reads it")
    p.add_argument("--count-variable-only", action="store_true",
                   help="count selector-only hits as usage (off by default)")
    p.add_argument("--json", action="store_true", help="machine readable output")
    p.add_argument("--quiet", action="store_true", help="no report, exit code only")
    p.add_argument("--url", default=os.environ.get("GRAFANA_URL", ""))
    p.add_argument("--token", default="")
    p.add_argument("--mcp-server", default=os.environ.get("GRAFANA_MCP_SERVER", "grafana"))
    p.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    p.add_argument("--max-age", type=float, default=DEFAULT_MAX_AGE,
                   help=f"refetch entries older than this many seconds (default {DEFAULT_MAX_AGE})")
    p.add_argument("--refresh", action="store_true", help="ignore the cache entirely")
    p.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    return p


def main(argv: list[str] | None = None) -> int:
    """Run the check.

    Args:
        argv: Command line arguments, defaulting to sys.argv[1:].

    Returns:
        0 when every datasource is unused, 1 when at least one is still read.
    """
    args = build_parser().parse_args(argv)
    token = resolve_token(args.token, args.mcp_server)
    if not args.url or not token:
        raise SystemExit("no Grafana URL or token: set GRAFANA_URL and GRAFANA_TOKEN, or pass --url/--token")
    if not args.datasource:
        raise SystemExit("nothing to check: pass at least one -d/--datasource")

    client = Client(args.url, token)
    names: dict[str, str] = {str(k): str(v) for k, v in resolve_datasources(client).items()}
    by_name: dict[str, str] = {v: k for k, v in names.items()}
    types = datasource_types(client)

    # Accept a uid or a name, and keep the other spelling as an alias: a target
    # may reference a datasource by name where the panel references it by uid.
    wanted: list[str] = []
    aliases: dict[str, set[str]] = {}
    for given in args.datasource:
        uid: str = given if given in names else by_name.get(given, given)
        wanted.append(uid)
        alias = {names[uid]} if uid in names else set()
        if given != uid:
            alias.add(given)
        aliases[uid] = alias

    cache = Cache(args.cache_dir, args.max_age, args.refresh)
    stats = Stats()
    started = time.monotonic()
    rows = list_dashboards(client)
    cache.prune({row["uid"] for row in rows})

    found: dict[str, list[Ref]] = {uid: [] for uid in wanted}
    for row, payload in fetch_dashboards(client, rows, cache, args.workers, stats):
        for uid in wanted:
            ref = scan_dashboard(row, payload, uid, aliases[uid], types.get(uid, ""))
            if ref:
                found[uid].append(ref)
    elapsed = time.monotonic() - started

    if args.json:
        print(json.dumps({
            "elapsed": round(elapsed, 2),
            "dashboards_scanned": stats.total,
            "datasources": {
                uid: {
                    "name": names.get(uid),
                    "direct": [
                        {"uid": r.uid, "title": r.title, "folder": r.folder,
                         "sites": sorted(r.sites & DIRECT_SITES)}
                        for r in found[uid] if r.direct
                    ],
                    "selector_only": sum(1 for r in found[uid] if not r.direct),
                }
                for uid in wanted
            },
        }, indent=2))
        in_use = sum(1 for uid in wanted if any(r.direct for r in found[uid]))
    elif args.quiet:
        in_use = sum(
            1 for uid in wanted
            if any(r.direct for r in found[uid])
            or (args.count_variable_only and found[uid])
        )
    else:
        in_use = report(wanted, found, names, stats, args.url, args.verbose, args.count_variable_only)

    return 1 if in_use else 0


if __name__ == "__main__":
    sys.exit(main())
