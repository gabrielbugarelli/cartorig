#!/usr/bin/env python3
"""Explicit real-data GeoPackage publisher probe (release engineering only).

Fetches the published Natural Earth vector GeoPackage once under a tight size
budget, validates its ZIP, creates a local offline geographic index, compares
layer coverage with the pinned 215-layer upstream inventory and uploads ONLY
a JSON metrics report. Never accessed by the OFX plugin runtime.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sqlite3
import zipfile

from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.verify_pack import verify_zip
from tools.natural_earth.build_catalog import index_source
from tools.natural_earth.coverage import audit

URL="https://naciscdn.org/naturalearth/packages/natural_earth_vector.gpkg.zip"
MAX_ZIP=750_000_000
MAX_GPKG=5_500_000_000

def main():
    root=Path("build/natural-earth/gpkg-probe")
    root.mkdir(parents=True,exist_ok=True)
    package=root/"natural_earth_vector.gpkg.zip"
    report={"source":URL,"status":"STARTED","complete_natural_earth":False}
    report_path=root/"gpkg-probe.json"
    try:
        size,sha=download_and_hash(URL,package,max_bytes=MAX_ZIP)
        archive=verify_zip(package,max_items=300,max_uncompressed=MAX_GPKG)
        report["download"]={"size_bytes":size,"sha256":sha,**archive}
        with zipfile.ZipFile(package) as z:
            candidates=[info for info in z.infolist() if
                        info.filename.lower().endswith(".gpkg") and not info.is_dir()]
            if len(candidates)!=1:
                raise ValueError("expected exactly one GeoPackage in official vector archive")
            info=candidates[0]
            if info.file_size>MAX_GPKG:
                raise ValueError("publisher GeoPackage exceeds disk budget")
            gpkg=root/"natural_earth_vector.gpkg"
            with z.open(info) as src,gpkg.open("wb") as dst:
                while block:=src.read(1024*1024):dst.write(block)
        catalog=root/"catalog.sqlite"
        report["index"]=index_source(gpkg,catalog)
        pinned=json.loads(
            Path("data/natural-earth/vector_layers_v5.1.2.json").read_text(encoding="utf-8"))
        coverage=audit(pinned,catalog)
        report["coverage"]=coverage["vector"]
        with sqlite3.connect(catalog) as db:
            report["layer_sample"]=db.execute(
                "SELECT table_name,scale,feature_count,indexed_regions "
                "FROM layers ORDER BY table_name LIMIT 20").fetchall()
            report["search_sample"]={
                "countries":db.execute("SELECT COUNT(*) FROM regions WHERE kind='country'").fetchone()[0],
                "states":db.execute("SELECT COUNT(*) FROM regions WHERE kind='state'").fetchone()[0],
                "cities":db.execute("SELECT COUNT(*) FROM regions WHERE kind='city'").fetchone()[0]
            }
        report["status"]="GPKG_INDEXED_AND_AUDITED"
        # Raster themes and archived variants still missing, therefore NEVER
        # mark this a Natural Earth Complete release.
    except Exception as error:
        report["status"]="FAILED"
        report["error"]=type(error).__name__+": "+str(error)[:400]
        raise
    finally:
        report_path.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
        print(json.dumps({"status":report["status"],
                          "vector_coverage":report.get("coverage"),
                          "search_sample":report.get("search_sample")},indent=2))
        # Avoid leaking large artifacts into GitHub storage. Tests may use
        # scratch files on the runner but upload metrics only.
        package.unlink(missing_ok=True)

if __name__=="__main__":main()
