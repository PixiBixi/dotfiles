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

Library panels are scanned too, and a panel with no datasource at all counts
as reading the instance default datasource.

Dashboards are cached on disk for --max-age (1h), shared with
grafana_metric_usage.py.

Exit codes: 0 every datasource unused, 1 at least one still read, 2 the scan is
incomplete, a -d is unknown, or the tool could not run. Never read 2 as UNUSED.

Examples:
    # who really reads this datasource?
    ./grafana_datasource_usage.py -d wfWf8AG4k -v

    # by name, several at once, machine readable
    ./grafana_datasource_usage.py -d 'Thanos' -d 'Thanos Dev' --json

    # CI gate before a terraform destroy: exit 1 while something still reads it
    ./grafana_datasource_usage.py -d wfWf8AG4k --quiet || echo "still in use"

    # include the selector-only hits in the count (off by default)
    ./grafana_datasource_usage.py -d wfWf8AG4k --count-variable-only

Auth: same as grafana_metric_usage.resolve_target. --url picks the gcx context
serving that host, default gcx's current context; GRAFANA_TOKEN is used only
for the host of $GRAFANA_URL.
"""

from __future__ import annotations

import argparse
import json
import re
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
    EXIT_INCOMPLETE,
    Client,
    GrafanaError,
    Stats,
    die,
    fetch_dashboards,
    library_panel_payload,
    list_dashboards,
    list_library_panels,
    open_cache,
    report_failures,
    resolve_target,
)


@dataclass(slots=True)
class Datasources:
    """The instance's datasources, as /api/datasources lists them."""

    names: dict[str, str]  # uid to name
    types: dict[str, str]  # uid to plugin type
    default: str  # uid of the instance default, "" if none

    @classmethod
    def fetch(cls, client: Client) -> Datasources:
        """List the datasources, or die: without the list no -d can be resolved or checked.

        Needed to decide what a `type: datasource` variable reaches: it selects by
        plugin type and never names a uid, so without the types the selector count
        is wrong by two orders of magnitude.
        """
        try:
            items = client.get_json("/api/datasources") or []
        except GrafanaError as exc:
            die(f"cannot list datasources, so -d cannot be resolved: {exc}")
        items = [i for i in items if isinstance(i, dict) and "uid" in i]
        return cls(
            names={str(i["uid"]): str(i.get("name", "")) for i in items},
            types={str(i["uid"]): str(i.get("type", "")) for i in items},
            default=next((str(i["uid"]) for i in items if i.get("isDefault")), ""),
        )

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

# `$ds`, `${ds}`, `${ds:raw}` and the deprecated `[[ds]]`, all naming variable `ds`.
VARIABLE_REF = re.compile(r"\$([A-Za-z_]\w*)|\$\{([A-Za-z_]\w*)(?::[^}]*)?\}|\[\[([A-Za-z_]\w*)(?::[^\]]*)?\]\]")

# Panel types that carry no query, so a missing datasource is not an implicit default.
CHROME_PANELS = frozenset({"row", "text", "dashlist", "news", "welcome"})


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

    kind: str = "dashboard"

    def location(self, base_url: str) -> str:
        """Return a clickable URL for the dashboard or library panel."""
        if self.kind == "library-panel":
            return f"{base_url}/library-panels?uid={self.uid}"
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
    name = variable_name(ref)
    if name is not None:
        # "${ds}" resolves to whatever the variable can select. Handled by the
        # caller as a selector hit, never as a direct one, so the variable's
        # own reach is what matters here.
        return wanted in ds_vars.get(name, set())
    return ref == wanted or ref in aliases


def variable_name(ref: str) -> str | None:
    """Return the variable a reference names (`$ds`, `${ds}`, `${ds:raw}`, `[[ds]]`), else None."""
    match = VARIABLE_REF.fullmatch(ref.strip())
    return next((g for g in match.groups() if g), None) if match else None


def _strings(node: Any) -> Iterator[str]:
    """Yield every string leaf of a JSON value."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for value in node.values():
            yield from _strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from _strings(value)


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
        # Whole values, not a substring of a JSON dump: uid "abc" is not in "abcdef".
        values = set(_strings([var.get("current"), var.get("options"), query]))
        if by_type or wanted in values or values & aliases:
            reach.setdefault(name, set()).add(wanted)
    return reach


def scan_dashboard(
    row: dict[str, Any],
    payload: dict[str, Any],
    wanted: str,
    aliases: set[str],
    ds_type: str = "",
    is_default: bool = False,
) -> Ref | None:
    """Find every site in one dashboard that references the datasource.

    Args:
        row: The search index row, carrying uid, title and folder.
        payload: The dashboard payload as returned by the API.
        wanted: The uid being searched for.
        aliases: Other spellings of the same datasource.
        ds_type: Plugin type of the wanted datasource.
        is_default: True when `wanted` is the instance default datasource, so
            a query panel naming no datasource at all reads it.

    Returns:
        A Ref when the dashboard references the datasource, else None.
    """
    dash = payload.get("dashboard") or payload
    ds_vars = variable_reach(dash, wanted, aliases, ds_type)
    sites: set[str] = set()

    def note(ref: str, site: str) -> None:
        if variable_name(ref) is not None:
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
            panel_refs = list(datasource_refs(panel))
            for ref in panel_refs:
                note(ref, SITE_PANEL)
            targets = [t for t in panel.get("targets") or [] if isinstance(t, dict)]
            for target in targets:
                for ref in datasource_refs(target):
                    note(ref, SITE_TARGET)
            # No datasource anywhere means Grafana falls back to the instance default.
            implicit = (
                not panel_refs
                and "libraryPanel" not in panel
                and panel.get("type") not in CHROME_PANELS
                and any(not list(datasource_refs(t)) for t in targets)
            )
            if is_default and implicit:
                sites.add(SITE_PANEL)
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
        kind=row.get("kind", "dashboard"),
    )


def report(
    wanted: list[str],
    found: dict[str, list[Ref]],
    names: dict[str, str],
    stats: Stats,
    base_url: str,
    verbose: int,
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
        used = is_used(refs, count_selectors)
        in_use += used
        label = names.get(uid, uid)
        verdict = "IN USE" if used else "UNKNOWN" if stats.failed else "UNUSED"
        print(f"{label:{width}}  {len(direct):>6}  {selector:>8}  {verdict}")

    if verbose:
        for uid in wanted:
            refs = found.get(uid, [])
            direct = [r for r in refs if r.direct]
            label = names.get(uid, uid)
            if direct:
                print(f"\n{label} ({uid}) is read by:")
                for ref in sorted(direct, key=lambda r: r.title.lower()):
                    print(f"  {ref.title}  [{ref.folder}]")
                    print(f"    {ref.location(base_url)}")
                    print(f"    at {','.join(sorted(ref.sites & DIRECT_SITES))}")
            # Only on -vv: this list is the long one by construction, hundreds of
            # dashboards that merely offer the datasource in a dropdown.
            if verbose > 1:
                selector = [r for r in refs if not r.direct]
                if selector:
                    print(f"\n{label} ({uid}) is selectable, not read, in:")
                    for ref in sorted(selector, key=lambda r: r.title.lower()):
                        print(f"  {ref.title}  [{ref.folder}]  {ref.location(base_url)}")

    print(
        f"\n{len(wanted)} datasource(s): {len(wanted) - in_use} unused, {in_use} in use"
        f"  |  {stats.total} dashboards ({stats.from_cache} cached, {stats.fetched} fetched)"
    )
    if not count_selectors:
        print("selector-only hits are not usage: a datasource variable lists every "
              "datasource of its type. Pass --count-variable-only to include them.")
    report_failures(stats)
    return in_use


def is_used(refs: list[Ref], count_selectors: bool) -> bool:
    """The verdict for one datasource, shared by every output mode so they never disagree."""
    return any(r.direct for r in refs) or (count_selectors and bool(refs))


def build_parser() -> argparse.ArgumentParser:
    """Return the command line parser."""
    p = argparse.ArgumentParser(
        description="Check which dashboards actually read a Grafana datasource.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(__doc__ or "").split("Examples:", 1)[-1],
    )
    p.add_argument("-d", "--datasource", action="append", default=[], metavar="UID_OR_NAME",
                   help="datasource uid or name, repeatable")
    p.add_argument("-v", "--verbose", action="count", default=0,
                   help="list the dashboards that read it; repeat (-vv) to also "
                        "list the selector-only ones")
    p.add_argument("--count-variable-only", action="store_true",
                   help="count selector-only hits as usage (off by default)")
    p.add_argument("--json", action="store_true", help="machine readable output")
    p.add_argument("--quiet", action="store_true", help="no report, exit code only")
    p.add_argument("--url", default="",
                    help="Grafana base URL; picks the matching gcx context (default: gcx current context)")
    p.add_argument("--token", default="")
    p.add_argument("--gcx-context", default="",
                    help="gcx context for the gcx-api fallback [$GCX_CONTEXT]")
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
        0 when every datasource is unused, 1 when at least one is still read,
        EXIT_INCOMPLETE when nothing is read but some fetch failed.
    """
    args = build_parser().parse_args(argv)
    try:
        return run(args)
    except GrafanaError as exc:
        die(f"error: {exc}")


def run(args: argparse.Namespace) -> int:
    """Body of main, so main can turn API errors into EXIT_INCOMPLETE."""
    url, token, ctx = resolve_target(args.url, args.token, args.gcx_context)
    if not args.datasource:
        die("nothing to check: pass at least one -d/--datasource")

    client = Client(url, token, ctx)
    known = Datasources.fetch(client)
    names = known.names
    by_name: dict[str, str] = {v: k for k, v in names.items()}

    # Accept a uid or a name, and keep the other spelling as an alias: a target
    # may reference a datasource by name where the panel references it by uid.
    wanted: list[str] = []
    aliases: dict[str, set[str]] = {}
    for given in args.datasource:
        uid = given if given in names else by_name.get(given)
        if uid is None:
            # An unknown -d would match nothing and read UNUSED: a typo must not pass a gate.
            die(f"unknown datasource {given!r} on {url or 'the gcx context'}: not a uid or a name "
                f"listed by /api/datasources")
        wanted.append(uid)
        alias = {names[uid]}
        if given != uid:
            alias.add(given)
        aliases[uid] = alias

    cache = open_cache(args, url, ctx)
    stats = Stats()
    started = time.monotonic()
    rows = list_dashboards(client)
    cache.prune({row["uid"] for row in rows})

    found: dict[str, list[Ref]] = {uid: [] for uid in wanted}

    def scan(row: dict[str, Any], payload: dict[str, Any]) -> None:
        dash = payload.get("dashboard") or payload
        for uid in wanted:
            ref = scan_dashboard(row, dash, uid, aliases[uid], known.types.get(uid, ""), uid == known.default)
            if ref:
                found[uid].append(ref)

    for row, payload in fetch_dashboards(client, rows, cache, args.workers, stats):
        scan(row, payload)
    for element in list_library_panels(client, stats):
        scan(*library_panel_payload(element))
    elapsed = time.monotonic() - started
    in_use = sum(is_used(found[uid], args.count_variable_only) for uid in wanted)

    if args.json:
        print(json.dumps({
            "elapsed": round(elapsed, 2),
            "complete": not stats.failed,
            "failed": stats.failed,
            "dashboards_listed": stats.total,
            "dashboards_scanned": stats.from_cache + stats.fetched,
            "datasources": {
                uid: {
                    "name": names.get(uid),
                    "in_use": is_used(found[uid], args.count_variable_only),
                    "direct": [
                        {"uid": r.uid, "title": r.title, "folder": r.folder,
                         "sites": sorted(r.sites & DIRECT_SITES)}
                        for r in found[uid] if r.direct
                    ],
                    "selector_only": [
                        {"uid": r.uid, "title": r.title, "folder": r.folder}
                        for r in found[uid] if not r.direct
                    ],
                }
                for uid in wanted
            },
        }, indent=2))
        report_failures(stats)
    elif args.quiet:
        report_failures(stats)
    else:
        report(wanted, found, names, stats, url, args.verbose, args.count_variable_only)

    if in_use:
        return 1
    return EXIT_INCOMPLETE if stats.failed else 0


if __name__ == "__main__":
    sys.exit(main())
