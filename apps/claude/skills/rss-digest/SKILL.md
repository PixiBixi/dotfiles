---
name: rss-digest
description: Use when asked to catch up on the RSS backlog at summary.jdelgado.fr (FreshRSS Summary) - "ouvre summary.jdelgado.fr", "fais-moi le digest RSS", "j'ai du retard sur mes flux", "les 30 derniers jours", "qu'est-ce que j'ai raté". Fetches unread articles through the site API and re-ranks them against the platform/SRE profile instead of trusting the site score.
---

# RSS digest

The site is a SPA: WebFetch on the homepage returns nothing useful. Go through the API.

## Fetch

```bash
SKILL_DIR=~/.claude/skills/rss-digest/scripts
OUT="<session scratchpad>/rss"
"$SKILL_DIR/fetch.sh" "$OUT" 30     # days, default 30
```

`compact.tsv` columns: score, feed, date, title, url, summary (300 chars). Sorted by site score, unread only, deduplicated on title. Never Read it whole when it exceeds ~300 lines: filter with `rg`/`awk` on the feed or title first.

API (if the script needs changing): `GET /api/articles?days=N&limit=0` returns `{total, articles[]}` with `id, title, url, feed_title, published (epoch), score, matched_topics, matched_keywords, top_topic, summary, bookmarked`. Shape it server-side rather than with jq: `fields=a,b` (projection), `summary_chars=N` (plain text), `dedupe=title`, `min_score`, `feeds=a,b` / `exclude_feeds=a,b` (exact `feed_title`), e.g. `feeds=Cert%20SSI` to pull every advisory regardless of score. Write endpoints (`/api/mark-read`, `/api/bookmark`, `/api/config/scoring`, `/api/rescore`, `/api/snooze`) are never called without an explicit ask.

## The site score is not the ranking

It is keyword density over `matched_topics`, blind to source quality. Beginner listicles from DEV.to and Hacker Moon (~90% of volume) float to the top; CERT-FR advisories and vendor CVEs sit at 1-6. Re-rank by hand:

1. **Security with possible exposure**, any score: CERT-FR (`Cert SSI`), IT Connect / vBlog CVE posts, Ars security. Keep only products we run: GitLab, Atlassian, Linux kernel/KVM, container runtimes, Docker Hub, ingress/proxies, GCP, Kubernetes. Say whether we are exposed (SaaS = patched by vendor) and mark what was not verified.
2. **Deadlines**: Kubernetes or GKE EOL, deprecations, forced upgrades.
3. **GKE / GCP / FinOps**: the `Containers & Kubernetes` (Google Cloud blog) feed is the highest-signal source, read all of it.
4. **Engineering deep dives**: Meta Engineering, Cloudflare (data pipelines, reliability, observability; skip Workers product launches), Percona only for incident-shaped posts.
5. **DEV.to / Hacker Moon**: keep only items naming our stack explicitly (Thanos, ArgoCD, Terragrunt, GKE, Workload Identity, PromQL, cardinality, FinOps on GCP) and written from production, not tutorials.

Everything else (consumer tech, Apple, politics, beginner Kubernetes, "AI incident agent" series) goes in one closing line.

## Profile

Platform/SRE at Equativ (adtech, RTB bidders, high QPS). GCP + GKE fleet (~24 prod clusters), ArgoCD GitOps, Terraform/Terragrunt (`iac-*`), Prometheus + global Thanos + Grafana Cloud, Tempo, Cloudprober, Aerospike, Dragonfly, GitLab CI, Akamai edge, some OVH bare metal (CDYN/Dynadmic). FinOps-first.

## Output

In French. Sections in this order, each a table or short list with a link, the site score and one line of "why it matters here": à traiter (sécu), calendrier, GKE/FinOps, lectures de fond, then one line for the rest. Lead with the backlog size and the source split. Do not mark anything read unless asked.
