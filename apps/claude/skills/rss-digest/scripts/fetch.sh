#!/usr/bin/env bash
# Fetch unread FreshRSS Summary articles and write a compact projection for triage.
# Usage: fetch.sh <out_dir> [days=30]
set -euo pipefail

OUT_DIR="${1:?usage: fetch.sh <out_dir> [days]}"
DAYS="${2:-30}"
BASE_URL="${RSS_DIGEST_URL:-https://summary.jdelgado.fr}"
RAW="${OUT_DIR}/articles.json"
COMPACT="${OUT_DIR}/compact.tsv"

mkdir -p "${OUT_DIR}"
# Shaped server-side: anonymous calls only get unread articles, deduped on title
# (best score kept), sorted by score, summary already plain text.
FIELDS="score,feed_title,published,title,url,summary"
curl -fsS --compressed --max-time 60 \
    "${BASE_URL}/api/articles?days=${DAYS}&limit=0&sort=score&dedupe=title&fields=${FIELDS}&summary_chars=300" \
    -o "${RAW}"

if ! jq -e '.articles | type == "array"' "${RAW}" > /dev/null; then
    echo "unexpected payload in ${RAW}" >&2
    exit 1
fi

# score, feed, date, title, url, summary
jq -r '.articles[]
  | [ (.score | floor), .feed_title, (.published | todate[0:10]), .title, .url, (.summary // "") ]
  | @tsv' "${RAW}" > "${COMPACT}"

count=$(wc -l < "${COMPACT}")
echo "unread: ${count// /}  raw: ${RAW}  compact: ${COMPACT}"
echo "per feed:"
cut -f2 "${COMPACT}" | sort | uniq -c | sort -rn | head -15
