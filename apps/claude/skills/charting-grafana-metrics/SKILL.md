---
name: charting-grafana-metrics
description: Use when you need a clean PNG chart of Grafana/Prometheus metrics, comparing series (versions, canary vs control, before/after), attaching a graph to a Jira ticket or MR, or when Grafana's server-side panel render (Image Renderer plugin) is unavailable and get_panel_image returns "No image renderer available".
---

# Charting Grafana metrics

## Overview

Renders a dark-themed, Grafana-styled PNG line chart from a PromQL query, fetched
through the **Grafana datasource proxy** (so no direct Prometheus network access is
needed, the Grafana SA token is enough). Reproducible and scriptable, unlike a
manual screenshot. Can attach the result straight to a Jira issue.

**Why this exists:** many Grafana instances lack the *Image Renderer* plugin, so
`get_panel_image` / `/render/...` return a "No image renderer available" placeholder.
This rebuilds the chart from raw data instead.

## When to use

- Comparing 2+ series: version A vs B, canary vs control, before/after a change.
- Attaching evidence to a Jira ticket, MR, or incident writeup.
- Grafana panel render fails (no Image Renderer plugin).

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
| Which datasource | `--datasource-uid` (find via `list_datasources` or panel queries) |
| The query | `--expr 'PromQL'` |
| Time window | `--start now-6h --end now --step 60` |
| Series label source | `--legend-key instance` (default; any metric label) |
| Prettier names | `--rename '{"raw-value":"Nice Name"}'` |
| Per-series mean/min/max | printed to stdout after saving (no extra query needed) |
| Callout on the peak | `--annotate-max "text"` |
| Which Grafana | `--grafana-url` (default `$GRAFANA_URL`, required) |
| Attach to Jira | `--attach-jira ABC-123` (see the env vars below) |

## Environment

Nothing is hardcoded: no host, no address. Set these in your shell profile.

| Variable | Needed for | Notes |
|----------|-----------|-------|
| `GRAFANA_URL` | every run | base URL, or pass `--grafana-url` |
| `GRAFANA_MCP_SERVER` | token auto-read | MCP server name in `~/.claude.json` (default `grafana`) |
| `GTOK` | optional | Grafana SA token, bypasses the auto-read; or `--token` |
| `JIRA_API_TOKEN` `JIRA_EMAIL` `JIRA_BASE` | `--attach-jira` only | all three, no default |

`GRAFANA_URL` and `GRAFANA_MCP_SERVER` must name the **same** Grafana: the token is
read from the MCP server, so a mismatched pair sends instance A's token to instance
B and the datasource proxy answers 401. With several instances, override both flags
together (`--grafana-url ... --mcp-server ...`), never just one.

Token auto-read order: `--token`, then `GTOK`, then `~/.claude.json`, key
`mcpServers.<GRAFANA_MCP_SERVER>.env.GRAFANA_SERVICE_ACCOUNT_TOKEN` (falls back to
`GRAFANA_API_KEY`).

## Workflow

1. Get the datasource UID + PromQL from the dashboard (`get_dashboard_panel_queries`)
   or write the query yourself.
2. Run the script (via the venv python). Colors auto-assign from the Grafana palette
   in series order; legend shows mean/max per series.
3. Read the PNG back to eyeball it before sharing.
4. Optionally attach to Jira with `--attach-jira`.

## Example (the canonical one: HAProxy 3.2 vs 2.7 node memory)

```bash
VENV=~/.claude/skills/charting-grafana-metrics/.venv/bin/python
SKILL=~/.claude/skills/charting-grafana-metrics
export GRAFANA_URL=https://grafana.example.com
export JIRA_API_TOKEN=$(zsh -l -c 'echo $JIRA_API_TOKEN')   # only if attaching
export JIRA_EMAIL=you@example.com JIRA_BASE=https://example.atlassian.net
DS_UID=abc123XYZ            # from list_datasources

$VENV $SKILL/plot_grafana.py \
  --datasource-uid $DS_UID \
  --expr '(1 - (node_memory_MemAvailable_bytes{instance=~"lb-edge-dc1-(1|4)"} / node_memory_MemTotal_bytes{instance=~"lb-edge-dc1-(1|4)"})) * 100' \
  --start now-6h --step 60 \
  --title "lb-edge - node memory used %  ·  3.2 vs 2.7 (dc1, last 6h)" \
  --ylabel "Memory used %" --ymin 0 --ymax 45 \
  --rename '{"lb-edge-dc1-1":"HAProxy 3.2.20 (dc1-1)","lb-edge-dc1-4":"HAProxy 2.7.11 (dc1-4, control)"}' \
  --annotate-max "reload: old+new worker coexist → node mem ~2x" \
  --out /tmp/mem-3.2-vs-2.7.png \
  --attach-jira ABC-123
```

## Common mistakes

- **401 from the proxy** → SA token missing/wrong. `mcp-grafana` v0.11+ uses
  `GRAFANA_SERVICE_ACCOUNT_TOKEN`, not `GRAFANA_API_KEY` (the script tries both).
- **Using system `python3`** → `ModuleNotFoundError: matplotlib`. Use the venv python.
- **Empty/one flat line where you expect several** → the `--expr` regex matched a
  single series; widen the label matcher.
- **Series unnamed / all "series"** → `--legend-key` points at a label the metric
  doesn't have; pick one it does (check the raw query result).
- **`:9100` (or any `:port`) in legend names** → auto-stripped from the derived
  series name, so `--rename` targets the clean host (e.g. `lb-edge-dc1-1`, not
  `lb-edge-dc1-1:9100`). No need to list both forms.
- **`now-90m` style** not supported: units are s/m/h/d only (e.g. `now-6h`).
