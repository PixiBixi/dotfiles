#!/usr/bin/env python3
"""Check a Grafana dashboard against the schema baseline before saving it.

Implements the mechanical half of the grafana-dashboards skill: the checks that
are decidable from the JSON alone, so the skill can keep prose for the judgment
calls. Traverses collapsed rows, which a flat `$.panels[*]` read misses.

Examples:
    ./lint_dashboard.py mydash.json
    ./lint_dashboard.py --uid abc123 --uid def456
    ./lint_dashboard.py --folder "K8S" --expect-ds-var ds
    ./lint_dashboard.py mydash.json --json

Environment (only for --uid and --folder):
    GRAFANA_URL    base URL, e.g. https://grafana.example.com
    GRAFANA_TOKEN  API token; see grafana_metric_usage.resolve_token for the full chain
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grafana_metric_usage import Client, GrafanaError, list_dashboards, resolve_token  # noqa: E402  # type: ignore[import-not-found]

# Panel types that carry no query and therefore no datasource.
CHROME_PANELS = frozenset({"row", "text", "dashlist", "news", "welcome"})

# User-facing strings that must be English.
TEXT_FIELDS = ("title", "description", "legendFormat", "displayName", "text", "label")

# Function words that are unambiguous markers of a non-English string. Kept
# short and >=4 chars on purpose: this flags candidates for a human to confirm,
# not a language detector. Short tokens collide with PromQL labels and acronyms
# (`le` is the histogram bucket label, `LA` is load average), and British
# spellings like "utilisation" are English, so none of those belong here.
NON_ENGLISH = frozenset(
    """
    les une dans pour avec nombre nombres moyenne memoire mémoire disponible
    erreur erreurs requete requête requetes requêtes serveur serveurs reseau
    réseau debit débit noeud noeuds nœud quantite quantité seconde taille
    temps duree durée actif actifs utilisateur utilisateurs
    nicht ohne fehler anzahl auslastung speicher uebersicht übersicht
    para sobre memoria errores servidor usuarios consultas
    della delle degli errori richieste
    """.split()
)

# Label interpolations and variables are not prose: `{{le}}` is the histogram
# bucket label, not the French article.
INTERPOLATION = re.compile(r"\{\{[^}]*\}\}|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?")

ACCENTED = re.compile(r"[àâäçéèêëîïôöùûüÿœæÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆñÑßüÜ]")

# Range selector with a subquery step left empty: `[24h:]` re-evaluates the
# inner query at the default step, 1440 times over a day.
STEPLESS_SUBQUERY = re.compile(r"\[[0-9]+[smhdwy]:\]")

WORD = re.compile(r"[a-zà-ÿ]+", re.IGNORECASE)


@dataclass(slots=True)
class Finding:
    """One rule violation, anchored at a JSON path."""

    level: str  # "error" or "warn"
    rule: str
    path: str
    detail: str


def iter_panels(dashboard: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    """Yield every panel, descending into collapsed rows.

    A collapsed row stores its children under `panels`, invisible to a flat
    `$.panels[*]` read, which is how an audit silently covers a third of a
    dashboard and calls it clean.

    Args:
        dashboard: The dashboard object (not the API envelope).

    Yields:
        Tuples of (json path, panel object).
    """
    for index, panel in enumerate(dashboard.get("panels") or []):
        path = f"panels[{index}]"
        yield path, panel
        for sub_index, nested in enumerate(panel.get("panels") or []):
            yield f"{path}.panels[{sub_index}]", nested


def iter_text(node: Any, path: str = "") -> Iterator[tuple[str, str]]:
    """Yield every user-facing string in the tree, with its JSON path.

    Args:
        node: Any decoded JSON value.
        path: Accumulated JSON path.

    Yields:
        Tuples of (json path, string value).
    """
    if isinstance(node, dict):
        for key, value in node.items():
            child = f"{path}.{key}" if path else key
            if key in TEXT_FIELDS and isinstance(value, str) and value.strip():
                yield child, value
            else:
                yield from iter_text(value, child)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from iter_text(value, f"{path}[{index}]")


def datasource_ref(node: dict[str, Any]) -> str | None:
    """Return a node's datasource, in either shape Grafana emits.

    Args:
        node: A decoded JSON object.

    Returns:
        The uid or variable reference, or None when the node declares none.
    """
    ds = node.get("datasource")
    if isinstance(ds, str):
        return ds
    if isinstance(ds, dict) and isinstance(ds.get("uid"), str):
        return ds["uid"]
    return None


def looks_non_english(text: str) -> str | None:
    """Return the evidence that a string is not English, or None.

    Args:
        text: A user-facing string.

    Returns:
        A short reason, suitable for a report line.
    """
    prose = INTERPOLATION.sub(" ", text)
    if ACCENTED.search(prose):
        return f"accented characters in {text!r}"
    words = {w.lower() for w in WORD.findall(prose)}
    hits = sorted(words & NON_ENGLISH)
    return f"non-English words {hits} in {text!r}" if hits else None


def check_defaults(dashboard: dict[str, Any]) -> list[Finding]:
    """Check the dashboard-level schema baseline.

    Args:
        dashboard: The dashboard object.

    Returns:
        Findings for graphTooltip, timezone, description and editable.
    """
    out: list[Finding] = []
    tooltip = dashboard.get("graphTooltip")
    if tooltip != 1:
        explain = {
            0: "0 = no cursor sharing",
            2: "2 = shared tooltip, unreadable past ~10 panels",
        }
        detail = explain.get(tooltip) if isinstance(tooltip, int) else None
        out.append(
            Finding("error", "shared-crosshair", "graphTooltip", f"{detail or repr(tooltip)}, must be 1")
        )
    if dashboard.get("timezone") != "utc":
        out.append(
            Finding("error", "timezone", "timezone", f"{dashboard.get('timezone')!r}, must be 'utc'")
        )
    if not (dashboard.get("description") or "").strip():
        out.append(
            Finding("error", "description", "description", "missing, it is what Grafana search shows")
        )
    if dashboard.get("editable") is False:
        out.append(Finding("warn", "editable", "editable", "false, blocks edits in the UI"))
    return out


def check_panels(dashboard: dict[str, Any], expect_ds_var: str | None) -> list[Finding]:
    """Check panel ids, deprecated types and datasource references.

    Args:
        dashboard: The dashboard object.
        expect_ds_var: Datasource variable the panels should follow, if any.

    Returns:
        Findings for missing or duplicate ids, `graph` panels and pinned uids.
    """
    out: list[Finding] = []
    ids = Counter()
    for path, panel in iter_panels(dashboard):
        panel_id = panel.get("id")
        if panel_id is None:
            out.append(
                Finding("error", "panel-id", f"{path}.id", "missing, breaks ?viewPanel= and the slow log")
            )
        else:
            ids[panel_id] += 1
        if panel.get("type") == "graph":
            out.append(Finding("error", "deprecated-panel", f"{path}.type", "'graph' plugin is deprecated"))
        if panel.get("type") in CHROME_PANELS:
            continue
        for target_index, target in enumerate(panel.get("targets") or []):
            if not isinstance(target, dict):
                continue
            ref = datasource_ref(target) or datasource_ref(panel)
            if expect_ds_var and ref and not ref.startswith("$"):
                out.append(
                    Finding(
                        "warn",
                        "pinned-datasource",
                        f"{path}.targets[{target_index}].datasource",
                        f"hardcoded {ref!r}, expected the ${{{expect_ds_var}}} variable",
                    )
                )
    for panel_id, count in ids.items():
        if count > 1:
            out.append(Finding("error", "panel-id", "panels[].id", f"id {panel_id} used {count} times"))
    return out


def check_variables(dashboard: dict[str, Any], expect_ds_var: str | None) -> list[Finding]:
    """Check the datasource variable name against the folder's convention.

    Args:
        dashboard: The dashboard object.
        expect_ds_var: The expected name, or None to skip.

    Returns:
        Findings for a datasource variable named differently.
    """
    if not expect_ds_var:
        return []
    out: list[Finding] = []
    for index, variable in enumerate(dashboard.get("templating", {}).get("list") or []):
        if variable.get("type") != "datasource":
            continue
        name = variable.get("name")
        if name != expect_ds_var:
            out.append(
                Finding(
                    "error",
                    "datasource-var-name",
                    f"templating.list[{index}].name",
                    f"{name!r}, folder convention is {expect_ds_var!r} (renaming breaks ?var-{name}= links)",
                )
            )
    return out


def check_queries(dashboard: dict[str, Any]) -> list[Finding]:
    """Check queries for the PromQL traps that are decidable from the text.

    Args:
        dashboard: The dashboard object.

    Returns:
        Findings for stepless subqueries.
    """
    out: list[Finding] = []
    for path, panel in iter_panels(dashboard):
        for index, target in enumerate(panel.get("targets") or []):
            if not isinstance(target, dict):
                continue
            expr = target.get("expr") or ""
            if isinstance(expr, str) and (match := STEPLESS_SUBQUERY.search(expr)):
                out.append(
                    Finding(
                        "error",
                        "stepless-subquery",
                        f"{path}.targets[{index}].expr",
                        f"{match.group(0)} re-evaluates at the default step, give it one",
                    )
                )
    return out


def check_language(dashboard: dict[str, Any]) -> list[Finding]:
    """Flag user-facing strings that do not look English.

    Heuristic by design: it surfaces candidates for a human to confirm rather
    than deciding, because a false negative here ships a dashboard an
    international team cannot read.

    Args:
        dashboard: The dashboard object.

    Returns:
        One warning per suspicious string.
    """
    out: list[Finding] = []
    for path, value in iter_text(dashboard):
        if reason := looks_non_english(value):
            out.append(Finding("warn", "language", path, reason))
    return out


def lint(dashboard: dict[str, Any], expect_ds_var: str | None) -> list[Finding]:
    """Run every check against one dashboard.

    Args:
        dashboard: The dashboard object, not the API envelope.
        expect_ds_var: Datasource variable name the folder standardises on.

    Returns:
        Every finding, errors first.
    """
    findings = (
        check_defaults(dashboard)
        + check_panels(dashboard, expect_ds_var)
        + check_variables(dashboard, expect_ds_var)
        + check_queries(dashboard)
        + check_language(dashboard)
    )
    return sorted(findings, key=lambda f: (f.level != "error", f.rule, f.path))


def load_local(path: Path) -> dict[str, Any]:
    """Load a dashboard from a file, accepting the API envelope or the bare object.

    Args:
        path: Path to a JSON file.

    Returns:
        The dashboard object.
    """
    payload = json.loads(path.read_text())
    return payload.get("dashboard", payload)


def ds_var_majority(dashboards: list[tuple[str, dict[str, Any]]]) -> str | None:
    """Return the datasource variable name most dashboards already use.

    Aligning on the majority form matters more than aligning on any given name:
    every rename breaks the `?var-<name>=` in existing bookmarks and tickets.

    Args:
        dashboards: Pairs of (label, dashboard object).

    Returns:
        The most common name, or None when no dashboard has such a variable.
    """
    names = Counter(
        variable.get("name")
        for _, dashboard in dashboards
        for variable in dashboard.get("templating", {}).get("list") or []
        if variable.get("type") == "datasource" and variable.get("name")
    )
    return names.most_common(1)[0][0] if names else None


def build_parser() -> argparse.ArgumentParser:
    """Build the command line parser."""
    parser = argparse.ArgumentParser(
        description=(__doc__ or "").split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Exit code is 1 when at least one error is found. Warnings alone exit 0.",
    )
    parser.add_argument("files", nargs="*", type=Path, help="dashboard JSON files")
    parser.add_argument("--uid", action="append", default=[], help="fetch this dashboard uid, repeatable")
    parser.add_argument("--folder", help="fetch and lint every dashboard in this folder")
    parser.add_argument(
        "--expect-ds-var",
        help="datasource variable name the folder standardises on; with --folder, defaults to the majority form",
    )
    parser.add_argument("--url", help="Grafana base URL [$GRAFANA_URL]")
    parser.add_argument("--token", default="", help="API token; same lookup order as the other Grafana tools")
    parser.add_argument("--mcp-server", default="", help="MCP server in ~/.claude.json to read the token from")
    parser.add_argument("--warnings-as-errors", action="store_true", help="exit 1 on warnings too")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")
    return parser


def collect(args: argparse.Namespace) -> list[tuple[str, dict[str, Any]]]:
    """Gather the dashboards to lint, from files or from the API.

    Args:
        args: Parsed command line arguments.

    Returns:
        Pairs of (label, dashboard object).

    Raises:
        SystemExit: When nothing was selected or credentials are missing.
    """
    out: list[tuple[str, dict[str, Any]]] = [(str(p), load_local(p)) for p in args.files]
    if not args.uid and not args.folder:
        if not out:
            raise SystemExit("nothing to lint: pass a file, --uid or --folder")
        return out

    url = args.url or os.environ.get("GRAFANA_URL", "")
    token = resolve_token(args.token, args.mcp_server)
    if not url or not token:
        raise SystemExit("no Grafana URL or token: set GRAFANA_URL and GRAFANA_TOKEN for --uid/--folder")
    client = Client(url, token)
    uids = list(args.uid)
    if args.folder:
        uids += [
            row["uid"] for row in list_dashboards(client) if row.get("folderTitle") == args.folder
        ]
        if not uids:
            raise SystemExit(f"no dashboard found in folder {args.folder!r}")
    for uid in uids:
        try:
            payload = client.get_json(f"/api/dashboards/uid/{uid}")
        except GrafanaError as exc:
            print(f"warning: {uid} not fetched ({exc})", file=sys.stderr)
            continue
        if payload:
            dashboard = payload["dashboard"]
            out.append((f"{dashboard.get('title', uid)} [{uid}]", dashboard))
    client.close()
    return out


def main(argv: list[str] | None = None) -> int:
    """Lint the selected dashboards.

    Args:
        argv: Command line arguments, defaulting to sys.argv[1:].

    Returns:
        0 when clean, 1 when at least one error was found.
    """
    args = build_parser().parse_args(argv)
    dashboards = collect(args)

    expect = args.expect_ds_var
    if args.folder and not expect:
        expect = ds_var_majority(dashboards)
        if expect:
            print(f"datasource variable: aligning on the majority form {expect!r}\n")

    results = {label: lint(dashboard, expect) for label, dashboard in dashboards}
    errors = sum(1 for f in (x for v in results.values() for x in v) if f.level == "error")
    warnings = sum(1 for f in (x for v in results.values() for x in v) if f.level == "warn")

    if args.json:
        print(
            json.dumps(
                {
                    label: [
                        {"level": f.level, "rule": f.rule, "path": f.path, "detail": f.detail}
                        for f in found
                    ]
                    for label, found in results.items()
                },
                indent=2,
                ensure_ascii=False,
            )
        )
    else:
        for label, found in results.items():
            if not found:
                print(f"OK   {label}")
                continue
            print(f"\n{label}")
            for finding in found:
                mark = "ERROR" if finding.level == "error" else "warn "
                print(f"  {mark} {finding.rule:20} {finding.path}")
                print(f"        {finding.detail}")
        print(f"\n{len(results)} dashboard(s): {errors} error(s), {warnings} warning(s)")

    return 1 if errors or (args.warnings_as_errors and warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
