#!/usr/bin/env python3
"""Check whether Prometheus metric families are referenced by any Grafana dashboard.

Answers the question you must answer before dropping a metric at scrape time:
"is anything actually reading this?". Scans every dashboard (all query shapes,
including the Cloud Monitoring ones that a plain `expr` sweep misses) plus the
Grafana-managed alert rules, and reports every reference it finds.

Dashboards are cached on disk so repeated runs only fetch what changed.

Examples:
    # one-off check
    ./grafana_metric_usage.py -m kube_pod_tolerations -m container_threads

    # feed it the exact relabel drop regexes from the values files
    ./grafana_metric_usage.py --regex -f drop-regexes.txt

    # CI gate: exit 1 as soon as one metric is still referenced
    ./grafana_metric_usage.py -f metrics.txt --quiet || echo "still in use"

Auth (see resolve_target):
    --url          target instance; requests go through the gcx context whose
                   server has that host. Default: gcx's current context.
    --gcx-context  force a gcx context ($GCX_CONTEXT).
    GRAFANA_TOKEN  static token (also GRAFANA_SERVICE_ACCOUNT_TOKEN, GTOK), used
                   only for the host of $GRAFANA_URL, or when gcx is missing.
"""

from __future__ import annotations

import argparse
import fnmatch
import gzip
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from http.client import HTTPConnection, HTTPSConnection
from pathlib import Path
from typing import Any, Iterable, Iterator
from urllib.parse import quote, urlencode, urlparse

DEFAULT_CACHE = Path(
    os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
) / "grafana-metric-usage"
DEFAULT_MAX_AGE = 24 * 3600
DEFAULT_WORKERS = 12

# Keys whose string values can hold a query. Covers PromQL (`expr`), Cloud
# Monitoring PromQL mode (`promQLQuery.expr`), Cloud Monitoring MQL mode
# (`timeSeriesQuery.query`) and template variables (`templating.list[].query`),
# which is what a naive `$..targets[*].expr` sweep silently misses.
QUERY_KEYS = frozenset({"expr", "query", "rawQuery", "definition", "metricName"})
TEXT_KEYS = frozenset({"title", "description", "legendFormat", "content"})

# PromQL identifier. Tokens immediately followed by "(" are function calls and
# are skipped, so `rate(` and `histogram_quantile(` never look like metrics.
IDENT_RE = re.compile(r"[A-Za-z_:][A-Za-z0-9_:]*")

# Reserved words that are valid identifiers but never metric names.
PROMQL_KEYWORDS = frozenset(
    """
    by without on ignoring group_left group_right offset bool and or unless
    start end atan2 inf nan
    """.split()
)


STATIC_TOKEN_VARS = ("GRAFANA_TOKEN", "GRAFANA_SERVICE_ACCOUNT_TOKEN", "GTOK")


def env_token() -> str:
    """Return the first static token set in the environment, or ""."""
    for name in STATIC_TOKEN_VARS:
        if os.environ.get(name):
            return os.environ[name]
    return ""


def url_host(url: str) -> str:
    """Lowercased host[:port] of a URL, tolerating a missing scheme."""
    return urlparse(url if "://" in url else f"https://{url}").netloc.lower()


def gcx_context(explicit: str = "") -> str:
    """Resolve the gcx context to use for the gcx-api fallback.

    Order: --gcx-context, $GCX_CONTEXT, else "" (gcx's own current-context).
    """
    return explicit or os.environ.get("GCX_CONTEXT", "")


def gcx_context_for_url(url: str) -> str:
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


def resolve_target(url: str = "", token: str = "", context: str = "") -> tuple[str, str, str]:
    """Pick the Grafana base URL, static token and gcx context for a run.

    Shared by the Grafana skills, deliberately duplicated so each one stands
    alone. A token from the environment belongs to $GRAFANA_URL and is never
    sent to another host: that is what answered 401 on every other instance.

    Order: --token (with --url or $GRAFANA_URL); --gcx-context / $GCX_CONTEXT;
    --url (the env token when its host is $GRAFANA_URL's, else the gcx context
    serving that host); gcx's current context; env token + $GRAFANA_URL when
    gcx is not installed.

    Args:
        url: --url as passed on the command line, "" when absent.
        token: --token as passed on the command line, "" when absent.
        context: --gcx-context as passed on the command line, "" when absent.

    Returns:
        (base_url, static_token, gcx_context). An empty token means every
        request goes through `gcx api`; base_url may then be "".
    """
    env_url = os.environ.get("GRAFANA_URL", "")
    if token:
        if not (url or env_url):
            sys.exit("no Grafana URL: pass --url or set GRAFANA_URL (required with --token)")
        return url or env_url, token, ""
    have_gcx = shutil.which("gcx") is not None
    ctx = gcx_context(context)
    if ctx:
        if not have_gcx:
            sys.exit(f"gcx context {ctx!r} requested but gcx is not on PATH (brew install gcx)")
        return gcx_default_url(ctx), "", ctx
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


def cache_namespace(url: str, context: str) -> str:
    """Per-instance cache subdirectory, so two Grafanas never share entries."""
    return url_host(url) or context or "gcx-current-context"


def gcx_env():
    """Environment for gcx without the static-token variables.

    gcx treats GRAFANA_TOKEN and friends as an auth override, which silently
    replaces the context's OAuth login and answers 401.
    """
    return {k: v for k, v in os.environ.items()
            if k not in ("GRAFANA_TOKEN", "GRAFANA_SERVICE_ACCOUNT_TOKEN", "GRAFANA_URL")}


def gcx_api_json(path: str, params: dict[str, Any] | None, context: str, timeout: float = 60.0) -> Any:
    """GET a Grafana API path through `gcx api`, so OAuth refresh stays gcx's job.

    Used when no static token is configured: gcx resolves auth (OAuth or a
    static token, per its own context) instead of this script reading or
    caching a credential itself.

    Args:
        path: API path, starting with "/".
        params: Optional query string parameters.
        context: gcx context name, or "" for gcx's current-context.
        timeout: Subprocess timeout, in seconds.

    Returns:
        The decoded JSON body, or None on a 404.

    Raises:
        GrafanaError: On a non-2xx response, a timeout, or an unparseable reply.
    """
    url = f"{path}?{urlencode(params)}" if params else path
    cmd = ["gcx", "api", url, "-o", "json"]
    if context:
        cmd += ["--context", context]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False, env=gcx_env())
    except FileNotFoundError:
        raise GrafanaError("gcx not found on PATH: install it or set GRAFANA_TOKEN")
    except subprocess.TimeoutExpired:
        raise GrafanaError(f"gcx api {path} timed out after {timeout:.0f}s")
    if proc.returncode != 0:
        try:
            summary = json.loads(proc.stdout)["error"]["summary"]
        except (json.JSONDecodeError, KeyError, TypeError):
            summary = (proc.stdout or proc.stderr or "").strip()[:300]
        if "404" in summary:
            return None
        raise GrafanaError(f"gcx api {path} failed: {summary}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise GrafanaError(f"gcx api {path}: unparseable response: {exc}")


def gcx_default_url(context: str = "") -> str:
    """Ask gcx for the current context's Grafana base URL, best effort.

    Used only when --url/$GRAFANA_URL is unset and gcx is doing the auth, so
    the URL still comes from gcx's own config, never a hardcoded default
    (this repo is public: no host belongs in the source).

    Args:
        context: gcx context name, or "" for gcx's current-context.

    Returns:
        The base URL, or "" if it could not be determined.
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


class GrafanaError(RuntimeError):
    """Raised when the Grafana API answers something unusable."""


@dataclass(slots=True)
class Hit:
    """One reference to a metric, found somewhere in Grafana."""

    metric: str  # the pattern that was asked for
    matched: str  # the identifier that actually matched it, differs in regex/glob mode
    kind: str  # "dashboard" or "alert-rule"
    uid: str
    title: str
    folder: str
    where: str  # which JSON key the reference was found under
    datasource: str

    def location(self, base_url: str) -> str:
        """Return a clickable URL for the object holding this reference."""
        if self.kind == "dashboard":
            return f"{base_url}/d/{self.uid}"
        return f"{base_url}/alerting/grafana/{self.uid}/view"


@dataclass(slots=True)
class Stats:
    """Counters for the run, reported at the end."""

    total: int = 0
    from_cache: int = 0
    fetched: int = 0
    failed: list[str] = field(default_factory=list)


class Client:
    """Minimal threaded HTTP client with one persistent connection per thread.

    Reusing the connection avoids a TCP and TLS handshake per dashboard, which
    dominates the wall clock when fetching a thousand small JSON documents.
    """

    def __init__(self, base_url: str, token: str, gcx_ctx: str = "", timeout: float = 30.0) -> None:
        """Initialise the client.

        Args:
            base_url: Grafana base URL, scheme included. May be "" when
                `token` is also "": every request then goes through `gcx api`,
                which resolves its own target from the gcx context.
            token: Bearer token sent on every request. Empty routes requests
                through `gcx api` instead, so OAuth refresh stays gcx's job.
            gcx_ctx: gcx context to use when `token` is empty.
            timeout: Per-request socket timeout, in seconds.
        """
        self._token = token
        self._gcx_ctx = gcx_ctx
        self._use_gcx = not token
        self._timeout = timeout
        self._local = threading.local()
        if not base_url:
            if not self._use_gcx:
                raise GrafanaError("no Grafana URL: set GRAFANA_URL or pass --url")
            self.base_url = ""
            self._host = self._prefix = ""
            self._https = False
            return
        parsed = urlparse(base_url.rstrip("/"))
        if parsed.scheme not in ("http", "https"):
            raise GrafanaError(f"unsupported scheme in GRAFANA_URL: {base_url!r}")
        self.base_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path}".rstrip("/")
        self._host = parsed.netloc
        self._https = parsed.scheme == "https"
        self._prefix = parsed.path.rstrip("/")

    def _connection(self) -> HTTPConnection | HTTPSConnection:
        """Return this thread's connection, creating it on first use."""
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = (
                HTTPSConnection(self._host, timeout=self._timeout, context=ssl.create_default_context())
                if self._https
                else HTTPConnection(self._host, timeout=self._timeout)
            )
            self._local.conn = conn
        return conn

    def _drop_connection(self) -> None:
        """Close and forget this thread's connection so the next call reconnects."""
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            try:
                conn.close()
            except OSError:
                pass
            self._local.conn = None

    def get_json(self, path: str, params: dict[str, Any] | None = None, retries: int = 3) -> Any:
        """GET a JSON document.

        Args:
            path: API path, starting with "/".
            params: Optional query string parameters.
            retries: How many times to retry on a transport error or a 5xx.

        Returns:
            The decoded JSON body, or None on a 404.

        Raises:
            GrafanaError: On a non-retryable HTTP error or exhausted retries.
        """
        if self._use_gcx:
            return gcx_api_json(path, params, self._gcx_ctx, timeout=self._timeout)
        url = f"{self._prefix}{path}"
        if params:
            url = f"{url}?{urlencode(params)}"
        headers = {
            "Authorization": f"Bearer {self._token}",
            "Accept": "application/json",
            "Accept-Encoding": "gzip",
        }
        last: Exception | None = None
        for attempt in range(retries):
            try:
                conn = self._connection()
                conn.request("GET", url, headers=headers)
                resp = conn.getresponse()
                body = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    body = gzip.decompress(body)
                if resp.status == 404:
                    return None
                if resp.status in (401, 403):
                    raise GrafanaError(f"{resp.status} on {url}: check GRAFANA_TOKEN scope")
                if resp.status >= 500:
                    raise OSError(f"{resp.status} on {url}")
                if resp.status >= 400:
                    raise GrafanaError(f"{resp.status} on {url}: {body[:200]!r}")
                return json.loads(body)
            except GrafanaError:
                raise
            except (OSError, json.JSONDecodeError) as exc:
                last = exc
                self._drop_connection()
                if attempt < retries - 1:
                    time.sleep(0.25 * 2**attempt)
        raise GrafanaError(f"GET {url} failed after {retries} attempts: {last}")

    def close(self) -> None:
        """Close this thread's connection."""
        self._drop_connection()


class Cache:
    """On-disk cache of dashboard payloads, one gzipped JSON per uid."""

    def __init__(self, root: Path, max_age: float, refresh: bool) -> None:
        """Initialise the cache.

        Args:
            root: Directory holding the cache. Created if missing.
            max_age: Entries older than this many seconds are refetched.
            refresh: When true, ignore every entry and refetch everything.
        """
        self.root = root
        self.blobs = root / "dashboards"
        self.max_age = max_age
        self.refresh = refresh
        self.blobs.mkdir(parents=True, exist_ok=True)
        self._manifest_path = root / "manifest.json"
        self._lock = threading.Lock()
        try:
            self._manifest: dict[str, dict[str, Any]] = json.loads(
                self._manifest_path.read_text()
            )
        except (OSError, json.JSONDecodeError):
            self._manifest = {}

    def _blob(self, uid: str) -> Path:
        return self.blobs / f"{quote(uid, safe='')}.json.gz"

    def get(self, uid: str) -> dict[str, Any] | None:
        """Return the cached payload for a uid, or None if absent or stale."""
        if self.refresh:
            return None
        entry = self._manifest.get(uid)
        if not entry or time.time() - entry.get("fetched_at", 0) > self.max_age:
            return None
        try:
            with gzip.open(self._blob(uid), "rt", encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, json.JSONDecodeError):
            return None

    def put(self, uid: str, payload: dict[str, Any]) -> None:
        """Store a payload for a uid and record its fetch time."""
        tmp = self._blob(uid).with_suffix(".tmp")
        with gzip.open(tmp, "wt", encoding="utf-8") as handle:
            json.dump(payload, handle)
        tmp.replace(self._blob(uid))
        meta = payload.get("meta", {}) or {}
        with self._lock:
            self._manifest[uid] = {
                "fetched_at": time.time(),
                "version": (payload.get("dashboard", {}) or {}).get("version"),
                "updated": meta.get("updated"),
            }

    def prune(self, live_uids: set[str]) -> int:
        """Drop cache entries for dashboards that no longer exist.

        Args:
            live_uids: The uids currently returned by the search API.

        Returns:
            How many stale entries were removed.
        """
        with self._lock:
            gone = set(self._manifest) - live_uids
            for uid in gone:
                self._manifest.pop(uid, None)
                self._blob(uid).unlink(missing_ok=True)
        return len(gone)

    def flush(self) -> None:
        """Persist the manifest to disk."""
        with self._lock:
            tmp = self._manifest_path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._manifest))
            tmp.replace(self._manifest_path)


def _local_datasource(node: dict[str, Any]) -> str | None:
    """Return the datasource declared on a node, in either shape Grafana emits.

    Args:
        node: A decoded JSON object.

    Returns:
        The datasource uid or variable reference, or None when absent.
    """
    ds = node.get("datasource")
    if isinstance(ds, str):
        return ds
    if isinstance(ds, dict) and isinstance(ds.get("uid"), str):
        return ds["uid"]
    return None


def walk_strings(
    node: Any, keys: frozenset[str], path: str = "", datasource: str | None = None
) -> Iterator[tuple[str, str, str | None]]:
    """Yield every string value stored under one of `keys`, with its context.

    Walks the whole tree, so collapsed rows (`panels[].panels[]`) and nested
    Cloud Monitoring query objects are covered without enumerating each shape.
    The nearest enclosing datasource is carried down, so a hit is attributed to
    the datasource its own target queries rather than to the dashboard's union.

    Args:
        node: Any decoded JSON value.
        keys: Object keys whose string values should be yielded.
        path: Accumulated JSON path, used for reporting.
        datasource: Nearest enclosing datasource reference.

    Yields:
        Tuples of (json path, string value, nearest datasource).
    """
    if isinstance(node, dict):
        datasource = _local_datasource(node) or datasource
        for key, value in node.items():
            child = f"{path}.{key}" if path else key
            if key in keys and isinstance(value, str) and value.strip():
                yield child, value, datasource
            else:
                yield from walk_strings(value, keys, child, datasource)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_strings(value, keys, f"{path}[{index}]", datasource)


def find_datasources(node: Any) -> set[str]:
    """Collect every datasource reference in a subtree.

    Handles both shapes Grafana emits, the bare string `"${ds}"` and the object
    `{"type": ..., "uid": ...}`, which routinely coexist in one dashboard.

    Args:
        node: Any decoded JSON value.

    Returns:
        The set of datasource identifiers found.
    """
    found: set[str] = set()
    if isinstance(node, dict):
        ds = node.get("datasource")
        if isinstance(ds, str):
            found.add(ds)
        elif isinstance(ds, dict) and isinstance(ds.get("uid"), str):
            found.add(ds["uid"])
        for value in node.values():
            found |= find_datasources(value)
    elif isinstance(node, list):
        for value in node:
            found |= find_datasources(value)
    return found


def identifiers(query: str) -> set[str]:
    """Extract the metric-name-looking identifiers from a query string.

    Tokens directly followed by "(" are dropped, so PromQL functions are not
    mistaken for metrics. Quoted content is kept on purpose: a selector written
    as `{__name__="foo"}` is a genuine use of `foo`.

    Args:
        query: A PromQL, MQL or template variable query.

    Returns:
        The set of candidate metric names.
    """
    out: set[str] = set()
    for match in IDENT_RE.finditer(query):
        token = match.group(0)
        if token in PROMQL_KEYWORDS:
            continue
        tail = query[match.end() : match.end() + 1]
        if tail == "(":
            continue
        out.add(token)
    return out


class Matcher:
    """Decides whether a candidate identifier is one of the wanted metrics."""

    def __init__(self, patterns: Iterable[str], mode: str) -> None:
        """Initialise the matcher.

        Args:
            patterns: Metric names, glob patterns or regexes.
            mode: One of "exact", "glob" or "regex". Regexes are fully anchored,
                exactly like a Prometheus relabel rule, so a pattern copied out
                of a values file behaves here as it does in the scrape config.
        """
        self.patterns = list(patterns)
        self.mode = mode
        if mode == "regex":
            self._res = [re.compile(f"^(?:{p})$") for p in self.patterns]
        elif mode == "exact":
            self._exact = set(self.patterns)

    def match(self, candidate: str) -> str | None:
        """Return the pattern a candidate matches, or None.

        Args:
            candidate: An identifier extracted from a query.

        Returns:
            The matching pattern, so the report can group by pattern.
        """
        if self.mode == "exact":
            return candidate if candidate in self._exact else None
        if self.mode == "glob":
            for pattern in self.patterns:
                if fnmatch.fnmatchcase(candidate, pattern):
                    return pattern
            return None
        for pattern, compiled in zip(self.patterns, self._res, strict=True):
            if compiled.match(candidate):
                return pattern
        return None


def list_dashboards(client: Client) -> list[dict[str, Any]]:
    """Return the search index for every dashboard, following pagination.

    Args:
        client: An initialised Grafana client.

    Returns:
        The raw search rows, each carrying at least uid, title and folderTitle.
    """
    rows: list[dict[str, Any]] = []
    page = 1
    while True:
        batch = client.get_json("/api/search", {"type": "dash-db", "limit": 1000, "page": page})
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < 1000:
            break
        page += 1
    return rows


def fetch_dashboards(
    client: Client, rows: list[dict[str, Any]], cache: Cache, workers: int, stats: Stats
) -> Iterator[tuple[dict[str, Any], dict[str, Any]]]:
    """Yield (search row, dashboard payload) for every dashboard.

    Cache hits are yielded immediately; misses are fetched concurrently.

    Args:
        client: An initialised Grafana client.
        rows: Search rows from `list_dashboards`.
        cache: The on-disk cache.
        workers: Thread pool size.
        stats: Counters, mutated in place.

    Yields:
        Tuples of (search row, dashboard payload).
    """
    misses: list[dict[str, Any]] = []
    for row in rows:
        stats.total += 1
        cached = cache.get(row["uid"])
        if cached is not None:
            stats.from_cache += 1
            yield row, cached
        else:
            misses.append(row)

    if not misses:
        return

    def _fetch(row: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any] | None]:
        return row, client.get_json(f"/api/dashboards/uid/{quote(row['uid'], safe='')}")

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(_fetch, row) for row in misses]
        for future in as_completed(futures):
            try:
                row, payload = future.result()
            except GrafanaError as exc:
                stats.failed.append(str(exc))
                continue
            if payload is None:
                continue
            cache.put(row["uid"], payload)
            stats.fetched += 1
            yield row, payload
    cache.flush()


def scan_dashboard(
    row: dict[str, Any], payload: dict[str, Any], matcher: Matcher, keys: frozenset[str]
) -> list[Hit]:
    """Find every wanted metric referenced by one dashboard.

    Args:
        row: The search row, for title and folder.
        payload: The `/api/dashboards/uid` response.
        matcher: The metric matcher.
        keys: JSON keys to scan.

    Returns:
        One Hit per (metric, json path) pair found.
    """
    dashboard = payload.get("dashboard") or {}
    fallback = ", ".join(sorted(find_datasources(dashboard))) or "-"
    hits: list[Hit] = []
    seen: set[tuple[str, str, str]] = set()
    for path, value, datasource in walk_strings(dashboard, keys):
        for candidate in identifiers(value):
            pattern = matcher.match(candidate)
            if pattern is None or (pattern, candidate, path) in seen:
                continue
            seen.add((pattern, candidate, path))
            hits.append(
                Hit(
                    metric=pattern,
                    matched=candidate,
                    kind="dashboard",
                    uid=row["uid"],
                    title=row.get("title", "?"),
                    folder=row.get("folderTitle", "General"),
                    where=path,
                    datasource=datasource or fallback,
                )
            )
    return hits


def scan_alert_rules(client: Client, matcher: Matcher) -> list[Hit]:
    """Find every wanted metric referenced by a Grafana-managed alert rule.

    Args:
        client: An initialised Grafana client.
        matcher: The metric matcher.

    Returns:
        One Hit per (metric, rule) pair found. Empty when the token cannot read
        the provisioning API, which is reported but not fatal.
    """
    try:
        rules = client.get_json("/api/v1/provisioning/alert-rules")
    except GrafanaError as exc:
        print(f"warning: alert rules not scanned ({exc})", file=sys.stderr)
        return []
    if not rules:
        return []
    hits: list[Hit] = []
    for rule in rules:
        seen: set[tuple[str, str]] = set()
        for path, value, _ in walk_strings(rule.get("data", []), QUERY_KEYS):
            for candidate in identifiers(value):
                pattern = matcher.match(candidate)
                if pattern is None or (pattern, candidate) in seen:
                    continue
                seen.add((pattern, candidate))
                hits.append(
                    Hit(
                        metric=pattern,
                        matched=candidate,
                        kind="alert-rule",
                        uid=rule.get("uid", "?"),
                        title=rule.get("title", "?"),
                        folder=rule.get("folderUID", "-"),
                        where=path,
                        datasource=rule.get("ruleGroup", "-"),
                    )
                )
    return hits


def resolve_datasources(client: Client) -> dict[str, str]:
    """Map datasource uid to name, so dead references can be spotted.

    Args:
        client: An initialised Grafana client.

    Returns:
        A uid to name mapping. Empty when the token cannot list datasources.
    """
    try:
        items = client.get_json("/api/datasources") or []
    except GrafanaError:
        return {}
    return {item["uid"]: item.get("name", "?") for item in items if "uid" in item}


def describe_datasource(ref: str, known: dict[str, str]) -> str:
    """Render a datasource reference, flagging the ones that no longer resolve.

    A hit on a dashboard whose datasource is gone or is an unresolved import
    variable is not a real consumer, which is the distinction that decides
    whether a metric can be dropped.

    Args:
        ref: The datasource uid or variable found next to the query.
        known: uid to name mapping from /api/datasources.

    Returns:
        A short human-readable description.
    """
    if not ref or ref == "-":
        return "unset (dashboard default)"
    if ref.startswith("$"):
        return f"{ref} UNRESOLVED-VARIABLE"
    if ref in ("-- Grafana --", "grafana", "-- Mixed --", "-- Dashboard --"):
        return ref
    name = known.get(ref)
    return f"{ref} ({name})" if name else f"{ref} DEAD"


def report(
    patterns: list[str], hits: list[Hit], stats: Stats, base_url: str, datasources: dict[str, str], verbose: bool
) -> None:
    """Print the human-readable report.

    Args:
        patterns: The patterns that were asked for, in input order.
        hits: Every reference found.
        stats: Fetch counters.
        base_url: Grafana base URL, for building links.
        datasources: uid to name mapping, for flagging dead references.
        verbose: When true, list every reference instead of a count.
    """
    by_metric: dict[str, list[Hit]] = {p: [] for p in patterns}
    for hit in hits:
        by_metric.setdefault(hit.metric, []).append(hit)

    width = min(max((len(p) for p in patterns), default=10), 70)
    print(f"\n{'metric / pattern':{width}}  {'dashboards':>10}  {'alerts':>6}  verdict")
    print("-" * (width + 34))
    unused = 0
    for pattern in patterns:
        found = by_metric[pattern]
        dash = len({h.uid for h in found if h.kind == "dashboard"})
        alert = len({h.uid for h in found if h.kind == "alert-rule"})
        verdict = "UNUSED" if not found else "IN USE"
        unused += not found
        print(f"{pattern:{width}}  {dash:>10}  {alert:>6}  {verdict}")
        # In regex/glob mode the pattern covers many families; say which ones are
        # actually read, or the caller cannot tell what to keep out of a drop rule.
        via = sorted({h.matched for h in found if h.matched != pattern})
        if via:
            print(f"{'':{width}}  via: {', '.join(via)}")

    if verbose and hits:
        print("\nreferences:")
        for pattern in patterns:
            for hit in by_metric[pattern]:
                label = hit.matched if hit.matched == pattern else f"{hit.matched}  (matched {pattern})"
                print(f"  {label}")
                print(f"    {hit.kind} {hit.title!r} [{hit.folder}] {hit.location(base_url)}")
                print(f"    at {hit.where}  ds={describe_datasource(hit.datasource, datasources)}")

    print(
        f"\n{len(patterns)} pattern(s): {unused} unused, {len(patterns) - unused} in use"
        f"  |  {stats.total} dashboards ({stats.from_cache} cached, {stats.fetched} fetched)"
    )
    for failure in stats.failed:
        print(f"  fetch error: {failure}", file=sys.stderr)


def load_patterns(args: argparse.Namespace) -> list[str]:
    """Collect the patterns to check, from flags, a file or stdin.

    Args:
        args: Parsed command line arguments.

    Returns:
        The patterns, de-duplicated, in first-seen order.

    Raises:
        SystemExit: When no pattern was supplied.
    """
    raw: list[str] = list(args.metric)
    if args.metrics_file:
        raw += args.metrics_file.read_text().splitlines()
    if not sys.stdin.isatty() and not raw:
        raw += sys.stdin.read().splitlines()
    out: list[str] = []
    for line in raw:
        line = line.split("#", 1)[0].strip()
        if line and line not in out:
            out.append(line)
    if not out:
        raise SystemExit("no metric supplied: use -m, -f or pipe a list on stdin")
    return out


def build_parser() -> argparse.ArgumentParser:
    """Build the command line parser."""
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Exit code is 1 when at least one pattern is still referenced.",
    )
    parser.add_argument("-m", "--metric", action="append", default=[], help="metric name, repeatable")
    parser.add_argument("-f", "--metrics-file", type=Path, help="file with one metric per line, # comments allowed")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--regex", action="store_true", help="treat inputs as fully anchored regexes, like a relabel rule")
    mode.add_argument("--glob", action="store_true", help="treat inputs as glob patterns")
    parser.add_argument("--url", default="",
                         help="Grafana base URL; picks the matching gcx context (default: gcx current context)")
    parser.add_argument("--token", default="", help="API token; see resolve_target for the lookup order")
    parser.add_argument("--gcx-context", default="",
                         help="gcx context for the gcx-api fallback [$GCX_CONTEXT]")
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE, help=f"cache directory [{DEFAULT_CACHE}]")
    parser.add_argument("--max-age", type=float, default=DEFAULT_MAX_AGE, help="cache entry lifetime in seconds")
    parser.add_argument("--refresh", action="store_true", help="ignore the cache and refetch every dashboard")
    parser.add_argument("--workers", type=int, default=DEFAULT_WORKERS, help="concurrent fetches")
    parser.add_argument("--include-text", action="store_true", help="also scan titles, descriptions and legends")
    parser.add_argument("--no-alerts", action="store_true", help="skip Grafana-managed alert rules")
    parser.add_argument("-v", "--verbose", action="store_true", help="list every reference found")
    parser.add_argument("-q", "--quiet", action="store_true", help="print nothing, rely on the exit code")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the check.

    Args:
        argv: Command line arguments, defaulting to sys.argv[1:].

    Returns:
        0 when every pattern is unused, 1 when at least one is still referenced.
    """
    args = build_parser().parse_args(argv)
    url, token, ctx = resolve_target(args.url, args.token, args.gcx_context)

    patterns = load_patterns(args)
    mode = "regex" if args.regex else "glob" if args.glob else "exact"
    matcher = Matcher(patterns, mode)
    keys = QUERY_KEYS | TEXT_KEYS if args.include_text else QUERY_KEYS

    client = Client(url, token, ctx)
    cache = Cache(args.cache_dir / cache_namespace(url, ctx), args.max_age, args.refresh)
    stats = Stats()

    started = time.monotonic()
    rows = list_dashboards(client)
    cache.prune({row["uid"] for row in rows})

    hits: list[Hit] = []
    for row, payload in fetch_dashboards(client, rows, cache, args.workers, stats):
        hits.extend(scan_dashboard(row, payload, matcher, keys))
    if not args.no_alerts:
        hits.extend(scan_alert_rules(client, matcher))
    elapsed = time.monotonic() - started

    if args.json:
        found = {p: [] for p in patterns}
        for hit in hits:
            found[hit.metric].append(
                {
                    "matched": hit.matched,
                    "kind": hit.kind,
                    "uid": hit.uid,
                    "title": hit.title,
                    "folder": hit.folder,
                    "where": hit.where,
                    "url": hit.location(client.base_url),
                }
            )
        print(json.dumps({"patterns": found, "dashboards_scanned": stats.total, "seconds": round(elapsed, 2)}, indent=2))
    elif not args.quiet:
        report(patterns, hits, stats, client.base_url, resolve_datasources(client), args.verbose)
        print(f"scanned in {elapsed:.1f}s")

    client.close()
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
