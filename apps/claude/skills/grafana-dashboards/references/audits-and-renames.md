# Usage audits and variable renames

Read before dropping a metric or a recording rule, deleting a datasource, or renaming a template variable. Set `SKILL=${CLAUDE_SKILL_DIR}` first.

## Is anything still reading this metric?
Before dropping a metric at scrape time, or before deleting a recording rule, prove nothing reads it. `scripts/grafana_metric_usage.py` sweeps every dashboard and every Grafana-managed alert rule, reading all three query paths listed in SKILL.md § Before you save plus template variables and collapsed rows:

```bash
python3 $SKILL/scripts/grafana_metric_usage.py -m kube_pod_tolerations -v     # -v lists each reference
python3 $SKILL/scripts/grafana_metric_usage.py --regex -f drop-regexes.txt    # feed it the relabel regexes verbatim
```

Exits 1 as soon as one metric is still referenced, **2 when the scan is incomplete** (a dashboard, the library panels or the alert rules could not be read): 2 is never UNUSED, rerun or pass `--no-alerts` knowingly. Library panels are scanned, and an exact name read through `{__name__=~"..."}` counts as a hit. Dashboards are cached for 1h (`--refresh` to bypass): the search API carries no version, so a recent edit is only seen once the entry expires. Three traps it exists to avoid, all met for real:

- **A substring grep lies in both directions.** `grep container_threads` matches `container_threads_max`, a different family that a chart may already drop. The tool matches whole PromQL identifiers, and skips tokens followed by `(` so a function is never mistaken for a metric.
- **A hit is not a consumer.** Read the datasource the tool prints next to each hit: an unresolved import variable (`${DS_SOMETHING}`) or a uid that no longer resolves means the panel has been dead for years. It attributes each hit to the target's own datasource, not to the dashboard's union.
- **Ask where the data actually comes from.** A metric absent from a filtered global store can still be served by a proxy that queries the per-cluster Prometheus directly, in which case a scrape-time drop removes it from both. Resolve the datasource URL before concluding the blast radius.

## Is anything still reading this datasource?
Same question one level up, before deleting a datasource or leaving one behind in a migration. `scripts/grafana_datasource_usage.py` takes a uid **or** a name and shares the dashboard cache with the tool above:

```bash
python3 $SKILL/scripts/grafana_datasource_usage.py -d wfWf8AG4k -v          # list the dashboards that read it
python3 $SKILL/scripts/grafana_datasource_usage.py -d wfWf8AG4k -vv         # also list the selector-only ones
python3 $SKILL/scripts/grafana_datasource_usage.py -d wfWf8AG4k --quiet     # exit 1 while something still reads it
```

Exit 2 means no verdict: an unknown `-d` (typo, wrong instance), an unreadable `/api/datasources`, or a dashboard that failed to fetch. Library panels are scanned, and a query panel with no datasource at all counts as reading the instance default.

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
