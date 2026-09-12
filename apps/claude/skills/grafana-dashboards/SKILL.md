---
name: grafana-dashboards
description: Use when creating or editing a Grafana dashboard or PromQL query against a Thanos or Prometheus datasource, or when a dashboard OOMs the query layer, shows empty/blank panels, has slow template variables, messy tables with stray label columns, or a panel showing a plausible but wrong number (many-to-many during rollouts, per-pod limits summed, quantiles on exponential histograms, tails hidden below p99). Also when an audit has to find every dashboard still reading a given metric, or every dashboard that really reads a given datasource before deleting it. For panels on a Google Cloud Monitoring (stackdriver) datasource, use grafana-cloud-monitoring instead.
---

# Authoring Grafana dashboards and PromQL

Three tools ship next to this file: `lint_dashboard.py` (schema baseline before saving), `grafana_metric_usage.py` (is a metric still read anywhere) and `grafana_datasource_usage.py` (is a datasource still read anywhere). They take the token from `$GRAFANA_TOKEN`, the same chain as the sibling skill. **When the output is evidence for a Jira ticket, an MR or a postmortem rather than a dashboard, use the `charting-grafana-metrics` skill**, which renders a PNG from a query, for the common case of a Grafana without the Image Renderer plugin.

## Language: dashboards are ALWAYS in English
Every user-facing string is English: dashboard title/description, row names, panel titles, panel descriptions, `legendFormat`, value-mapping text, variable labels and descriptions, table column `displayName`. **Even when the conversation is in another language.** Dashboards are shared artifacts read by international teams. Same for alert rule names, summaries and annotations.

Before pushing, grep your generated JSON for leftovers: check every `title`, `description`, `legendFormat`, `displayName` and mapping `text`.

## Dashboard-level defaults
Set these without asking, they are schema baseline, not per-dashboard choices:
- **`graphTooltip: 1` (shared crosshair), ALWAYS.** Never `0` (no sharing), never `2` (shared *tooltip*, unreadable past ~10 panels). These dashboards are read by correlating panels against each other: hovering CPU must move the cursor line on GC, threadpool and network at the same instant. When auditing an existing dashboard, check `$.graphTooltip` and report it compliant rather than assuming it needs changing.
- `timezone: "utc"`, `editable: true`, and a dashboard-level `description` (1-2 sentences: what it is for, who reads it). It is what shows up in Grafana search.
- Panel type `timeseries`/`stat`/`table` only. The `graph` plugin is deprecated; rewrite it when you touch a panel that still uses it.
- **Every panel needs a unique `id`.** JSON authored without them saves with none at all, which silently breaks panel permalinks (`?viewPanel=`) *and* the `panel_id` label in the query-frontend slow log, i.e. it disables the debugging procedure in § Pre-flight on exactly the dashboards you will need it for.
- **One name for the datasource variable, across the whole folder.** Three names for the same thing (`ds`, `datasource`, `Source`) makes dashboard URLs non-transposable and breaks copy-paste between panels. When standardising, align on whatever is already the majority form rather than on what a doc says: every rename breaks the `?var-<name>=` in existing bookmarks and tickets.

## Before you save (run the linter)
The rules above are the ones that get skipped, and it is always on the quick dashboard built in twenty minutes, not on the big investigation one. `lint_dashboard.py`, next to this file, decides them from the JSON and descends into collapsed rows, which a flat `$.panels[*]` read misses:

```bash
./lint_dashboard.py mydash.json          # or --folder "K8S" to sweep one folder
```

Errors exit 1, so it gates a commit. Run `--help` for the flags. Two caveats: its language check is a heuristic that surfaces candidates, so read what it reports rather than trusting the count, and on a folder it aligns the datasource variable on the **majority** form already in use, because every rename breaks the `?var-<name>=` in existing bookmarks.

Two things it cannot decide for you:

**An empty `[]` from a JSONPath is not proof of absence.** It also means "you asked for the wrong shape". `$.panels[*].targets[*].datasource.uid` returns `[]` both when no target carries a datasource *and* when every target carries one as a plain string, the two are indistinguishable. Query the parent (`.datasource`) and look at what comes back before concluding anything is missing.

**`get_dashboard_panel_queries` reads only `expr`, so it is blind to every GCM panel.** A fully migrated Cloud Monitoring dashboard comes back with no queries at all, which reads as "these panels were abandoned" when they are in fact working: the query lives in `promQLQuery.expr` (PromQL mode) or `timeSeriesQuery.query` (MQL mode). Any audit that answers "which dashboards still use metric X" has to read all three paths, and the same holds for a `$.panels[*].targets[*].expr` sweep. Cross-check the target count with `$.panels[*].targets[*].queryType` before reading an empty result as an empty dashboard.

## Is anything still reading this metric?
Before dropping a metric at scrape time, or before deleting a recording rule, prove nothing reads it. `grafana_metric_usage.py`, next to this file, sweeps every dashboard and every Grafana-managed alert rule, reading all three query paths above plus template variables and collapsed rows:

```bash
./grafana_metric_usage.py -m kube_pod_tolerations -v     # -v lists each reference
./grafana_metric_usage.py --regex -f drop-regexes.txt    # feed it the relabel regexes verbatim
```

Exits 1 as soon as one metric is still referenced. Results are cached on disk, so a second run is seconds. Three traps it exists to avoid, all met for real:

- **A substring grep lies in both directions.** `grep container_threads` matches `container_threads_max`, a different family that a chart may already drop. The tool matches whole PromQL identifiers, and skips tokens followed by `(` so a function is never mistaken for a metric.
- **A hit is not a consumer.** Read the datasource the tool prints next to each hit: an unresolved import variable (`${DS_SOMETHING}`) or a uid that no longer resolves means the panel has been dead for years. It attributes each hit to the target's own datasource, not to the dashboard's union.
- **Ask where the data actually comes from.** A metric absent from a filtered global store can still be served by a proxy that queries the per-cluster Prometheus directly, in which case a scrape-time drop removes it from both. Resolve the datasource URL before concluding the blast radius.

## Is anything still reading this datasource?
Same question one level up, before deleting a datasource or leaving one behind in a migration. `grafana_datasource_usage.py` takes a uid **or** a name and shares the dashboard cache with the tool above:

```bash
./grafana_datasource_usage.py -d wfWf8AG4k -v          # list the dashboards that read it
./grafana_datasource_usage.py -d wfWf8AG4k -vv         # also list the selector-only ones
./grafana_datasource_usage.py -d wfWf8AG4k --quiet     # exit 1 while something still reads it
```

**The verdict is the direct / selector split, never the raw hit count.** A `type: datasource` variable selects by plugin type, so every datasource of that type appears in every dashboard carrying such a variable, without anyone having pointed at it. Measured on a 1294-dashboard instance: `GKE cluster ads.txt production` showed up in 294 dashboards and had **1** real consumer. A grep on the uid answers 294 and gets the decision wrong in the expensive direction, which is the datasource-level form of the *a hit is not a consumer* rule above.

So the tool counts a dashboard as a consumer only when the reference sits on a panel, a target, a variable's own query or an annotation. A reference through `"${ds}"` is reported separately as `selector`, and `--count-variable-only` folds it back in if you really want it.

Two things it settles that a manual sweep gets wrong:

- **`current` is not a dependency.** A datasource variable records whatever was selected when the dashboard was last saved, so a uid sitting in `current` proves someone opened the dashboard once, not that anything reads it.
- **Name and uid are both live spellings.** Targets referencing a datasource by name coexist with panels referencing the same one by uid, inside one dashboard. Passing either resolves both.

## Renaming a template variable
Grafana does not rewrite references, so a rename is a manual sweep. Miss one and the panel silently falls back to the default datasource instead of erroring.

- Datasource references come in **two shapes, often mixed inside one dashboard and even inside one panel's targets**: the string `"datasource": "${ds}"` and the object `"datasource": {"type": "prometheus", "uid": "${ds}"}`. The patch path differs (`.datasource` vs `.datasource.uid`), so enumerate both before writing. One 29-panel dashboard held 23 string and 13 object refs at target level alone.
- They live at **three levels**: `$.panels[*].datasource`, `$.panels[*].targets[*].datasource` (by far the most numerous, one per query), and `$.templating.list[*].datasource` on every variable that queries the renamed one. Annotations use the built-in `-- Grafana --` and are not affected.
- Patch operations do **not** support wildcards (`$.panels[*].datasource` fails with *field 'panels' is not an object*), enumerate explicit indices. Map them from `$.panels[*].type`: rows and text panels carry no datasource, so the count of non-row/non-text panels must equal the number of references you found.
- Re-read every level afterwards. The whole patch is atomic, so a failed op changes nothing, but a *successful* partial sweep looks fine until someone opens the dashboard.
- **It breaks existing URLs.** `?var-<oldname>=<uid>` no longer applies, so bookmarks and links pasted in tickets or chat lose their selection and fall back to the default. Say so before doing it.

## Pre-flight (ALWAYS do this first)
Before writing any expr, confirm the metric exists **on the target datasource**:
```promql
count(<metric>) or on() vector(-1)    # -1 = absent on this datasource
```
**`-1` means "no sample right now", not "no such metric".** On a sparse family (GCP quota metrics are the usual case) the bare `count()` returns `-1` on a metric that exists and has data, so wrap the check in the same window the panel will use before concluding the name is wrong: `count(last_over_time(<metric>[6h])) or on() vector(-1)`. To settle name versus absence, go to the descriptors API instead of retrying spellings, see the `grafana-cloud-monitoring` skill.

A panel that is empty on a global Thanos but fine on a per-cluster Prometheus means the metric is filtered out of the global store. Find the culprit query from the frontend's own slow log: `kubectl logs -l app.kubernetes.io/component=query-frontend | grep -i slow` -> `param_query=` + `grafana_dashboard_uid`/`panel_id`.

## A global Thanos is usually a filtered store
When a global Thanos fans out to many per-cluster stacks, two things bite repeatedly: (1) it is a **filtered** store, many raw metrics never arrive there, so check presence before building on them; (2) fan-out multiplied by a bad query OOMs the query pods. Build for both constraints.

**What usually survives to the global:** kube-state-metrics basics (`kube_pod_container_resource_{limits,requests}`, `kube_node_info`, `container_memory_working_set_bytes`) plus whatever you explicitly forward.

**What usually does not**, and costs an afternoon each time you assume otherwise: kube-prometheus's own recording rules (`node_namespace_pod_container:*`), `kube_node_status_capacity`/`allocatable`, `kube_namespace_*`, and the deprecated `*_memory_bytes`/`*_cpu_cores` families. Per-cluster datasources have them, the global does not.

- **Forwarding is opt-in, so a new metric needs a recording rule, not a new panel.** A rule typically reaches the global only if it is explicitly marked for federation (in a kube-prometheus values file, a `federate: "yes"` label on the rule). Ship the rule rather than rewriting panels onto raw metrics that are not forwarded.
- **Ship per-pod ratio recording rules once, then read them everywhere.** Rules named along the lines of `kube_pod_cpu5m_limit_ratio`, `kube_pod_cpu5m_request_ratio`, `kube_pod_memory_limit_ratio`, `kube_pod_memory_request_ratio` (plus per-namespace equivalents) turn every saturation panel into a single cheap read. Take them as **range vectors**, never re-divide in a subquery: `max_over_time(kube_pod_cpu5m_limit_ratio{...}[24h])`.
- **A ratio built on a limit or request is `+Inf` when the denominator is 0** (pod with no limit set). Append `< +Inf` on the `> threshold` tables; `<= X` tables already exclude it.

## Cluster and namespace filtering (anti-OOM, mandatory on a global store)
- **A single-cluster filter bounds the fan-out to one stack**, the main lever against OOM. Always filter on the per-cluster external label, plus the namespace, and exclude what you do not read: `{k8s_cluster_name="$cluster", namespace=~"$namespace", namespace!="kube-system"}`.
- **Check the label name before assuming.** In a Thanos receive setup the per-cluster external label is commonly `k8s_cluster_name` (what the examples here use), while the conventional `cluster` is often **absent** and a verbose internal one such as `receive_prometheus` carries the receiver rather than the cluster. Confirm with `group by (<candidate>) (kube_node_info)` rather than trusting a doc.

## Template variables (fast)
Use `query_result(group by (<label>) (<low-cardinality metric>))` plus a `regex`, NOT `label_values()` (which hits the slow `/series` API on Thanos). Set `refresh: 1` (on load), variable `query.qryType: 3`.
```
cluster:   query_result(group by (k8s_cluster_name) (kube_node_info))
           regex: /k8s_cluster_name="([^"]+)"/
namespace: query_result(group by (namespace) (<a per-pod metric>{k8s_cluster_name="$cluster", namespace!="kube-system"}))
           regex: /namespace="([^"]+)"/
```
Pick the smallest metric that carries the label: `kube_node_info` is ~100 series where a per-container resource-limits metric is ~3300 for the same answer, a 30x difference on a query that runs on every dashboard load.

## Clean tables (the layout that works)
1. Target: `format: table`, `instant: true`.
2. **Wrap the query in `max by (namespace, pod) (...)` AFTER the over_time func** (not inside, which would create a subquery). Without it, `format: table` leaks every external and federation label as a column and pushes the value off-screen. Typically `k8s_cluster_name`, `receive_prometheus`, `dc`, `env`, `prometheus`, `tenant_id`.
3. Transformation `organize`: exclude `Time`, index `namespace`=0 `pod`=1.
4. Override `byType: number`: `displayName`, `unit: percentunit`, `custom.cellOptions: {type: color-background, mode: basic}`, thresholds (green / orange@0.85 / red@0.95).
5. Panel `options.sortBy`: `[{displayName: "<value col>", desc: true}]`. **Not cosmetic:** Prometheus sorts `matrix` results but not instant `vector` results, so an instant table arrives in arbitrary order. Sort in the panel's own transform rather than relying on the query, and note that `sort_by_label()` is blocked on Grafana Cloud tenants.
6. Pin the datasource to the `${ds}` variable, never hardcode a datasource uid. Recurring bug: panels left stuck on one cluster's uid while the rest of the dashboard follows the variable.

## Healthy / empty-state panels
An "absence of problems" query returns empty, so the panel shows **"No data"**, which reads as *broken*, not *healthy*. Force a healthy state:
- **Stat** (a count of OOMKills / errors / down pods): `<expr> or on() vector(0)` plus a value mapping `0` -> green "healthy" text with `colorMode: background`.
- **Table** (a "failing X" list), two traps:
  1. *Detection.* `kube_pod_status_ready{condition="true"} == 0` **misses** pods with no ready series at all (pending / unscheduled / terminating), exactly the `number_unavailable` ones. Use `kube_pod_info{...} unless on(namespace,pod) (kube_pod_status_ready{...,condition="true"} == 1)` which also carries the `node` label.
  2. *Fallback row.* `A or B` is a **union**, so the healthy row would show *alongside* real rows. Gate it on emptiness: `A or (label_replace(vector(0), "col", "healthy", "", "") and on() absent(A))`, nesting `label_replace` once per column to fill several (e.g. `node` + `pod`). Then `cellOptions: color-background`, base threshold red, healthy strings mapped green.
- **Timeseries**, and the fix is NOT the same as for a stat. An event panel needs its `> 0` filter, otherwise it draws dozens of flat lines at zero and nothing is readable; but with the filter, "nothing happened" and "panel broken" both render as an empty graph. Keep the filter and make zero legible on the **display** side instead: `fieldConfig.defaults.min: 0`, `tooltip.hideZeros: false`, and a table legend carrying `calcs: ["sum"]` so each series shows a total. A legend row reading 0 is unambiguous; an absent legend is not.

Every recipe above leans on `absent()` or `vector()`, so **none of them port to a query language that has neither**, MQL included. There the healthy state has to come from the panel: `fieldConfig.defaults.noValue` with the text that says it is fine (`"No quota above 80%"`). Same effect, and it is the only option, so do not spend time looking for the query-side trick (see `grafana-cloud-monitoring`).

## PromQL essentials
- **rate/increase need a range >= 4x scrape** (use `[5m]` min). `rate` for dashboards/alerts; `increase` for totals; `irate` only for spike detail, **never for alerting**.
- **Aggregate AFTER rate**: `sum(rate(x[5m])) by (l)`, never `rate(sum(...))` which breaks counter monotonicity.
- Histograms: keep `by (le)` in the inner `sum(rate(..._bucket[5m]))` or you get NaN.
- Ratios: guard division by zero with `... / (sum(...) > 0)`.
- **Subqueries: never stepless.** `[24h:]` re-evaluates the inner query at the default ~1m step (1440 times); write `[24h:5m]`, or better, read a pre-recorded series as a range vector.
- High cardinality: never put pod UIDs, request IDs or emails in labels.

## Aggregation traps (these return a plausible wrong number, not an error)
- **Dividing two series that both roll.** During a pod rollout the departing series is still inside its 5-minute staleness window while its replacement already reports, so there are two series for one `(namespace, pod)` and the division fails with many-to-many. Wrap **both sides** in `max by (namespace, pod) (...)`; that guarantees one series per key on each side. Required, not cosmetic.
- **A limit enforced per pod is read with MAX across pods, never SUM.** A per-pod setting such as `--store.grpc.series-max-concurrency` summed over a namespace reads 300 while no single pod is near its cap. Same for cache fill: a stack aggregating to 75% can have its hottest pod pinned at 100% and evicting. The aggregate view answers "over/under-provisioned", MAX-per-pod answers "is it about to die"; label the panel with which one it is.
- **Draw a ceiling from the metric that exports it, never from a literal.** A reference line built on the exported `*_max` metric (e.g. `thanos_bucket_store_series_gate_queries_max`) follows the configured value; a hardcoded `100` keeps drawing 100 after someone halves the setting to 50, and the panel lies with no visible symptom.
- **A ratio over a window is a ratio of sums, never a mean of per-step ratios.** `sum(successes) / sum(total)` over the window is the availability; a stat panel computing `avg(rate(sum[$__rate_interval]) / rate(count[$__rate_interval]))` and reducing with `mean` weights every step equally whatever number of executions it contained, which is a different quantity. The useful corollary: with evenly occupied buckets the two agree *exactly*, so a visible gap between them is evidence of something else, usually an inflated denominator, and not of clustering.
- **Reduce an `increase(x[$__range])` panel with `lastNotNull`, never `mean`.** In a range query every step looks back a full dashboard range, so averaging blends windows that predate the event you are looking at. The last non-null point is the only one that means what the panel title claims.
- **Deduplicate node-identity metrics before joining.** `node_uname_info` and friends outlive node-IP reuse across a migration, giving many-to-many or, worse, silent mis-attribution to the wrong node. `topk by (instance)` first.

## Reading distributions and tails
- **Never `histogram_quantile()` a base-2 exponential histogram.** With buckets at 1, 2, 4 ... 512, the function interpolates *inside* a wide bucket and emits a smooth constant that looks like a signal: every stack reading the same ~7.87 at once is an artifact. Plot the raw buckets as a **heatmap** (`le` on the y-axis, rate as colour) and read the real distribution.
- **Read the tail, not p99.** If the slow population is ~0.1% of traffic, p99 is computed over the fast 99% and *structurally cannot see it*. Measured on a Thanos fan-out: p99 0.12-0.19s versus p9999 5.3s, a factor of 30 hidden below p99. Plot p99/p999/p9999 together, and remember a fan-out querier waits for its slowest branch, so user-visible latency is the tail of the widest fan-out.
- **An instant `increase(<counter>[2h])` is one arbitrary sample.** It badly understates anything bursty. For a sizing figure, take a percentile of the rolling window across >= 24h with an explicit subquery step (`[24h:30m]`), never a single instant read.

## Absence is not zero
Three different failures all render as an empty panel, distinguish them before concluding:
- **A counter with no sample until its first event.** Some exporters ship nothing while the counter is zero (e.g. `dragonfly_evicted_keys_total`), so "no data" reads as healthy *and* as broken. Judge via a proxy that always has a value (used versus maxmemory), or force a healthy state per § Healthy / empty-state panels.
- **A metric only one component exports.** `thanos_store_api_query_duration_seconds` exists on the global querier only, so any panel filtering it per stack returns nothing forever. Run the § Pre-flight `count()` check *with the panel's own label filters applied*, not just on the bare metric name.
- **`kube_pod_container_status_restarts_total` does NOT count pod recreation.** It counts container restarts *inside an existing pod*. A recreated pod is a new object whose counter starts at zero, so `increase()` reads nothing while pods churn every few minutes. This produces a **false and reassuring** answer, the worst kind: a panel titled "restarts" shows zero during exactly the event it exists to catch, a fleet-wide rollout. Count pod age instead, which catches both cases:
```promql
count by (namespace) (time() - kube_pod_start_time{pod=~"<sts>.*"} < 3600)
```
The same trap bites `max_over_time(<metric>{pod="X"}[24h])` returning two series for one pod name: a recreated pod carries a different `instance`, so the "pod" is two objects over the window.

## Caching note
The Thanos query-frontend response cache (memcached, or Dragonfly speaking the memcached protocol) caches **`query_range` only**, **instant queries (`/api/v1/query`) are never cached**. So a heavy table panel (instant) will not benefit from the cache; reduce its cost via the cluster filter and range-vector recording rules instead. Note that `dragonfly_evicted_keys_total` ships nothing until its first eviction, so an empty panel there is not proof the cache is not evicting, see § Absence is not zero.

## Google Cloud Monitoring datasources
A panel on the `cloud-monitoring` datasource (plugin type `stackdriver`), in PromQL or MQL mode, is covered by the **`grafana-cloud-monitoring`** skill: metric name conversion, the `migrateQuery` rewrite that empties a JSON-authored panel, `monitored_resource`, MQL tables, and the pre-flight that does not go through the Grafana MCP.

Two things worth knowing from here: a GCM datasource cannot serve `label_values()`, so migrating panels onto it kills the dashboard's `type: query` variables, and `get_dashboard_panel_queries` reads only `expr`, so a GCM dashboard looks queryless to an audit.

## Common mistakes
| Symptom | Cause | Fix |
|---|---|---|
| Panel empty on the global store, OK on per-cluster | metric filtered out of the global | use a forwarded recording rule (or ship the metric) |
| Query pods OOMKilled on dashboard load | fan-out x stepless subquery x no cluster filter | cluster filter + `[24h:5m]` / range-vector RR |
| Table has 10+ stray columns | raw RR in `format: table` leaks external labels | wrap in `max by (namespace, pod) (...)` |
| Template variables slow | `label_values()` on a huge metric via `/series` | `query_result(group by ...)` on a low-card metric |
| `+Inf` rows on top of a "> 85%" table | pod has no limit (division by zero) | append `< +Inf` |
| Panel shows "No data" when everything is healthy | empty result reads as broken | stat: `... or vector(0)` + map 0 to green; table: `absent()`-gated fallback row |
| "Down pods" table misses pending/unavailable pods | `ready==0` skips pods with no ready series | `kube_pod_info unless on(namespace,pod) (ready==1)` |
| Healthy fallback row shows next to real problem rows | `A or B` is a union | gate: `A or (fallback and on() absent(A))` |
| "Instances up" reads 2 for a single pod; RSS/goroutines inflated | sidecar scraped under the **same `job`** on another port | intersect on a metric only the main process exports (see below) |
| Ratio panel throws many-to-many, but only during a deploy | rollout staleness: 2 series for one `(namespace, pod)` | `max by (namespace, pod)` on **both** sides |
| Saturation graph sits far below the cap, yet pods get OOMKilled | a per-pod limit summed across the namespace's pods | MAX across pods, not SUM |
| Reference line still shows the old limit after a config change | ceiling hardcoded as a literal | read the exported `*_max` metric |
| Quantile line is a smooth constant, identical on every stack | `histogram_quantile` interpolating inside a base-2 bucket | heatmap of the raw `le` buckets |
| A totals panel drifts from the same figure computed by hand | `increase(x[$__range])` reduced with `mean` blends overlapping windows | reduce with `lastNotNull` |
| Latency panel looks healthy, users report 20s queries | slow population ~0.1%, invisible below p99 | plot p999 / p9999 too |
| Panel empty forever once filtered per stack | metric exported by one component only | pre-flight `count()` **with the panel's own filters** |
| Panels query the default datasource after a variable rename | reference missed at `targets` level (most numerous) | sweep all 3 levels, then re-read |
| JSONPath audit says a field is absent, it is actually everywhere | queried `.datasource.uid` on string-shaped refs | query the parent and inspect the shape |
| Event timeseries empty and unreadable when nothing happened | `> 0` drops every series, so no legend and no value | keep the filter; `min: 0` + `hideZeros: false` + table legend with `sum` |
| "0 restarts" while pods visibly churn | `restarts_total` ignores **recreated** pods | count pod age: `time() - kube_pod_start_time < window` |
| A cap or limit line is drawn as a filled area | the override sets `lineStyle`/`color` but inherits the panel's `fillOpacity` | add `custom.fillOpacity: 0` to that override, a ceiling is a reference, not a quantity |
| Pre-flight `count()` says `-1`, the metric is right there in the descriptors | `-1` is "no sample now", not "no such metric" | re-run as `count(last_over_time(<metric>[6h]))` |

## One `job` can cover several containers
A ServiceMonitor with several ports scrapes **every** port under one `job`, so a sidecar becomes an extra `instance`. kube-prometheus-stack does exactly this for Prometheus: `http-web:9090` (prometheus) **and** `reloader-web:8080` (config-reloader), same `job`, same `pod`.

Both containers are Go binaries, so both export `up`, `process_*` and `go_*`. `count(up{job=...} == 1)` returns 2 for one pod, and `sum(process_resident_memory_bytes{job=...})` adds the sidecar's RSS to Prometheus's.

Filtering on `container`/`endpoint` is not portable (names differ per distribution). Intersect on a metric only the main process exports:
```promql
count(up{job="$job"} == 1 and on(instance, job) prometheus_build_info) or on() vector(0)
sum(process_resident_memory_bytes{job="$job"} and on(instance, job) prometheus_build_info)
sum(rate(process_cpu_seconds_total{job="$job"}[5m]) and on(instance, job) prometheus_build_info)
```
`and` is a set intersection: the extra labels on `prometheus_build_info` (version, branch...) do not need a one-to-one match. Application-prefixed metrics (`prometheus_*`, `thanos_*`, `haproxy_*`) are already safe, only the **generic** `up` / `process_*` / `go_*` need this.
