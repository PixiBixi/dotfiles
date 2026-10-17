# Troubleshooting: symptom index

Find the symptom, apply the fix; the full reasoning is in `panels.md` and `promql.md`.

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
| "Instances up" reads 2 for a single pod; RSS/goroutines inflated | sidecar scraped under the **same `job`** on another port | intersect on a metric only the main process exports (see § One `job` in promql.md) |
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
| Panel of a DaemonSet unreadable, hundreds of lines or tiles | one series per pod on a large fleet | distribution (max / median / min) + `topk($topk, ... @ end())`, see § Fleets in panels.md |
| Top-N panel shows more than N series | `topk` in a range query re-ranks at every step | pin the ranking with `@ end()` |
| Mean line has gaps, the quantile band of the same set is continuous | one pod with a 0 request/limit gives `+Inf`, `avg()` becomes `+Inf` | filter the denominator `> 0` |
| "Request per pod" stat wiggles instead of being flat | `avg()` includes pods Pending/terminating reporting 0 | `quantile(0.5, x > 0)` |
| Pinned top N shows gaps across the range | churning fleet (spot, HPA): the ranked pods did not all live the whole range | per-step `topk`, see § Fleets in panels.md |
| Band does not render on the negated half of a mirrored panel | `fillBelowTo` fills only from the upper series down | put the fill on the series that is upper after negation |
| Restarts legend total too high, fractional values | overlapping `increase(x[5m])` windows at a step < 5m; extrapolation | `[$__interval]` + min interval 5m + `round()` |
| Total series greyed in the legend, cannot be clicked | hidden with `hideFrom.viz` | draw it as an unstacked line + `or on() vector(0)` |
| Tooltip lists every idle pod with a "No ..." text | `noValue` on a multi-series panel | keep `noValue` for stats and single-series panels |
| "Availability" dips on every HPA scale-up | ready ratio counts Pending/Failed pods | rename to ready ratio, or filter phase Running |
| Pre-flight `count()` says `-1`, the metric is right there in the descriptors | `-1` is "no sample now", not "no such metric" | re-run as `count(last_over_time(<metric>[6h]))` |
| "vector cannot contain metrics with the same labelset" on `count_over_time({__name__=~...})` | the range function drops `__name__`, families collide | `label_replace` the name into a label inside a stepped subquery |
| Cache latency climbs steadily, nothing else changed | mean blends roles, or reply size grows | split per role; plot bytes per call next to latency |
