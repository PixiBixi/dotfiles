---
name: charting-grafana-metrics
description: Use when you need a clean PNG chart of Grafana/Prometheus metrics, comparing series (versions, canary vs control, before/after), attaching a graph to a Jira ticket or MR, or when Grafana's server-side panel render is unavailable and `gcx dashboards snapshot` fails (no Image Renderer on that context).
---

# Charting Grafana metrics

## Overview

Renders a dark-themed, Grafana-styled PNG line chart from a PromQL query, fetched through the **Grafana datasource proxy** (so no direct Prometheus network access is needed, the Grafana SA token is enough). Reproducible and scriptable, unlike a manual screenshot. Can attach the result straight to a Jira issue.

**Why this exists:** many Grafana instances lack the *Image Renderer* plugin, so `gcx dashboards snapshot` (its PNG renderer) errors out instead of returning an image. This rebuilds the chart from raw data instead, and also covers what a snapshot never will: a custom side-by-side comparison across queries or time ranges that no single panel encodes.

## Pre-flight
Every Grafana call here goes through `gcx`. Check it once per session:
```bash
command -v gcx >/dev/null || { echo "install: brew install gcx"; exit 1; }
gcx config check || { echo "not ready: gcx login"; exit 1; }
```

**Get the query right before you draw it.** This skill renders whatever PromQL you hand it, and a wrong query is worse here than in a dashboard: the PNG lands in a ticket as frozen evidence nobody replays, and it looks official. **REQUIRED BACKGROUND for the query itself:** use the `grafana-dashboards` skill, sections *PromQL essentials*, *Aggregation traps* and *Reading distributions and tails*. The ones that bite on a comparison chart: aggregate after `rate` and never before, wrap both sides in `max by (...)` when a rollout leaves two series per pod, never `histogram_quantile` a base-2 exponential histogram, and give every subquery an explicit step.

## When to use

- Comparing 2+ series: version A vs B, canary vs control, before/after a change.
- Attaching evidence to a Jira ticket, MR, or incident writeup.
- Grafana panel render fails (`gcx dashboards snapshot` errors: no Image Renderer on that context).

Not for: interactive exploration (use Grafana), or single-value/table data.

## Setup (once)

`matplotlib` is required. If missing, use an isolated venv (don't pollute system Python):

```bash
python3 -m venv ~/.claude/skills/charting-grafana-metrics/.venv
~/.claude/skills/charting-grafana-metrics/.venv/bin/pip install -q matplotlib
```

## Quick reference

| Need | Flag |
|------|------|
| Which datasource | `--datasource-uid` (find via `gcx datasources list` or panel queries) |
| The query | `--expr 'PromQL'` |
| Time window | `--start now-6h --end now --step 60` |
| Series label source | `--legend-key instance` (default; any metric label) |
| Prettier names | `--rename '{"raw-value":"Nice Name"}'` |
| Per-series mean/min/max | printed to stdout after saving (no extra query needed) |
| Callout on the peak | `--annotate-max "text"` |
| Which Grafana | `--grafana-url https://<host>`: uses the gcx context whose server has that host (default: gcx's current context) |
| Which gcx context | `--gcx-context <name>` (default `$GCX_CONTEXT`); for an instance named without a URL, pick it from `gcx config list-contexts` |
| Attach to Jira | `--attach-jira ABC-123` (see the env vars below, and the approval gate in Workflow) |

## Environment

Nothing is hardcoded: no host, no address. Set these in your shell profile.

| Variable | Needed for | Notes |
|----------|-----------|-------|
| `GRAFANA_URL` + `GRAFANA_TOKEN` | static token | the token is only sent to the host of `GRAFANA_URL` (then `GRAFANA_SERVICE_ACCOUNT_TOKEN`, `GTOK`) |
| `GCX_CONTEXT` | gcx | gcx context to force, same as `--gcx-context` |
| `JIRA_API_TOKEN` `JIRA_EMAIL` `JIRA_BASE` | `--attach-jira` only | all three, no default |

Resolution order, identical across every Grafana skill: `--token`; `--gcx-context` / `$GCX_CONTEXT`; `--grafana-url` (the env token for the host of `$GRAFANA_URL`, else the gcx context serving that host, else exit with the `gcx login` to run); gcx's current context; the env token when gcx is missing. Through gcx, its own OAuth refresh applies and this script never reads or caches a credential itself. The resolver is duplicated in each skill on purpose, so either works installed alone.

## Workflow

1. Get the datasource UID + PromQL from the dashboard (`gcx api /api/dashboards/uid/<uid>`, read `panels[*].targets[*].expr`) or write the query yourself.
2. Run the script (via the venv python). Colors auto-assign from the Grafana palette in series order; legend shows mean/max per series.
3. Read the PNG back to eyeball it before sharing.
4. Optionally attach to Jira with `--attach-jira`. It is a tracker write visible to the whole team: follow the approval gate of the `ticket-conventions` skill first (show the ticket id and the PNG, wait for an explicit yes). A failed upload exits non-zero.

## Example (the canonical one: HAProxy 3.2 vs 2.7 node memory)

```bash
VENV=~/.claude/skills/charting-grafana-metrics/.venv/bin/python
SKILL=~/.claude/skills/charting-grafana-metrics
export JIRA_API_TOKEN=$(zsh -l -c 'echo $JIRA_API_TOKEN')   # only if attaching
export JIRA_EMAIL=you@example.com JIRA_BASE=https://example.atlassian.net
DS_UID=abc123XYZ            # from `gcx datasources list`

$VENV $SKILL/plot_grafana.py \
  --datasource-uid $DS_UID \
  --expr '(1 - (node_memory_MemAvailable_bytes{instance=~"lb-edge-dc1-(1|4)"} / node_memory_MemTotal_bytes{instance=~"lb-edge-dc1-(1|4)"})) * 100' \
  --start now-6h --step 60 \
  --title "lb-edge - node memory used %  ·  3.2 vs 2.7 (dc1, last 6h)" \
  --ylabel "Memory used %" --ymin 0 --ymax 45 \
  --rename '{"lb-edge-dc1-1":"HAProxy 3.2.20 (dc1-1)","lb-edge-dc1-4":"HAProxy 2.7.11 (dc1-4, control)"}' \
  --annotate-max "reload: old+new worker coexist → node mem ~2x" \
  --grafana-url https://grafana.example.com \
  --out /tmp/mem-3.2-vs-2.7.png \
  --attach-jira ABC-123
```

## Common mistakes

- **Chart drawn from a query nobody checked** → see the PromQL pointer above; a plausible wrong number is the failure mode, not an error.
- **401 from the proxy** → with a static token, it does not belong to that host; through gcx, the refresh token expired (about monthly), run `gcx login <context>`.
- **Using system `python3`** → `ModuleNotFoundError: matplotlib`. Use the venv python.
- **Empty/one flat line where you expect several** → the `--expr` regex matched a single series; widen the label matcher.
- **Series unnamed / all "series"** → `--legend-key` points at a label the metric doesn't have; pick one it does (check the raw query result).
- **`:9100` (or any `:port`) in legend names** → auto-stripped from the derived series name, so `--rename` targets the clean host (e.g. `lb-edge-dc1-1`, not `lb-edge-dc1-1:9100`). No need to list both forms.
- **Relative times take one number and one unit**, s/m/h/d (`now-90m`, `now-6h`, `now-2d`). Compound (`now-1h30m`), weeks (`now-1w`) and rounding (`now/d`) are not supported: convert them (`now-90m`, `now-7d`).
