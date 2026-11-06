#!/usr/bin/env python3
"""Natural Earth official-source inventory and optional build-time asset fetch.

Only build/release tooling may access the network. The OpenFX runtime never
uses this module. Every discovered link is UNVERIFIED until content is fetched,
hashed and independently checked. Do not equate a page link to an installed layer.
"""
from __future__ import annotations
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone

BASE = "https://www.naturalearthdata.com/downloads/"
GROUPS = (
    ("10m", "cultural"), ("10m", "physical"), ("10m", "raster"),
    ("50m", "cultural"), ("50m", "physical"), ("50m", "raster"),
    ("110m", "cultural"), ("110m", "physical"),
)
ALLOWED_HOSTS = {"www.naturalearthdata.com", "naturalearthdata.com",
                 "naciscdn.org", "naturalearth.s3.amazonaws.com"}
MAX_HTML = 5_000_000
MAX_ARCHIVE = 1_500_000_000
ARCHIVE_TYPES = (".zip", ".gpkg", ".sqlite", ".tif", ".tiff", ".psd", ".tar.gz", ".7z")
VERSION = re.compile(r"\bversion\s+(\d+\.\d+(?:\.\d+)?)", re.I)

def category_page(scale: str, theme: str) -> str:
    part = "raster-data" if theme == "raster" else theme + "-vectors"
    return f"{BASE}{scale}-{part}/"

class Links(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.anchors: list[dict] = []
        self.parts: list[str] = []
        self.active: dict | None = None

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            attr = dict(attrs)
            self.active = {"href": attr.get("href", ""), "start": len("".join(self.parts)),
                           "text": []}

    def handle_endtag(self, tag):
        if tag == "a" and self.active is not None:
            self.active["label"] = " ".join("".join(self.active["text"]).split())
            del self.active["text"]
            self.anchors.append(self.active)
            self.active = None

    def handle_data(self, data):
        self.parts.append(data)
        if self.active is not None:
            self.active["text"].append(data)

    def all_text(self) -> str:
        return "".join(self.parts)

def canonical_url(href: str, page: str) -> str | None:
    href = href.strip().replace("&amp;", "&")
    # WordPress currently publishes downloads as '/http//www.naturalearthdata.com/...'.
    # Repair ONLY this malformed, known publisher form; never join it as a
    # local /http// path or silently substitute another source provider.
    slashed = href.lstrip("/")
    if slashed.startswith("http//"):
        href = "https://" + slashed[6:]
    elif slashed.startswith("https//"):
        href = "https://" + slashed[7:]
    url = urllib.parse.urljoin(page, href)
    # The currently published WordPress pages contain absolute links like:
    # https://www.naturalearthdata.com/http//www.naturalearthdata.com/download/...
    # Resolve a publisher host embedded inside its own malformed path.
    malformed = re.match(
        r"^https?://(?:www\.)?naturalearthdata\.com/(?:http|https)//"
        r"((?:www\.)?naturalearthdata\.com)/download/(.+)$", url, re.I)
    if malformed:
        url = "https://" + malformed.group(1).lower() + "/download/" + malformed.group(2)
    parts = urllib.parse.urlsplit(url)
    if parts.hostname not in ALLOWED_HOSTS or parts.scheme not in ("http", "https"):
        return None
    if parts.username or parts.password:
        return None
    if parts.scheme == "http":
        url = urllib.parse.urlunsplit(("https", parts.netloc, parts.path, parts.query, ""))
    return url

def parse_page(html: str, page: str, scale: str, theme: str) -> tuple[list[dict], list[str]]:
    parser = Links()
    parser.feed(html)
    whole = parser.all_text()
    records: list[dict] = []
    children: set[str] = set()
    for a in parser.anchors:
        url = canonical_url(a["href"], page)
        if url is None:
            continue
        parts = urllib.parse.urlsplit(url)
        target = parts.path.lower()
        if (theme == "raster" and target.startswith(
                urllib.parse.urlsplit(category_page(scale, theme)).path.lower())
                and url.rstrip("/") != page.rstrip("/") and
                parts.hostname in ("www.naturalearthdata.com", "naturalearthdata.com") and
                not any(target.endswith(x) for x in ARCHIVE_TYPES)):
            children.add(url.rstrip("/") + "/")
        if not any(target.endswith(ext) for ext in ARCHIVE_TYPES):
            continue
        label = a["label"]
        context = whole[a["start"]:a["start"] + 180]
        version = VERSION.search(context)
        key = hashlib.sha256((page + "\n" + url + "\n" + label).encode()).hexdigest()[:20]
        records.append({
            "resource_id": f"ne-{scale}-{theme}-{key}",
            "scale": scale, "theme": theme,
            "label": label, "source_page": page, "url": url,
            "theme_version": version.group(1) if version else None,
            "archive_format": target.rsplit(".", 1)[-1],
            "status": "DISCOVERED_UNVERIFIED",
            "sha256": None, "archive_bytes": None,
        })
    return records, sorted(children)

def fetch_page(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "CartoRigNaturalEarthAudit/0.1"})
    with urllib.request.urlopen(req, timeout=35) as resp:
        if urllib.parse.urlsplit(resp.url).hostname not in ALLOWED_HOSTS:
            raise ValueError("source page redirected outside official hosts")
        data = resp.read(MAX_HTML + 1)
    if len(data) > MAX_HTML:
        raise ValueError("page exceeds bounded download size")
    return data.decode("utf-8", "replace")

def audit(fetch=fetch_page) -> dict:
    """Explicit release-engineering operation: runs with network access."""
    resources: list[dict] = []
    pages: list[dict] = []
    visited: set[str] = set()
    for scale, theme in GROUPS:
        root = category_page(scale, theme)
        pending = [root]
        # Exactly one level of raster family pages, not unbounded crawling.
        for depth in range(2 if theme == "raster" else 1):
            next_pending: list[str] = []
            for url in pending:
                if url in visited:
                    continue
                visited.add(url)
                try:
                    html = fetch(url)
                    links, children = parse_page(html, url, scale, theme)
                    resources.extend(links)
                    pages.append({"url": url, "status": "INDEXED",
                                  "html_sha256": hashlib.sha256(html.encode()).hexdigest(),
                                  "download_links": len(links)})
                    if depth == 0:
                        next_pending.extend(children)
                except Exception as exc:
                    pages.append({"url": url, "status": "BLOCKED",
                                  "reason": type(exc).__name__ + ": " + str(exc)[:200]})
            pending = sorted(set(next_pending))
    # Do not count duplicate anchors as multiple archives.
    unique = {x["resource_id"]: x for x in resources}
    blocked = [p for p in pages if p["status"] == "BLOCKED"]
    return {
        "schema_version": 1, "publisher": "Natural Earth / NACIS",
        "policy": "All layers must be VERIFIED before a complete-data claim",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "pages": pages, "resources": sorted(unique.values(), key=lambda x: (x["scale"],x["theme"],x["url"])),
        "summary": {"category_pages_expected": 8,
                    "pages_indexed": len(pages)-len(blocked),
                    "pages_blocked": len(blocked),
                    "resources_discovered": len(unique),
                    "resources_verified": 0, "complete": False},
    }

def download_and_hash(url: str, path: Path, max_bytes: int = MAX_ARCHIVE) -> tuple[int,str]:
    """Explicit producer-only download. Runtime is strictly offline."""
    canonical = canonical_url(url, BASE)
    if canonical != url or not any(urllib.parse.urlsplit(url).path.lower().endswith(x) for x in ARCHIVE_TYPES):
        raise ValueError("download must be an official, canonical archive URL")
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".part")
    h = hashlib.sha256()
    count = 0
    try:
        with urllib.request.urlopen(urllib.request.Request(
                url, headers={"User-Agent": "CartoRigNaturalEarthBuild/0.1"}), timeout=90) as source:
            if urllib.parse.urlsplit(source.url).hostname not in ALLOWED_HOSTS:
                raise ValueError("redirect outside official data providers")
            with temp.open("wb") as dest:
                while chunk := source.read(1024 * 1024):
                    count += len(chunk)
                    if count > max_bytes:
                        raise ValueError("archive exceeds configured size limit")
                    h.update(chunk)
                    dest.write(chunk)
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)
    return count, h.hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    report = audit()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    if report["summary"]["pages_blocked"]:
        raise SystemExit("Source page audit incomplete: inspect BLOCKED pages")

if __name__ == "__main__":
    main()
