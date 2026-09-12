---
name: grafana-cloud-monitoring
description: Use when a Grafana panel queries Google Cloud Monitoring (the cloud-monitoring datasource, plugin type stackdriver), in PromQL or native MQL mode, or when migrating panels off a stackdriver-exporter onto it. Covers a GCM panel reading No data or falling back to the Builder query type, errors on monitored_resource, resource_container or a JSON parse that is really a 403, converting a Cloud Monitoring metric type or a GMP metric to its PromQL name, a table that lost its label columns, quota metrics that read empty because they publish sparsely, and template variables that die because a GCM datasource cannot serve label_values.
---

# Grafana on Google Cloud Monitoring (GCM)

For everything that is not GCM-specific, the `grafana-dashboards` skill owns it: panel schema baseline, table layout, healthy/empty states, aggregation traps and the audit tools. This file only covers what breaks **because** the datasource is Cloud Monitoring.

Grafana's `cloud-monitoring` datasource (plugin type `stackdriver`) has a PromQL editor that queries Cloud Monitoring's Prometheus-compatible endpoint, so a Prometheus panel can move onto GCP metrics almost verbatim, ratios and `absent()` fallbacks included. `sort_desc`, `label_replace`, `vector()`, `absent()` and `last_over_time` all work. What makes it fail is never the PromQL.

**Metric names.** Take the Cloud Monitoring metric type, turn the first `/` into `:` and every other special character into `_`: `cloudsql.googleapis.com/database/cpu/utilization` -> `cloudsql_googleapis_com:database_cpu_utilization`. Label names are the metric and resource labels, unchanged. Converting off a `stackdriver_exporter`: its name is `stackdriver_<resource_type>_<metric_type>`, so strip `stackdriver_` and the resource-type prefix, then put the `:` back at the first `/` boundary. Do not "fix" a name that looks wrong, `container.googleapis.com/quota/quota/nodes_per_cluster/usage` really does carry `quota` twice.

**The `:` rule does NOT apply to Google Managed Prometheus metrics, and this is the one that wastes an hour.** GMP scrapes are stored under `prometheus.googleapis.com/<name>/<kind>`, but the PromQL endpoint serves them under their **original, bare Prometheus name**. The tell is the exporter's resource type, `prometheus_target`:

| Exporter metric | The `:` rule gives | Actually works |
|---|---|---|
| `stackdriver_prometheus_target_prometheus_googleapis_com_apiserver_request_total_counter` | `prometheus_googleapis_com:apiserver_request_total_counter` -> absent | `apiserver_request_total` |
| `stackdriver_prometheus_target_prometheus_googleapis_com_scheduler_pod_scheduling_sli_duration_seconds_histogram_bucket` | `prometheus_googleapis_com:..._histogram_bucket` -> absent | `scheduler_pod_scheduling_sli_duration_seconds_bucket` |

So: `stackdriver_prometheus_target_*` -> drop the whole `prometheus_googleapis_com` segment and the trailing `_counter` / `_histogram`, keep the plain Prometheus name and its normal `_bucket` / `_count` suffixes. Everything else (`serviceruntime`, `cloudsql`, `compute`, `container`) follows the `:` rule above. Pre-flight both spellings rather than reasoning about it: the wrong one returns `-1`, not an error.

**A JSON-authored target is silently rewritten to the Builder query.** `migrateQuery()` (`grafana/grafana-cloudmonitoring-datasource`, `src/datasource.ts`) short-circuits only when the target already owns one of `metricQuery`, `sloQuery`, `timeSeriesQuery` or `timeSeriesList`. `promQLQuery` is **not** in that list, so a target carrying only `promQLQuery` becomes `queryType: timeSeriesList` with no metric type, and `filterQuery()` then drops it: the panel sends no query at all and reads "No data". It runs from `query()` as well as from the editor, so this bites at render time. Ship a `timeSeriesList` stub alongside, which is what the UI leaves behind anyway:
```json
{
  "queryType": "promQL",
  "promQLQuery": { "projectName": "$project", "expr": "...", "step": "1m" },
  "timeSeriesList": {
    "projectName": "$project", "crossSeriesReducer": "REDUCE_NONE",
    "alignmentPeriod": "cloud-monitoring-auto", "perSeriesAligner": "ALIGN_MEAN",
    "filters": [], "groupBys": []
  }
}
```
That asymmetry is why the mode works when clicked together in the UI and not when authored as JSON. `projectName` is interpolated like any string field, so a dashboard variable belongs there.

**PromQL reads one project, never a metrics scope.** The endpoint is `projects/<project>/location/global/prometheus`, and a scoping project returns an empty vector for metrics owned by the projects in its scope. `projectName` must name the project that **owns** the metric, so a dashboard spanning several (cluster quotas in one project, Cloud SQL in another) needs a different `projectName` per panel group, and a project that no variable can derive needs its own hidden `constant` variable. Widening the metrics scope does not help.

**`monitored_resource` is mandatory when a metric maps to several resource types.** Quota metrics are the usual case, and the API **rejects** the query rather than returning empty, which makes this the easy one to diagnose:
```text
must specify a label matcher on the 'monitored_resource' label because multiple
monitored resource types [consumer_quota producer_quota] are possible
```

**New-style resources carry the project as `resource_container`, not `project_id`.** `compute.googleapis.com/Location` and `container.googleapis.com/Cluster` are the ones met on quota metrics; a `project_id` matcher there matches nothing and the panel is empty with no error. Legacy resources (`consumer_quota`, `cloudsql_database`, `gce_instance`) do use `project_id`. Read the labels back before filtering rather than assuming either.

**The editor has no `legendFormat` and no instant/table query**, only Project, the expression and a min step. Two consequences:
- Legends come out as the raw label set. Reduce to a single label in the query (`max by (database_id) (...)`) and add a `renameByRegex` transformation (`.*database_id="([^"]+)".*` -> `$1`). Non-destructive: a display name that does not match is left alone.
- A table panel cannot use `format: table` + `instant`. Folding the range result with a `reduce` transformation in `seriesToRows` mode yields a `Field` column (the label set as text) plus the reducer column, so one column instead of one per label. **Take that fallback only for a throwaway panel.** A table whose point is to be sorted and filtered per label wants the native MQL mode below, which keeps real label columns. Whichever you pick, say it in the panel description.

**Quota metrics publish sparsely.** An instant read of a GCP quota metric is routinely empty while `last_over_time(<metric>[6h])` returns the value. Keep the window, and do not read the empty instant panel as a broken query.

**A 403 arrives as a JSON parse error.** The plugin parses the API error body as a result, so a missing `roles/monitoring.viewer` on the target project surfaces as `ReadString: expects " or n, but found {` with the real `"code": 403` truncated at the end of the tooltip. Read the whole string before touching the query.

**Migrating a dashboard breaks its variables, not just its panels.** A GCM datasource cannot serve `label_values()`, so every `type: query` variable built on the old Prometheus metric dies with the exporter. The panels are the mechanical half. Rebuild the variables as:
- `custom` for a short, stable list (the projects that own the metric). It must be **single-select** wherever it feeds `projectName`, because PromQL and MQL both read one project.
- `textbox` defaulting to `.*` for a label filter. It survives a new label value appearing, where a `custom` list with `includeAll` silently hides it: `All` expands to the hardcoded options only, which is the "panel lies with no visible symptom" failure again.
A regex textbox works unchanged in both languages: `service=~"$service"` in PromQL, `| filter resource.service =~ '$service'` in MQL.

## Native MQL mode, the way out for a table with label columns
Reach for MQL when the PromQL mode's table limitation costs you something real: it returns **labelled frames**, so label columns survive, and it computes several value columns in one query where PromQL needs one target per value plus a `merge`. A usage/limit/ratio table is 3 PromQL targets or 1 MQL target.

Label placement is not guessable, read it off the descriptors: metric labels are `metric.<key>` (from `metricDescriptors`), resource labels are `resource.<key>` (from `monitoredResourceDescriptors/<type>`). For `consumer_quota` that is `metric.quota_metric` against `resource.project_id` / `resource.service` / `resource.location`.

```text
{
  fetch consumer_quota::serviceruntime.googleapis.com/quota/allocation/usage
  | within 6h
  | group_by [resource.project_id, resource.service, resource.location, metric.quota_metric], max(val())
  ;
  fetch consumer_quota::serviceruntime.googleapis.com/quota/limit
  | within 6h
  | group_by [resource.project_id, resource.service, resource.location, metric.quota_metric], min(val())
}
| join
| value [usage: val(0), limit: val(1), ratio: val(0)/val(1)]
| filter resource.service =~ '$service'
| filter ratio > 0.8
```
`{A ; B} | join` pairs the two streams on their common labels, `| value [...]` names the output columns, and `| filter` / `| top 10, ratio` chain after it on those names. Chained `| filter` steps are fine. The `| within 6h` belongs on each `fetch`, not at the end.

The target shape, and note there is **no stub to ship** here: `timeSeriesQuery` *is* in `migrateQuery()`'s short-circuit list, unlike `promQLQuery`.
```json
{
  "queryType": "timeSeriesQuery",
  "timeSeriesQuery": {
    "projectName": "$project_id", "graphPeriod": "disabled", "query": "<MQL>"
  }
}
```
Two things to expect on the panel side:
- **Column names.** Whether Grafana exposes a label as `resource.project_id` or `project_id` is not worth a guess: put **both spellings** in the `organize` transformation's `renameByName`. An unmatched rename is a no-op, so the worst case is a raw column name, never a broken panel. The natural column order MQL returns is already the label order of your `group_by` followed by the `value` columns, so drop `indexByName` rather than fighting it.
- **MQL has no `absent()`**, so none of the healthy-state recipes above port. A `| filter ratio > 0.8` table reads "No data" when everything is fine. Use `fieldConfig.defaults.noValue` on the panel (`"No quota above 80%"`) as the equivalent.

Prove a filter actually filters before trusting an empty panel: run it at a threshold you know is crossed (`> 0.3`) and check rows come back.

## Pre-flight, because the Grafana MCP cannot query this datasource
`query_prometheus` against a `stackdriver` datasource uid returns a bare `404`: the tool builds a Prometheus API path the plugin does not serve. Validate expressions against the Cloud Monitoring API instead. This runs as **your** credentials and not the datasource's service account, so it proves the query and the metric name, never the permissions:
```bash
curl -s -G -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-urlencode 'query=count(<metric>) or on() vector(-1)' \
  "https://monitoring.googleapis.com/v1/projects/<project>/location/global/prometheus/api/v1/query"
```
To settle a metric name, list what the project actually exports, which is faster and safer than any doc:
```bash
curl -s -G -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-urlencode 'filter=metric.type = starts_with("container.googleapis.com/quota")' \
  'https://monitoring.googleapis.com/v3/projects/<project>/metricDescriptors'
```
Use the descriptors API rather than a regex on the name: `__name__=~"..."` is rejected with `=~ is an unsupported matchtype for the __name__ label`.

MQL is a different endpoint, a POST on v3, and it is worth running because the response tells you the column names the panel will get (`labelDescriptors` and `pointDescriptors`):
```bash
curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" -d '{"query": "<MQL>"}' \
  "https://monitoring.googleapis.com/v3/projects/<project>/timeSeries:query"
```

## Common mistakes
| Symptom | Cause | Fix |
|---|---|---|
| GCM panel "No data", editor opens on Query type **Builder** | JSON target carried only `promQLQuery`, `migrateQuery` rewrote it | ship a `timeSeriesList` stub next to `promQLQuery` |
| GCM panel empty, the same expr returns series on another project | `projectName` is a scoping project, PromQL reads one project | point `projectName` at the project owning the metric |
| GCM quota query rejected outright, not empty | metric maps to several monitored resource types | add `monitored_resource="consumer_quota"` |
| GCM quota panel empty with no error at all | filtered on `project_id` for a new-style resource | filter on `resource_container` |
| GCM panel error `ReadString: expects " or n, but found {` | a 403 rendered as a parse failure | grant `roles/monitoring.viewer` to the datasource SA on that project |
| GCP quota stat empty although the quota exists | quota metrics publish sparsely, the instant read is empty | keep `last_over_time(...[6h])` |
| Converted GMP metric absent, other converted names all work | the `:` rule does not apply to `prometheus_target` metrics | use the bare Prometheus name (`apiserver_request_total`) |
| Migrated dashboard's table lost its Project / Service columns | PromQL mode cannot do `format: table`, `reduce` folds labels into one text column | rewrite that panel in native MQL mode |
| MQL table reads "No data" and nothing is actually wrong | MQL has no `absent()`, so no healthy-state fallback | set `fieldConfig.defaults.noValue` on the panel |
| MQL columns come out named `resource.project_id` (or `project_id`) | Grafana's label naming is not guessable | put both spellings in `renameByName`, unmatched renames no-op |
| Audit reports a GCM dashboard as having no queries | `get_dashboard_panel_queries` reads only `expr` | also read `promQLQuery.expr` and `timeSeriesQuery.query` |
| Variables dead after moving panels to GCM | a GCM datasource cannot serve `label_values()` | rebuild as `custom` (single-select for `projectName`) or `textbox` regex |

Every one of these returns a plausible wrong answer or an empty panel rather than an error, which is why they cost hours. The PromQL itself is almost never the problem.
