#!/usr/bin/env python3
"""Fail-closed Natural Earth completeness audit: no network calls."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sqlite3

GROUPS={(a,b) for a,b in (
    ("10m","cultural"),("10m","physical"),("10m","raster"),
    ("50m","cultural"),("50m","physical"),("50m","raster"),
    ("110m","cultural"),("110m","physical"))}
RASTER_COUNTS={"10m":7,"50m":9}

def audit(expected:dict,catalog:Path|None=None,
          sources:dict|None=None,archives:dict|None=None,
          raster_derivatives:dict|None=None)->dict:
    pinned={Path(x["source_path"]).stem for x in expected.get("layers",[])}
    if len(pinned)!=expected.get("layer_count"):
        raise ValueError("duplicate or invalid pinned vector layers")
    found=set()
    if catalog and catalog.is_file():
        db=sqlite3.connect(catalog.resolve().as_uri()+"?mode=ro",uri=True)
        try:found={x[0] for x in db.execute("SELECT table_name FROM layers")}
        finally:db.close()
    missing=sorted(pinned-found)
    source_pages=(sources or {}).get("pages",[])
    source_assets=(sources or {}).get("resources",[])
    indexed=set()
    for scale,theme in GROUPS:
        tail=f"/{scale}-{'raster-data' if theme=='raster' else theme+'-vectors'}"
        if any(p.get("status")=="INDEXED" and
               p.get("url","").rstrip("/").endswith(tail) for p in source_pages):
            indexed.add((scale,theme))
    missing_categories=sorted([f"{s}:{t}" for s,t in GROUPS-indexed])
    raster_family_pages={s:sum(
        p.get("status")=="INDEXED" and f"/downloads/{s}-raster-data/" in p.get("url","")
        for p in source_pages) for s in RASTER_COUNTS}
    raster_family_missing={s:max(0,RASTER_COUNTS[s]-raster_family_pages[s])
                           for s in RASTER_COUNTS}
    raster_sources=[x for x in source_assets if x.get("theme")=="raster"]
    raster_installed=(raster_derivatives or {}).get("assets",[])
    raster_missing=[x.get("resource_id") for x in raster_sources if not any(
        d.get("source_id")==x.get("resource_id") and d.get("status")=="VALIDATED"
        for d in raster_installed)]
    source_unverified=[x.get("resource_id") for x in source_assets if
                       x.get("status")!="VERIFIED" or not x.get("sha256")]
    page_blocked=[x.get("url") for x in source_pages if x.get("status")!="INDEXED"]
    vector_ok=bool(pinned) and not missing
    sources_ok=bool(source_assets) and not missing_categories and not page_blocked
    raster_ok=bool(raster_sources) and not raster_missing and not any(raster_family_missing.values())
    archives_ok=bool(archives and archives.get("complete")) and not source_unverified
    complete=vector_ok and sources_ok and raster_ok and archives_ok
    return {
        "schema_version":1,"complete":complete,
        "vector":{"expected":len(pinned),"indexed":len(pinned)-len(missing),
                  "missing":missing,"passed":vector_ok},
        "pages":{"missing_categories":missing_categories,"blocked":page_blocked,
                 "raster_families_indexed":raster_family_pages,
                 "raster_families_missing":raster_family_missing,
                 "passed":sources_ok},
        "archives":{"source_links":len(source_assets),"unverified":source_unverified,
                    "pack_verified":archives_ok},
        "raster":{"source_variants":len(raster_sources),
                  "validated_derivatives":len(raster_installed),
                  "missing":raster_missing,"passed":raster_ok},
        "reason":None if complete else "Natural Earth data pack not fully verified",
    }

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("vector-pin","catalog","sources","archives","raster-derivatives"):
        p.add_argument("--"+name,type=Path,required=name=="vector-pin")
    p.add_argument("--output",required=True,type=Path)
    a=p.parse_args()
    def load(path):
        return json.loads(path.read_text(encoding="utf-8")) if path and path.is_file() else None
    report=audit(load(a.vector_pin),a.catalog,load(a.sources),load(a.archives),load(a.raster_derivatives))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print("COMPLETE" if report["complete"] else "BLOCKED")
    if not report["complete"]:raise SystemExit(1)

if __name__=="__main__":main()
