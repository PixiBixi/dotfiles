# Common dashboard set for a component folder

One folder per platform component (Thanos, Loki, ArgoCD...), holding the same five kinds of dashboard. A reader who knows one folder knows them all, and the question they arrive with maps to one title prefix. Reference implementation: the `Thanos` folder (`thanos-start-here`, `thanos-sla`, `thanos-mtc-*`, `thanos-*-sizing`).

## Titles, uids, tags

| Kind | Title | uid | Tags |
|------|-------|-----|------|
| Entry point | `<Comp> / 0 Start here` | `<comp>-start-here` | `<comp>`, `index` |
| Service levels | `<Comp> / 1 SLA` | `<comp>-sla` | `<comp>`, `sla`, `slo` |
| Operations | `<Comp> / Ops / <sub-component>` | `<comp>-<sub>` | `<comp>`, `<sub>` |
| Sizing / FinOps | `<Comp> / Sizing / <resource>` | `<comp>-<resource>-sizing` | `<comp>`, `finops`, `sizing` |
| Investigation | `<Comp> / Deep dive / <topic>` | `<comp>-<topic>` | `<comp>`, the ticket key (`PE-1622`) |

- The `0` / `1` prefixes pin the two entry dashboards to the top of the alphabetical folder listing. Everything else sorts by kind.
- **Set a readable uid on creation.** It is in every `/d/` link, alert annotation and ticket, and changing it later breaks all of them. A Grafana-generated uid (`ffqoyj6rjglj4b`) is never acceptable on a new dashboard.
- Cross-link in descriptions with `/d/<uid>`, never with the title: titles get renamed, uids do not.

## Variables, identical in every dashboard of the folder

| Name | Type | Notes |
|------|------|-------|
| `ds` | datasource | Primary store. A second one is `ds<Purpose>` (`dsTooling`), never a new spelling |
| `cluster` | query | `query_result(group by (k8s_cluster_name) (kube_node_info))`, see § Template variables in SKILL.md |
| `namespace` | query | Label it after what a namespace means for the component (`Stack`, `Tenant`) but keep the name |
| `interval` | interval | Rate window, only where rates are drawn |

Same name, same query, same label everywhere, so `?var-cluster=X` can be carried from one dashboard to the next. Grafana dashboard links with `includeVars: true` depend on it.

## What each kind contains

**0 Start here**: answers "is anything broken right now, and where do I look". No investigation panel.
- A health strip of 4-6 `stat` panels, one per failure mode that pages someone, each forced to a green healthy state (§ Healthy / empty-state panels). Each description ends with `Detail in Ops / <x>.`
- A `text` panel "Which dashboard answers your question": one line per dashboard of the folder, question then link.
- A `text` panel "What is not measured": the blind spots, so nobody reads silence as health.
- One headline SLO stat linking to `1 SLA`. Range `now-6h`, refresh `5m`.

**1 SLA**: the promises the component makes, one per user-visible path (write gets in, read answers, read answers in time, data survives).
- Objectives, SLO window and latency threshold are **`custom` variables**, so a target can be argued with without editing a panel. A latency threshold must be one of the histogram's bucket boundaries, so offer only those.
- Rows in this order: top-line SLIs (stat), `Error budget` (gauge, remaining fraction), `Burn rate` (1h and 6h windows, break-even line computed from the SLO variable), `What is spending the budget` (errors by source), `Completeness` (a sender that goes silent is data loss at 100% success, and no availability SLI sees it).
- Ratios over the window are ratios of sums (§ Aggregation traps). Range `now-7d`.

**Ops / \<sub-component\>**: the on-call view, one per sub-component with its own failure modes.
- Health strip first, then a fleet `table` (one row per instance or stack, so the broken one is found in one glance), then one row per path (write, read, storage), then `Resources` last.
- `cluster` / `namespace` selectors drive every panel below the table. Range `now-6h`, refresh `1m`.
- Latency panels plot up to p999 (§ Reading distributions and tails). Resources read the federated ratio rules as MAX per stack and point at `Sizing` for request versus usage.

**Sizing / \<resource\>**: answers "is it over- or under-provisioned", read over 7d-14d rather than the default range.
- Tables of what each pod reached over the range next to what it is provisioned with. CPU at p999 **and** peak (bursty idle pods hide the burst below p999), RAM at the peak only (a memory limit exceeded for one second is an OOMKill).
- RAM peaks read raw cAdvisor, not a 5-minute recording rule that misses transients. CPU against the request when pods carry no CPU limit.

**Deep dive / \<topic\>**: built for one investigation, tagged with its ticket.
- The ticket tag is what lets the next audit decide whether it is still needed. Once the ticket is closed, either promote the panels that proved useful into `Ops` or `Sizing`, or delete the dashboard.
- Descriptions may carry the measurements that motivated a panel; the other kinds stay terse.

## Starting a new component folder

1. Create `0 Start here` and one `Ops` dashboard first; `1 SLA` once objectives are agreed, `Sizing` when a FinOps question comes up. Do not create empty placeholders.
2. Copy the variables block from an existing dashboard of the reference folder rather than re-typing it.
3. Run `lint_dashboard.py --folder "<Comp>"`: the `title-format`, `component-tag`, `readable-uid`, `deep-dive-ticket` and `folder-start-here` warnings check this layout.
