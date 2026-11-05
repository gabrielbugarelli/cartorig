#!/usr/bin/env python3
"""Deterministic, reviewable migration ledger from user-owned CartoRig specifications.

The current Native code has not achieved full parity. This tool intentionally
never copies a legacy 'implemented' checkbox to Native completion.
"""
import argparse
import csv
import hashlib
import io
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "docs" / "reference"
OUT = ROOT / "docs" / "REQUIREMENTS_MATRIX.csv"
EXPECTED = {"CR-RF": 465, "KF+CAM+GEO+ROUTE+MG": 42, "MAP": 20, "ADV": 24, "TEST": 129}

PARTIAL = {
    "CR-RF-0001": "src/cartorig.cpp; samples/brasil-venezuela.cartorig-native.json",
    "CR-RF-0002": "src/cartorig.cpp",
    "CR-RF-0004": "src/cartorig.cpp",
    "CR-RF-0005": "src/cartorig.cpp",
    "KF-01": "src/cartorig.cpp (camera only)",
    "KF-05": "src/cartorig.cpp (linear/hold/smoothstep only)",
    "MAP-001": "src/cartorig.cpp (scene input, no full editor)",
    "MAP-003": "src/raster.cpp (fixed highlight IDs)",
    "MAP-004": "src/raster.cpp (ASCII marker labels only)",
    "MAP-005": "src/raster.cpp (two-anchor routes only)",
    "MAP-006": "src/cartorig.cpp (2D keyframe camera)",
    "MAP-007": "src/cartorig.cpp (fitBounds geometry)",
    "MAP-008": "src/cartorig.cpp (basic palette)",
    "MAP-009": "tools/render_preview.cpp (standalone preview only)",
    "MAP-020": "data/countries.geojson (offline raster)",
    "ADV-001": "src/cartorig.cpp (Polygon/MultiPolygon only)",
    "ADV-009": "src/raster.cpp (quadratic 2-anchor route)"
}

def clean(text):
    text = re.sub(r"\\*\\*|" + chr(96), "", text.strip())
    return re.sub(r"\\s+", " ", text)

def source(path):
    return (SRC / path).read_text(encoding="utf-8-sig")

def build():
    rows = []
    catalog = source("ORIGINAL_465.md")
    for status, ident, description in re.findall(r"^\\s*- \\[([x ])\\] \\*\\*(CR-RF-\\d{4})\\*\\*\\s*—\\s*(.*)$", catalog, re.M):
        rows.append([ident, "CR-RF", "ORIGINAL_465.md", clean(description), "legacy-implemented" if status == "x" else "legacy-backlog"])
    for ident, legacy_status, milestone, acceptance in re.findall(
        r"^\\|\\s*\\*\\*((?:KF|CAM|GEO|ROUTE|MG)-\\d{2})\\*\\*\\s*\\|\\s*([^|]*)\\|\\s*([^|]*)\\|\\s*(.*?)\\|\\s*$",
        catalog, re.M
    ):
        rows.append([ident, "ANIMATION", "ORIGINAL_465.md", clean(acceptance), clean(legacy_status)])
    for ident, description, acceptance in re.findall(r"^\\|\\s*(MAP-\\d{3})\\s*\\|\\s*([^|]*)\\|\\s*([^|]*)\\|", source("PRODUCT.md"), re.M):
        rows.append([ident, "MAP", "PRODUCT.md", clean(description + "; " + acceptance), "planned"])
    for ident, description, acceptance in re.findall(r"^\\|\\s*(ADV-\\d{3})\\s*\\|\\s*([^|]*)\\|\\s*([^|]*)\\|", source("ADVANCED_ROADMAP.md"), re.M):
        rows.append([ident, "ADV", "ADVANCED_ROADMAP.md", clean(description + "; " + acceptance), "planned"])

    counts = {"CR-RF": 0, "KF+CAM+GEO+ROUTE+MG": 0, "MAP": 0, "ADV": 0}
    for row in rows:
        counts["KF+CAM+GEO+ROUTE+MG" if row[1] == "ANIMATION" else row[1]] += 1
    with (SRC / "TEST_MATRIX_ORIGINAL.csv").open(encoding="utf-8-sig", newline="") as f:
        tests = list(csv.DictReader(f))
    counts["TEST"] = len(tests)
    if counts != EXPECTED:
        raise RuntimeError(f"Requirements coverage changed unexpectedly: {counts}, expected {EXPECTED}")
    ids = [row[0] for row in rows]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Duplicate requirement IDs")
    if len({row['id'] for row in tests}) != len(tests):
        raise RuntimeError("Duplicate test IDs")

    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\\n")
    writer.writerow(["requirement_id", "family", "source", "original_criterion", "original_state", "native_state", "native_evidence"])
    for ident, family, src, description, old in rows:
        evidence = PARTIAL.get(ident, "")
        writer.writerow([ident, family, src, description, old, "PARTIAL_CORE_UNVERIFIED_HOST" if evidence else "BACKLOG_NOT_ACCEPTED", evidence])
    return stream.getvalue(), counts

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="assert generated ledger is current without writing")
    args = ap.parse_args()
    content, counts = build()
    if args.check:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != content:
            raise SystemExit("REQUIREMENTS_MATRIX.csv is stale; run python tools/traceability.py")
    else:
        OUT.write_text(content, encoding="utf-8", newline="")
    print("Requirements indexed:", counts)
    print("Matrix SHA256:", hashlib.sha256(content.encode("utf-8")).hexdigest())

if __name__ == "__main__":
    main()
