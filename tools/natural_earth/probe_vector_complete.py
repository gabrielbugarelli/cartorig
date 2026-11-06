#!/usr/bin/env python3
"""One-shot audit of real, pinned Natural Earth 5.1.2 VECTOR data (215 layers).

Release-engineering only, never part of the installed OpenFX plugin.
Source 1: current official aggregate GeoPackage (182 matching layer tables).
Source 2: all 33 missing official 5.1.2 GeoJSON files, SHA1 Git verified,
converted to GeoPackage with source properties and true OGC geometry.
The combined VECTOR gate can pass independently of the RASTER gate, which
remains explicitly incomplete.
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
from tools.natural_earth.supplements import fetch_official,create_geopackage,manifest_entries
from tools.natural_earth.coverage import audit

PRIMARY_URL="https://naciscdn.org/naturalearth/packages/natural_earth_vector.gpkg.zip"
# Measured against the publisher on 2026-11-06; pin for deterministic release.
PRIMARY_SHA256="b9e2e7b3d5c2c59593f6eafc19be2ba87fb04788a90c57ccd6cf32a587b6ecc3"
MAX_ZIP=750_000_000
MAX_GPKG=5_500_000_000

def execute(root:Path)->dict:
    root.mkdir(parents=True,exist_ok=True)
    main_zip=root/"natural_earth_vector.gpkg.zip"
    summary={
      "schema_version":1,"source_release":"natural-earth-vector/v5.1.2",
      "primary_package":PRIMARY_URL,"official_primary_zip_sha256":PRIMARY_SHA256,
      "full_natural_earth_complete":False,
      "vector_complete":False,"status":"STARTED",
    }
    try:
        size,sha=download_and_hash(PRIMARY_URL,main_zip,max_bytes=MAX_ZIP)
        if sha!=PRIMARY_SHA256:
            raise ValueError("published aggregate GeoPackage SHA256 differs from verified baseline")
        summary["primary_verified_bytes"]=size
        verify_zip(main_zip,max_items=300,max_uncompressed=MAX_GPKG)
        with zipfile.ZipFile(main_zip) as archive:
            entries=[x for x in archive.infolist() if x.filename.endswith(".gpkg") and not x.is_dir()]
            if len(entries)!=1:
                raise ValueError("official vector aggregate does not contain exactly one GeoPackage")
            gpkg=root/"natural_earth_vector.gpkg"
            with archive.open(entries[0]) as src,gpkg.open("wb") as dst:
                while chunk:=src.read(1024*1024):dst.write(chunk)
        index=root/"base-index.sqlite"
        summary["aggregate_index"]=index_source(gpkg,index)
        vector_pin=json.loads(Path("data/natural-earth/vector_layers_v5.1.2.json").read_text())
        supplement_pin=json.loads(Path(
          "data/natural-earth/aggregate_geojson_supplements_v5.1.2.json").read_text())
        entries=manifest_entries(supplement_pin)
        folder=root/"supplement-source"
        fetch_official(entries,folder)
        supplement_path=root/"natural_earth_supplement.gpkg"
        summary["supplemental_import"]=create_geopackage(supplement_pin,folder,supplement_path)
        combined=audit(vector_pin,index,supplemental_gpkg=supplement_path,
                       supplement_pin=supplement_pin)
        summary["vector_coverage"]=combined["vector"]
        summary["vector_complete"]=combined["vector"]["passed"]
        # Prove that the FTS catalog still works for normal country/state/city
        # searches; physical supplementary data lives in separate layer GPKG.
        with sqlite3.connect(index) as db:
            summary["main_layer_tables"]=db.execute("SELECT COUNT(*) FROM layers").fetchone()[0]
            summary["country_search_entries"]=db.execute(
                "SELECT COUNT(*) FROM regions WHERE kind='country'").fetchone()[0]
        summary["status"]="VERIFIED_VECTOR_215" if summary["vector_complete"] else "INCOMPLETE_VECTOR"
        if not summary["vector_complete"]:
            raise ValueError("vector source coverage is incomplete")
        return summary
    except Exception as error:
        summary["status"]="FAILED"
        summary["error"]=type(error).__name__+": "+str(error)[:400]
        raise
    finally:
        report=root/"complete-vector-report.json"
        report.write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
        # Never upload or accidentally commit the 1GB+ primary GeoPackage.
        main_zip.unlink(missing_ok=True)

def main():
    report=execute(Path("build/natural-earth/combined-vector"))
    print(json.dumps({"status":report["status"],"vector":report.get("vector_coverage"),
                      "raster_complete":False},indent=2))

if __name__=="__main__":main()
