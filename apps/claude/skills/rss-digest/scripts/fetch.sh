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
curl -fsS --max-time 60 "${BASE_URL}/api/articles?days=${DAYS}&limit=0" -o "${RAW}"

if ! jq -e '.articles | type == "array"' "${RAW}" > /dev/null; then
    echo "unexpected payload in ${RAW}" >&2
    exit 1
fi

# score, feed, date, title, url, first 300 chars of the plain-text summary
jq -r '.articles
  | map(select(._read == false))
  | unique_by(.title)
  | sort_by(-.score)[]
  | [ (.score | floor), .feed_title, (.published | todate[0:10]), .title, .url,
      ((.summary // "") | gsub("<[^>]+>"; "") | gsub("\\s+"; " ") | .[0:300]) ]
  | @tsv' "${RAW}" > "${COMPACT}"

count=$(wc -l < "${COMPACT}")
echo "unread: ${count// /}  raw: ${RAW}  compact: ${COMPACT}"
echo "per feed:"
cut -f2 "${COMPACT}" | sort | uniq -c | sort -rn | head -15
