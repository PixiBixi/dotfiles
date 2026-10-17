# Panel recipes

Template variables, tables, fleets and healthy states. Query-side traps are in `promql.md`.

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

## Fleets: the distribution, never one series per member
**Default for any panel whose series are members of one fleet** (pods of a Deployment or DaemonSet, nodes, Aerospike nodes, Cloud SQL replicas), from about 5 members up, not only for huge DaemonSets. One line per pod answers a question nobody asks; the per-member view belongs in the drill-down dashboard. Series that are distinct entities (one per HPA, per tunnel, per destination region) stay one line each.

A DaemonSet on a 1000-node cluster draws 1000 lines per `by (pod)` panel and 1000 tiles per `up` stat: nothing is readable, and a real failure hides in the noise (a wall of 1182 green tiles was hiding 11 pods down). Ask "what does the fleet look like, and who is the outlier", not "what does each pod do":
- **Health**: one stat `count(up{...} == 0) or on() vector(0)` mapped to green "healthy", next to a table of the failing pods (`max by (pod, instance) (up{...} == 0)`, `noValue` saying all pods answer).
- **Resources: max, median, min.** Collapse to one series per member first (`max by (namespace, pod) (...)`, rollout-safe), then `max`, `quantile(0.5, ...)`, `min` across it. The median is the typical member; max drifting from it is one hot member, min drifting is one idle or broken one. Skip p95/p99 below ~50 members: with 30 pods p95 sits between the top two and draws on top of the max. Style: median solid width 2, max and min dashed with `fillOpacity: 0`, fixed colours, keep the request/limit line. When lower is worse (idle time, free memory), say in the description that the min is the one to watch.
- **Mean + spread band, one panel per resource.** A mean line plus a shaded band gives level and dispersion at a glance, and replaces a separate percentile row. Targets `avg(X)` "mean", `quantile(1 - $band, X)` "low", `quantile($band, X)` "high"; `$band` is a `custom` variable (`min-max : 1, 1p-99p : 0.99, 5p-95p : 0.95, 10p-90p : 0.9`, `quantile(0)`/`quantile(1)` being min/max). On "high": `lineWidth: 0`, `fillOpacity: 20`, `fillBelowTo: "low"`; hide low/high from the legend (`hideFrom.legend`), keep them in the tooltip. `fillBelowTo` matches the **display name**, so these legends stay fixed strings, no variable in them.
- **Mirrored receive/transmit panel with bands.** `fillBelowTo` only fills from the upper series down: negate transmit in the query (`-8 * quantile(...)`) and put the fill on "low", which is now the upper one. Legend `calcs` on a negated series: `max` shows the quietest point, use `lastNotNull` + `mean`. Network is read in bits: `8 *` on a bytes metric, unit `bps`.
- **Aggregate `by (namespace)` when the variable is multi-value**, so pods of different workloads never share one distribution.
- **GCM PromQL has no `legendFormat`**: tag each aggregate with `label_replace(max(...), "stat", "max", "", "")` and rename with a `renameByRegex` on `stat="([^"]+)"`.
- **Pin the top N to the end of the range with `@ end()`**: `x and on(pod) topk($topk, max_over_time(x[$__range] @ end()))`. A bare `topk` in a range query re-ranks at every step, so the set of pods changes along the graph and draws more than N series. For a counter, rank on `increase(c[$__range] @ end())`. **Exception, churning fleets (spot, HPA):** pods live a few hours (1139 distinct pods in 24h for ~400 at once), so a pinned top N shows gaps where none of the ranked pods existed, and ranking on `sum_over_time` only rewards survivors. There use a per-step `topk($topk, X)` and say in the description that the legend lists more than N pods over a long range.
- **N is a `custom` variable (3, 5, 10, 20, default 5), not a share of the fleet.** Readability caps at about 10 lines whatever the pod count; scaling N with the fleet (1% of 1182 = 12) brings the unreadable panel back. The pod variable stays for drill-down.
- **Per-member drill-down as a toggle, not a second dashboard.** A `custom` variable `groupby` with options `stack : namespace` (default) and `pod : namespace\, pod`, read as `max by ($groupby) (...)`, with legend `{{stack}} {{pod}}`: the `pod` part renders empty when it is not grouped on. Put `${groupby:text}` in the panel titles, and tell in the variable description to narrow the fleet first (one shard, one stack), since `pod` brings back one line per member.

## Healthy / empty-state panels
An "absence of problems" query returns empty, so the panel shows **"No data"**, which reads as *broken*, not *healthy*. Force a healthy state:
- **Stat** (a count of OOMKills / errors / down pods): `<expr> or on() vector(0)` plus a value mapping `0` -> green "healthy" text with `colorMode: background`.
- **Table** (a "failing X" list), two traps:
  1. *Detection.* `kube_pod_status_ready{condition="true"} == 0` **misses** pods with no ready series at all (pending / unscheduled / terminating), exactly the `number_unavailable` ones. Use `kube_pod_info{...} unless on(namespace,pod) (kube_pod_status_ready{...,condition="true"} == 1)` which also carries the `node` label.
  2. *Fallback row.* `A or B` is a **union**, so the healthy row would show *alongside* real rows. Gate it on emptiness: `A or (label_replace(vector(0), "col", "healthy", "", "") and on() absent(A))`, nesting `label_replace` once per column to fill several (e.g. `node` + `pod`). Then `cellOptions: color-background`, base threshold red, healthy strings mapped green.
- **Timeseries**, and the fix is NOT the same as for a stat. An event panel needs its `> 0` filter, otherwise it draws dozens of flat lines at zero and nothing is readable; but with the filter, "nothing happened" and "panel broken" both render as an empty graph. Keep the filter and make zero legible on the **display** side instead: `fieldConfig.defaults.min: 0`, `tooltip.hideZeros: false`, and a table legend carrying `calcs: ["sum"]` so each series shows a total. A legend row reading 0 is unambiguous; an absent legend is not.
- **A total over stacked per-pod bars is a line, never a series hidden with `hideFrom.viz`**: Grafana greys a series it does not draw and its legend entry can no longer be clicked. Draw the total as a line in its own stacking group (`stacking: {group: "B", mode: "none"}`) with `or on() vector(0)`, otherwise an isolated event is a lone point that no line connects.
- **`noValue` belongs on single-series panels only.** On a multi-series panel it applies to every series with no value at the hovered point, so the tooltip lists every idle pod with the text.

Every recipe above leans on `absent()` or `vector()`, so **none of them port to a query language that has neither**, MQL included. There the healthy state has to come from the panel: `fieldConfig.defaults.noValue` with the text that says it is fine (`"No quota above 80%"`). Same effect, and it is the only option, so do not spend time looking for the query-side trick (see `grafana-cloud-monitoring`).
