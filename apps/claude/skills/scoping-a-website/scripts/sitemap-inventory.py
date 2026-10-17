#!/usr/bin/env python3
"""Group a live site's URLs into page templates, with a count and a sample URL each.

Reads /robots.txt for Sitemap: lines, falls back to /sitemap.xml, follows nested
sitemap indexes. Without any sitemap, crawls the home page links (nav and footer).

Usage: sitemap-inventory.py https://example.org
"""
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse

UA = "Mozilla/5.0 (sitemap-inventory)"
NS = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
MAX_SITEMAPS = 50
MAX_BYTES = 10 * 1024 * 1024


def same_site(url, base):
    """Sitemap URLs come from the remote site: only follow http(s) on the base host."""
    u, b = urlparse(url), urlparse(base)
    return u.scheme in ("http", "https") and u.netloc == b.netloc


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read(MAX_BYTES).decode("utf-8", errors="replace")
    except Exception as exc:  # network errors only change the fallback path
        print(f"# skip {url}: {exc}", file=sys.stderr)
        return None


def sitemap_urls(base):
    robots = fetch(urljoin(base, "/robots.txt")) or ""
    found = re.findall(r"(?im)^\s*sitemap:\s*(\S+)", robots)
    return found or [urljoin(base, "/sitemap.xml")]


def read_sitemaps(roots, base):
    pages, queue, seen = [], list(roots), set()
    while queue and len(seen) < MAX_SITEMAPS:
        url = queue.pop(0)
        if url in seen or not same_site(url, base):
            continue
        seen.add(url)
        body = fetch(url)
        if not body:
            continue
        try:
            tree = ET.fromstring(body)
        except ET.ParseError:
            print(f"# skip {url}: not XML", file=sys.stderr)
            continue
        locs = [e.text.strip() for e in tree.iter(f"{NS}loc") if e.text]
        if tree.tag == f"{NS}sitemapindex":
            queue.extend(locs)
        else:
            pages.extend(locs)
    return pages


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.hrefs.append(href)


def crawl_home(base):
    body = fetch(base) or ""
    parser = Links()
    parser.feed(body)
    host = urlparse(base).netloc
    urls = {urljoin(base, h).split("#")[0] for h in parser.hrefs}
    return sorted(u for u in urls if urlparse(u).netloc == host)


def template_of(url):
    """First path segment, plus a marker when the URL goes deeper (detail pages)."""
    parts = [p for p in urlparse(url).path.split("/") if p]
    if not parts:
        return "/ (home)"
    if len(parts) == 1:
        return f"/{parts[0]}"
    return f"/{parts[0]}/* (depth {len(parts)})"


def main():
    if len(sys.argv) != 2 or not sys.argv[1].startswith(("http://", "https://")):
        sys.exit("usage: sitemap-inventory.py https://example.org")
    base = sys.argv[1].rstrip("/") + "/"

    pages = read_sitemaps(sitemap_urls(base), base)
    source = "sitemap"
    if not pages:
        pages, source = crawl_home(base), "home page links (no sitemap)"

    groups = defaultdict(list)
    for url in dict.fromkeys(pages):
        groups[template_of(url)].append(url)

    print(f"# {len(pages)} URLs from {source}")
    print("template\tcount\tsample")
    for tpl, urls in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        print(f"{tpl}\t{len(urls)}\t{urls[0]}")


if __name__ == "__main__":
    main()
