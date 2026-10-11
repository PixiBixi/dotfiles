---
name: k8s-rightsizing
description: >
  Use when sizing the CPU/memory requests or limits of a Kubernetes workload from its real
  usage: "on peut réduire cette RAM ?", "rightsize X", "mesure sur 1 semaine", "combien
  consomme <workload>", "il a déjà été OOMKilled ?", "baisse les requests", a FinOps cut on a
  deployment or statefulset. Covers finding the series that hold the usage, the PromQL per
  signal, the recommendation rule and the values change. Not for CI runner or node pool
  sizing, or a live OOM incident.
---

# K8s rightsizing

A recommendation is the peak of real usage over a representative window plus headroom: never the average, never a number read off someone else's dashboard.

## 1. Find the series

Federated or global stores usually drop the raw `container_*` and `kube_pod_container_*` series and keep **recording rules** instead (pod-level CPU rate, memory usage, OOM counters). If the project CLAUDE.md names them, use those first. Otherwise list what exists for the target cluster before any real query: an empty result means wrong series or datasource, not zero usage.

```bash
gcx metrics query -d <uid> 'count by (__name__) ({__name__=~".*(cpu_usage|memory_usage|working_set|oom).*", <cluster_label>="<cluster>"})' -o json --jq '[.data.result[].metric.__name__]'
```

| Need | Source |
|---|---|
| Pod-level usage, single-container pods (most cases) | the recording rules on the global store |
| Per-container split (sidecars), requests, raw OOM reason | the raw or per-cluster datasource |

Check the oldest point before claiming a 30-day window: retention differs per store.

## 2. Measure

Always filter on cluster and namespace (and container on raw series): an unfiltered `[7d]` range over a multi-cluster store can OOM the queriers. Window `[7d]` by default, `[14d]` when the load is weekly-cyclic. Raw series shown; swap in the recording rule names where they exist.

| Signal | PromQL (instant query) |
|---|---|
| Memory peak | `max by (pod, container) (max_over_time(container_memory_working_set_bytes{C,N,X}[7d]))` |
| Memory p99 | `max by (container) (quantile_over_time(0.99, container_memory_working_set_bytes{C,N,X}[7d]))` |
| CPU p95 of the 5m rate | `max by (container) (quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{C,N,X}[5m])[7d:5m]))` (on a rate recording rule, drop the inner `rate`) |
| CPU peak | same with `max_over_time` |
| Current requests / limits | `max by (container, resource) (kube_pod_container_resource_requests{C,N,X})`, same on `..._limits` |
| OOMKills | `max by (pod) (max_over_time(kube_pod_container_status_last_terminated_reason{C,N,X,reason="OOMKilled"}[7d]))` |
| Restarts | `max by (pod) (increase(kube_pod_container_status_restarts_total{C,N,X}[7d]))` |

Live spec for comparison: `kubectl klens reqlim --context <ctx> -n <ns> --by-owner`.

## 3. Recommend

| Value | Default rule (state the factors in the answer; a team standard overrides them) |
|---|---|
| Memory request | p99 working set x 1.15, rounded up to 64Mi |
| Memory limit | max(peak x 1.25, request); equal to the request for a fixed heap (JVM, `GOMEMLIMIT`); never below the window peak |
| CPU request | p95 of the 5m rate x 1.2, rounded to 50m |
| CPU limit | follow the repo (unset stays unset); if set, at least 2 x the request |
| Any OOMKill or memory restart in the window | no memory cut, report it first |
| Under 7 days of data, a recent rollout, or a known peak outside the window | say so, widen the window, or do not recommend |

One table per workload: container (or pod), current req/lim, measured p95/p99/peak, proposed req/lim, monthly delta. First line: environment, window, and whether the numbers are pod- or container-level.

## 4. Ship

Values change in the owning GitOps repo (`mr-open`), then check the rollout. Offer a reminder at +7 days (`tickler`) to re-measure and look for OOMKills.

## Common mistakes

| Mistake | Instead |
|---|---|
| "No data" from raw series on a global store | Look for the recording rules first |
| Pod-level numbers applied to one container of a multi-container pod | Raw per-container series |
| Average or median as the basis | p99 / peak over 7-14 days |
| Cutting memory after an OOMKill | Report it, no cut |
| Unfiltered range over every cluster | cluster + namespace (+ container) matchers |
| A number without its window and env | "prod, 7d to 2026-10-11, pod-level p99 1.8Gi" |
