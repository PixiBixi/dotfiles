---
name: grafana-dashboards
description: Use for ANY Grafana dashboard work, load it BEFORE gcx:create-dashboard or manage-dashboards (generic, they lack the house rules). Triggers - a dashboard URL (`/d/<uid>`) pasted, "dash" or "panel", creating, editing, redesigning or cleaning up a dashboard, PromQL on a Thanos or Prometheus datasource, a dashboard that OOMs the query layer, empty panels, slow template variables, a plausible but wrong number, the folder layout of a component's dashboards, or an audit of every dashboard reading a given metric or datasource. For Google Cloud Monitoring (stackdriver) panels use grafana-cloud-monitoring instead.
---

# Authoring Grafana dashboards and PromQL

**Load order:** this skill first, then `gcx:create-dashboard` when the work is a visual redesign or new panels (its snapshot loop), or `manage-dashboards` for plain get/push. This skill's rules win on conflict.

Three tools ship in `scripts/`: `lint_dashboard.py` (schema baseline before saving), `grafana_metric_usage.py` (is a metric still read anywhere) and `grafana_datasource_usage.py` (is a datasource still read anywhere). The working directory is never this folder, so call them through `SKILL=${CLAUDE_SKILL_DIR}` as in the examples below. They route through `gcx api`, so gcx's own OAuth refresh applies; the target is picked as in § Which instance, the same chain as the sibling skill. **When the output is evidence for a Jira ticket, an MR or a postmortem rather than a dashboard:** on Grafana Cloud, `gcx dashboards snapshot` renders the existing panel to PNG; use the `charting-grafana-metrics` skill for a comparison no panel shows, or on a self-hosted Grafana without the Image Renderer plugin (where the snapshot errors out).

## Workflow: create or edit a dashboard
1. § gcx setup and § Which instance, once per session.
2. § Query pre-flight on every metric you plan to read, on the target datasource.
3. Platform folder: read `references/folder-layout.md`. Apply § Dashboard-level defaults and § Language.
4. Write the panels with `references/panels.md` (tables, fleets, empty-state, template variables) and `references/promql.md` (global Thanos, aggregation and absence traps).
5. § Before you save: run the linter, then push with § Every save carries a version note.

A panel that is empty, slow, OOMs the query layer or shows a plausible but wrong number: start from the symptom table in `references/troubleshooting.md`.

## References
| Task | Read |
|---|---|
| Building panels, tables, fleets, healthy states, template variables | `references/panels.md` |
| PromQL on a global Thanos, aggregation traps, tails, absence, caching, sidecar `job` | `references/promql.md` |
| Is a metric or datasource still read, renaming a template variable | `references/audits-and-renames.md` |
| A symptom on an existing panel | `references/troubleshooting.md` |
| Component folder layout | `references/folder-layout.md` |

## gcx setup
Every Grafana call in this skill's tools goes through `gcx`. Check it once per session:
```bash
command -v gcx >/dev/null || { echo "install: brew install gcx"; exit 1; }
gcx config check || { echo "not ready: gcx login"; exit 1; }
```
If it reports `Auth method: token (environment override)`, rerun with `env -u GRAFANA_TOKEN -u GRAFANA_SERVICE_ACCOUNT_TOKEN -u GRAFANA_URL` before the command: those variables override every context and answer 401 however fresh the OAuth login is. Call gcx and kubectl directly, never through a shell function or a variable (zsh breaks it, and permission rules cannot match it). The tools strip those variables on their own.

## Which instance
| Request | Pass |
|---|---|
| A URL (`https://<host>/d/<uid>`) | `--url https://<host>`: the tool uses the gcx context whose server has that host |
| An instance named without a URL | `gcx config list-contexts`, then `--gcx-context <name>` |
| Neither | nothing: gcx's current context |

`$GRAFANA_TOKEN` (then `$GRAFANA_SERVICE_ACCOUNT_TOKEN`, `$GTOK`) is only sent to the host of `$GRAFANA_URL`, or used when gcx is missing; `--token` forces a static token. A host no gcx context serves exits with the `gcx login` command to run. The dashboard cache is kept per host.

## Query pre-flight (before writing any expr)
Before writing any expr, confirm the metric exists **on the target datasource**:
```promql
count(<metric>) or on() vector(-1)    # -1 = absent on this datasource
```
**`-1` means "no sample right now", not "no such metric".** On a sparse family (GCP quota metrics are the usual case) the bare `count()` returns `-1` on a metric that exists and has data, so wrap the check in the same window the panel will use before concluding the name is wrong: `count(last_over_time(<metric>[6h])) or on() vector(-1)`. To settle name versus absence, go to the descriptors API instead of retrying spellings, see the `grafana-cloud-monitoring` skill.

A panel that is empty on a global Thanos but fine on a per-cluster Prometheus means the metric is filtered out of the global store. Find the culprit query from the frontend's own slow log: `kubectl logs -l app.kubernetes.io/component=query-frontend | grep -i slow` -> `param_query=` + `grafana_dashboard_uid`/`panel_id`.

## Language: dashboards are ALWAYS in English
Every user-facing string is English: dashboard title/description, row names, panel titles, panel descriptions, `legendFormat`, value-mapping text, variable labels and descriptions, table column `displayName`. **Even when the conversation is in another language.** Dashboards are shared artifacts read by international teams. Same for alert rule names, summaries and annotations.

Before pushing, grep your generated JSON for leftovers: check every `title`, `description`, `legendFormat`, `displayName` and mapping `text`.

## Dashboard-level defaults
Set these without asking, they are schema baseline, not per-dashboard choices:
- **`graphTooltip: 1` (shared crosshair), ALWAYS.** Never `0` (no sharing), never `2` (shared *tooltip*, unreadable past ~10 panels). These dashboards are read by correlating panels against each other: hovering CPU must move the cursor line on GC, threadpool and network at the same instant. When auditing an existing dashboard, check `$.graphTooltip` and report it compliant rather than assuming it needs changing.
- `timezone: "utc"`, `editable: true`, and a dashboard-level `description` (1-2 sentences: what it is for, who reads it). It is what shows up in Grafana search.
- Panel type `timeseries`/`stat`/`table` only. The `graph` plugin is deprecated; rewrite it when you touch a panel that still uses it.
- **Every panel needs a unique `id`.** JSON authored without them saves with none at all, which silently breaks panel permalinks (`?viewPanel=`) *and* the `panel_id` label in the query-frontend slow log, i.e. it disables the debugging procedure in § Query pre-flight on exactly the dashboards you will need it for.
- **One name for the datasource variable, across the whole folder.** Three names for the same thing (`ds`, `datasource`, `Source`) makes dashboard URLs non-transposable and breaks copy-paste between panels. When standardising, align on the form more than half the dashboards already carry, even an imported `DS_*` name, rather than on what a doc says: every rename breaks the `?var-<name>=` in existing bookmarks and tickets. A second datasource variable takes the convention as prefix (`dsTooling`), never a new spelling.

## Folder layout (common dashboard set)
A component folder holds the same five kinds of dashboard: `<Comp> / 0 Start here`, `<Comp> / 1 SLA`, `<Comp> / Ops / <x>`, `<Comp> / Sizing / <x>`, `<Comp> / Deep dive / <x>`, with readable uids, the component tag and the same variables everywhere. **Read `references/folder-layout.md` before creating a dashboard in a platform folder**, or before starting a new one: it gives what each kind contains and the variable block.

## Before you save (run the linter)
The rules above are the ones that get skipped, and it is always on the quick dashboard built in twenty minutes, not on the big investigation one. `scripts/lint_dashboard.py` decides them from the JSON, reads v1 dashboards and `dashboard.grafana.app/v2` manifests (`gcx dashboards get -o json`) alike, and descends into collapsed rows, which a flat `$.panels[*]` read misses:

```bash
SKILL=${CLAUDE_SKILL_DIR}
python3 $SKILL/scripts/lint_dashboard.py mydash.json          # or --folder "K8S" to sweep one folder
```

Errors exit 1, so it gates a commit; a `--uid` or folder dashboard it could not fetch exits 2, never a clean 0. The folder-layout rules are warnings only, so legacy folders still pass. Run `--help` for the flags. Two caveats: its language check is a heuristic that surfaces candidates, so read what it reports rather than trusting the count, and on a folder it aligns the datasource variable on the name carried by **more than half** of the dashboards that have one, because every rename breaks the `?var-<name>=` in existing bookmarks. Below that bar the naming check is skipped: a mere plurality is not a convention, pass `--expect-ds-var` to pick one.

Two things it cannot decide for you:

**An empty `[]` from a JSONPath is not proof of absence.** It also means "you asked for the wrong shape". `$.panels[*].targets[*].datasource.uid` returns `[]` both when no target carries a datasource *and* when every target carries one as a plain string, the two are indistinguishable. Query the parent (`.datasource`) and look at what comes back before concluding anything is missing.

**A `$.panels[*].targets[*].expr` sweep is blind to every GCM panel.** A fully migrated Cloud Monitoring dashboard comes back with no queries at all under that path, which reads as "these panels were abandoned" when they are in fact working: the query lives in `promQLQuery.expr` (PromQL mode) or `timeSeriesQuery.query` (MQL mode) instead. Any audit that answers "which dashboards still use metric X" has to read all three paths; `scripts/grafana_metric_usage.py` already does (see `references/audits-and-renames.md`). Cross-check the target count with `$.panels[*].targets[*].queryType` before reading an empty result as an empty dashboard.

**`gcx dashboards get -o json` returns a `dashboard.grafana.app/v2` manifest, where every v1 path is empty.** Check `.apiVersion` first, then read and patch these instead:

| What | v2 path |
|---|---|
| Panels, keyed `panel-<id>` | `.spec.elements[<name>].spec` (`id`, `title`, `description`, `vizConfig`) |
| Queries | `.spec.elements[<name>].spec.data.spec.queries[].spec.query.spec.expr` / `.legendFormat` |
| Rows and positions | `.spec.layout.spec.rows[].spec` (`title`) then `.layout.spec.items[].spec` (`x`, `y`, `width`, `height`, `element.name`) |
| Variables | `.spec.variables[].spec` (`name`, `options`, `current`), type in `.kind` |

A new panel needs both an `elements` entry and a `GridLayoutItem` referencing it; an element no row references is not drawn. Drop `.status` before pushing.

## After a migration or import
Before handing over: lint for negative `gridPos.y`, missing plugin panels and datasource uid remap, and check no panel shows "No data".

## Every save carries a version note
Each write to a dashboard lands in Settings > Versions, and the note is the only record of why it changed. Write it in English, ticket key first (`PE-2210: replace the stop-writes boolean with the headroom to each threshold`). Notes cannot be added afterwards: a version is immutable.

- MCP grafana: the `message` argument of the update call.
- `gcx dashboards update`: set `metadata.annotations["grafana.app/message"]` in the manifest, the command has no flag for it. Without it the version saves with an empty note, and under the gcx token's account rather than yours.

```bash
jq --arg m "PE-XXXX: <what changed>" 'del(.status) | .metadata.annotations["grafana.app/message"] = $m' dash.json > push.json
gcx dashboards update <uid> -f push.json
```

A `409 Conflict` means the manifest's `resourceVersion` predates another save: re-`get` right before each push and patch that copy, never rebuild from an older fetch.

## Google Cloud Monitoring datasources
A panel on the `cloud-monitoring` datasource (plugin type `stackdriver`), in PromQL or MQL mode, is covered by the **`grafana-cloud-monitoring`** skill: metric name conversion, the `migrateQuery` rewrite that empties a JSON-authored panel, `monitored_resource`, MQL tables, and the pre-flight query validation via `gcx datasources cloudmonitoring query`.

Two things worth knowing from here: a GCM datasource cannot serve `label_values()`, so migrating panels onto it kills the dashboard's `type: query` variables, and a bare `expr` sweep reads only PromQL-mode targets, so a GCM dashboard in MQL mode looks queryless unless `promQLQuery.expr` and `timeSeriesQuery.query` are also read (see § Before you save above).
