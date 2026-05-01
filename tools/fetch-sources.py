#!/usr/bin/env python3
"""
Fetch the 4 authentic-source RSS feeds and emit a JSON array of the top 3
items per feed (12 items total). Mirrors the shape of `tools/fetch-sources.ps1`
so the existing rewrite prompts can read either cache file unchanged.

Used by `.github/workflows/sources-cache.yml` to produce the daily cache that
cloud routines read via WebFetch -- the cloud sandbox cannot reach .go.jp /
.or.jp / news.yahoo.co.jp directly (Claude WebFetch blocks them), but it can
reach github.com release assets.

Output format (stdout):
  [
    {"source": "内閣府", "title": "...", "url": "...",
     "pubDate": "...", "summary": ""},
    ...
  ]

Exit codes:
  0 if at least one item was extracted
  1 if every feed failed (caller should NOT publish a stale cache)
"""

from __future__ import annotations

import json
import sys
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET

FEEDS = [
    ("内閣府", "https://www.cao.go.jp/rss/news.rdf"),
    ("厚生労働省", "https://www.mhlw.go.jp/stf/news.rdf"),
    ("Yahoo!ニュース（国内）", "https://news.yahoo.co.jp/rss/categories/domestic.xml"),
    ("NHKニュース", "https://www.nhk.or.jp/rss/news/cat1.xml"),
]

NS = {
    "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "rss": "http://purl.org/rss/1.0/",
    "dc": "http://purl.org/dc/elements/1.1/",
    "atom": "http://www.w3.org/2005/Atom",
}

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)


def _text(el, tag, ns=None):
    if el is None:
        return ""
    if ns:
        node = el.find(f"{{{NS[ns]}}}{tag}")
    else:
        node = el.find(tag)
    return (node.text or "").strip() if node is not None and node.text else ""


def parse_feed(name: str, url: str, max_items: int = 3) -> list[dict]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = r.read()
    root = ET.fromstring(data)

    # RDF/RSS 1.0 (内閣府, 厚労省): rdf:RDF / rss:item
    # RSS 2.0 (Yahoo, NHK):       rss / channel / item
    # Atom (defensive):           atom:feed / atom:entry
    items_xml = []
    items_xml.extend(root.findall(f"{{{NS['rss']}}}item"))            # RSS 1.0
    if not items_xml:
        items_xml.extend(root.findall(".//item"))                     # RSS 2.0
    if not items_xml:
        items_xml.extend(root.findall(f".//{{{NS['atom']}}}entry"))   # Atom

    out = []
    for it in items_xml[:max_items]:
        # Title / link
        title = _text(it, "title", ns="rss") or _text(it, "title", ns="atom") or _text(it, "title")
        link = _text(it, "link", ns="rss") or _text(it, "link")
        if not link:
            atom_link = it.find(f"{{{NS['atom']}}}link")
            if atom_link is not None:
                link = atom_link.attrib.get("href", "")

        # Pub date
        pub = (
            _text(it, "pubDate")
            or _text(it, "date", ns="dc")
            or _text(it, "updated", ns="atom")
            or _text(it, "published", ns="atom")
        )

        # Summary
        summary = (
            _text(it, "description", ns="rss")
            or _text(it, "description")
            or _text(it, "summary", ns="atom")
        )
        if len(summary) > 200:
            summary = summary[:200]

        if title and link:
            out.append({
                "source": name,
                "title": title,
                "url": link,
                "pubDate": pub,
                "summary": summary,
            })
    return out


def main() -> int:
    all_items: list[dict] = []
    errors: list[dict] = []
    for name, url in FEEDS:
        try:
            items = parse_feed(name, url)
            if not items:
                errors.append({"source": name, "url": url, "error": "no items parsed"})
            else:
                all_items.extend(items)
        except (urllib.error.URLError, urllib.error.HTTPError, ET.ParseError, OSError) as e:
            errors.append({"source": name, "url": url, "error": f"{type(e).__name__}: {e}"})

    if errors:
        sys.stderr.write("Feed errors:\n")
        for err in errors:
            sys.stderr.write(f"  {err['source']}: {err['error']}\n")

    if not all_items:
        sys.stderr.write("All feeds failed -- not emitting JSON.\n")
        return 1

    json.dump(all_items, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    sys.stderr.write(f"OK: {len(all_items)} items from {len({i['source'] for i in all_items})} sources\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
