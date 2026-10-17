# PromQL on a global Thanos

## Contents
- A global Thanos is usually a filtered store
- Cluster and namespace filtering
- PromQL essentials
- Aggregation traps
- Reading distributions and tails
- Absence is not zero
- Caching note
- One `job` can cover several containers

## A global Thanos is usually a filtered store
When a global Thanos fans out to many per-cluster stacks, two things bite repeatedly: (1) it is a **filtered** store, many raw metrics never arrive there, so check presence before building on them; (2) fan-out multiplied by a bad query OOMs the query pods. Build for both constraints.

**What usually survives to the global:** kube-state-metrics basics (`kube_pod_container_resource_{limits,requests}`, `kube_node_info`, `container_memory_working_set_bytes`) plus whatever you explicitly forward.

**What usually does not**, and costs an afternoon each time you assume otherwise: kube-prometheus's own recording rules (`node_namespace_pod_container:*`), `kube_node_status_capacity`/`allocatable`, `kube_namespace_*`, and the deprecated `*_memory_bytes`/`*_cpu_cores` families. Per-cluster datasources have them, the global does not.

- **Forwarding is opt-in, so a new metric needs a recording rule, not a new panel.** A rule typically reaches the global only if it is explicitly marked for federation (in a kube-prometheus values file, a `federate: "yes"` label on the rule). Ship the rule rather than rewriting panels onto raw metrics that are not forwarded.
- **Ship per-pod ratio recording rules once, then read them everywhere.** Rules named along the lines of `kube_pod_cpu5m_limit_ratio`, `kube_pod_cpu5m_request_ratio`, `kube_pod_memory_limit_ratio`, `kube_pod_memory_request_ratio` (plus per-namespace equivalents) turn every saturation panel into a single cheap read. Take them as **range vectors**, never re-divide in a subquery: `max_over_time(kube_pod_cpu5m_limit_ratio{...}[24h])`.
- **A ratio built on a limit or request is `+Inf` when the denominator is 0** (pod with no limit set). Append `< +Inf` on the `> threshold` tables; `<= X` tables already exclude it.
- **Per-pod request/limit series can read 0 for pods Pending or terminating**, not only for pods without a limit: 74 pods at once on one HPA fleet. One `+Inf` makes `avg()` `+Inf`, which Grafana does not draw, so the mean line goes blank while quantiles of the same set stay continuous. Filter the denominator itself: `/ on(namespace, pod) (max by (namespace, pod) (limit) > 0 or max by (namespace, pod) (request) > 0)`. A "request per pod" stat is `quantile(0.5, request > 0)`, never `avg(request)`, which dips with the fleet churn. `sum()` is unaffected.
- **HPA utilization is against the request, never the limit.** A usage/limit panel cannot tell whether the HPA holds its target: read `kube_hpa_utilization` against `kube_hpa_utilization_target` (older kube-state-metrics names, still what a global store may carry; check `count by (__name__) ({__name__=~".*hpa.*"})` before assuming `kube_horizontalpodautoscaler_*`).

## Cluster and namespace filtering (anti-OOM, mandatory on a global store)
- **A single-cluster filter bounds the fan-out to one stack**, the main lever against OOM. Always filter on the per-cluster external label, plus the namespace, and exclude what you do not read: `{k8s_cluster_name="$cluster", namespace=~"$namespace", namespace!="kube-system"}`.
- **Check the label name before assuming.** In a Thanos receive setup the per-cluster external label is commonly `k8s_cluster_name` (what the examples here use), while the conventional `cluster` is often **absent** and a verbose internal one such as `receive_prometheus` carries the receiver rather than the cluster. Confirm with `group by (<candidate>) (kube_node_info)` rather than trusting a doc.

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
- **A legend `sum` over `increase(x[5m])` double counts when the step is shorter than 5m**: consecutive windows overlap. Use `increase(x[$__interval])` with the panel's min interval at `5m`, so window = step, and `round()` for integer events (restarts), since `increase()` extrapolates to fractions.
- **Deduplicate node-identity metrics before joining.** `node_uname_info` and friends outlive node-IP reuse across a migration, giving many-to-many or, worse, silent mis-attribution to the wrong node. `topk by (instance)` first.
- **A range function over a `{__name__=~"..."}` selector fails with "vector cannot contain metrics with the same labelset".** `count_over_time`, `changes`, `rate` drop `__name__`, so two metrics sharing their other labels (every `_bucket` family on one target) collide. Copy the name into a plain label first, through a subquery with an explicit step: `changes(label_replace({__name__=~".+_bucket"}, "mn", "$1", "__name__", "(.+)")[10m:30s])`. When counting series is enough, `count({__name__=~"..."})` needs no workaround. Run it per tenant querier, never on a global fan-out.
- **A mean latency per command across pods with different roles is a weighted blend, not a latency.** `sum by (cmd) (rate(duration)) / sum by (cmd) (rate(count))` over a Dragonfly fleet mixed store-gateway index caches (~15 us MGET) with the query-frontend response cache (~15 ms MGET returning multi-MB results): at 8x fewer calls the slow pod still drove the curve, which looked like a degradation. Split the panel per role, and read a cache's latency next to its bytes per call, which it tracks almost exactly (about 1 us per KiB).

## Reading distributions and tails
- **Never `histogram_quantile()` a base-2 exponential histogram.** With buckets at 1, 2, 4 ... 512, the function interpolates *inside* a wide bucket and emits a smooth constant that looks like a signal: every stack reading the same ~7.87 at once is an artifact. Plot the raw buckets as a **heatmap** (`le` on the y-axis, rate as colour) and read the real distribution.
- **Read the tail, not p99.** If the slow population is ~0.1% of traffic, p99 is computed over the fast 99% and *structurally cannot see it*. Measured on a Thanos fan-out: p99 0.12-0.19s versus p9999 5.3s, a factor of 30 hidden below p99. Plot p99/p999/p9999 together, and remember a fan-out querier waits for its slowest branch, so user-visible latency is the tail of the widest fan-out.
- **An instant `increase(<counter>[2h])` is one arbitrary sample.** It badly understates anything bursty. For a sizing figure, take a percentile of the rolling window across >= 24h with an explicit subquery step (`[24h:30m]`), never a single instant read.

## Absence is not zero
Three different failures all render as an empty panel, distinguish them before concluding:
- **A counter with no sample until its first event.** Some exporters ship nothing while the counter is zero (e.g. `dragonfly_evicted_keys_total`), so "no data" reads as healthy *and* as broken. Judge via a proxy that always has a value (used versus maxmemory), or force a healthy state per § Healthy / empty-state panels in panels.md.
- **A metric only one component exports.** `thanos_store_api_query_duration_seconds` exists on the global querier only, so any panel filtering it per stack returns nothing forever. Run the § Query pre-flight in SKILL.md `count()` check *with the panel's own label filters applied*, not just on the bare metric name.
- **`kube_pod_container_status_restarts_total` does NOT count pod recreation.** It counts container restarts *inside an existing pod*. A recreated pod is a new object whose counter starts at zero, so `increase()` reads nothing while pods churn every few minutes. This produces a **false and reassuring** answer, the worst kind: a panel titled "restarts" shows zero during exactly the event it exists to catch, a fleet-wide rollout. Count pod age instead, which catches both cases:
```promql
count by (namespace) (time() - kube_pod_start_time{pod=~"<sts>.*"} < 3600)
```
**A ready ratio is not an availability.** `kube_pod_status_ready{condition="true"}` over all pods counts Pending, starting and Failed pods (spot preemptions leave Failed pods until GC) as not ready, so on an HPA or spot fleet the dips follow pod churn: 0 not-ready pods when at most 5 pods were new, 6.8 on average when more than 30 were. Title it "Ready pods ratio" and say so, or restrict the denominator to `kube_pod_status_phase{phase="Running"} == 1`.

The same trap bites `max_over_time(<metric>{pod="X"}[24h])` returning two series for one pod name: a recreated pod carries a different `instance`, so the "pod" is two objects over the window.

## Caching note
The Thanos query-frontend response cache (memcached, or Dragonfly speaking the memcached protocol) caches **`query_range` only**, **instant queries (`/api/v1/query`) are never cached**. So a heavy table panel (instant) will not benefit from the cache; reduce its cost via the cluster filter and range-vector recording rules instead. Note that `dragonfly_evicted_keys_total` ships nothing until its first eviction, so an empty panel there is not proof the cache is not evicting, see § Absence is not zero.

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
