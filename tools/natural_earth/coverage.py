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
          raster_derivatives:dict|None=None,
          supplemental_gpkg:Path|None=None,supplement_pin:dict|None=None)->dict:
    pinned={Path(x["source_path"]).stem for x in expected.get("layers",[])}
    if len(pinned)!=expected.get("layer_count"):
        raise ValueError("duplicate or invalid pinned vector layers")
    found=set()
    if catalog and catalog.is_file():
        db=sqlite3.connect(catalog.resolve().as_uri()+"?mode=ro",uri=True)
        try:found={x[0] for x in db.execute("SELECT table_name FROM layers")}
        finally:db.close()
    supplement_invalid=[]
    supplemental_names=set()
    if supplemental_gpkg and supplemental_gpkg.is_file():
        pin_entries=(supplement_pin or {}).get("entries",[])
        pinned_supp={entry["layer"]:entry["pinned_git_blob_sha1"] for entry in pin_entries}
        if len(pinned_supp)!=33 or len(pin_entries)!=33 or (supplement_pin or {}).get("upstream_ref")!="v5.1.2":
            supplement_invalid.append("missing or invalid pinned supplement source manifest")
        else:
            db=sqlite3.connect(supplemental_gpkg.resolve().as_uri()+"?mode=ro",uri=True)
            try:
                metadata={row[0] for row in db.execute(
                    "SELECT table_name FROM gpkg_geometry_columns WHERE srs_id=4326")}
                layers={row[0] for row in db.execute(
                    "SELECT table_name FROM gpkg_contents WHERE data_type='features'")}
                for name,path,blob_sha,sha,features in db.execute(
                    "SELECT table_name,upstream_path,upstream_git_blob_sha1,sha256,feature_count FROM provenance"):
                    valid=(name in pinned_supp and name in metadata and name in layers
                           and path=="geojson/"+name+".geojson"
                           and blob_sha==pinned_supp[name]
                           and isinstance(sha,str) and len(sha)==64
                           and isinstance(features,int) and features>0)
                    if valid:
                        count=db.execute('SELECT COUNT(*) FROM "'+name+'"').fetchone()[0]
                        valid=count==features
                    if valid:
                        supplemental_names.add(name)
                    else:
                        supplement_invalid.append(name)
                if len(supplemental_names)!=33:
                    supplement_invalid.append("not all 33 pinned sources are present")
            except sqlite3.Error as error:
                supplement_invalid.append("invalid supplemental GeoPackage: "+str(error))
            finally:
                db.close()
    # Supplemental tables count only after provenance, schema and row checks.
    missing=sorted(pinned-(found|supplemental_names))
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
    # Discovery records intentionally remain DISCOVERED_UNVERIFIED. Their
    # corresponding acquired assets are recorded by materialize() in a
    # *separate*, SHA256-verified manifest. Compare source IDs and URLs
    # explicitly rather than requiring discovery itself to be verified.
    verified_assets={}
    # Full vector-source coverage is proven from the publisher aggregate
    # GeoPackage plus 33 independently pinned supplements. The website
    # links to redundant, sometimes inaccessible vector ZIP bundles; only
    # raster variants require distinct downloaded archives and conversion.
    raster_ids={item.get("resource_id") for item in raster_sources}
    archive_records=[item for item in (archives or {}).get("resources",[])
                     if item.get("resource_id") in raster_ids]
    duplicates=[]
    for asset in archive_records:
        key=asset.get("resource_id")
        if not key or key in verified_assets:
            duplicates.append(key)
        else:
            verified_assets[key]=asset
    source_unverified=[]
    for item in raster_sources:
        ident=item.get("resource_id")
        local=verified_assets.get(ident,{})
        valid=(local.get("status")=="VERIFIED"
               and local.get("url")==item.get("url")
               and isinstance(local.get("sha256"),str)
               and len(local["sha256"])==64
               and isinstance(local.get("archive_bytes"),int)
               and local["archive_bytes"]>0)
        if not valid:source_unverified.append(ident)
    source_unverified+=duplicates
    page_blocked=[x.get("url") for x in source_pages if x.get("status")!="INDEXED"]
    vector_ok=bool(pinned) and not missing and not supplement_invalid
    sources_ok=bool(source_assets) and not missing_categories and not page_blocked
    raster_report=raster_derivatives or {}
    raster_ok=(bool(raster_sources) and not raster_missing
               and not any(raster_family_missing.values())
               and raster_report.get("complete") is True
               and raster_report.get("sources_converted")==
                   raster_report.get("sources_expected")==len(raster_sources)
               and not raster_report.get("failures"))
    source_ids=raster_ids
    archives_complete=bool(archives and
        ((archives.get("summary") or {}).get("complete") is True or
         archives.get("complete") is True))
    archives_ok=(archives_complete and not source_unverified
                 and len(archive_records)==len(raster_sources)
                 and len(verified_assets)==len(source_ids))
    complete=vector_ok and sources_ok and raster_ok and archives_ok
    return {
        "schema_version":1,"complete":complete,
        "vector":{"expected":len(pinned),"indexed":len(pinned)-len(missing),
                  "primary_indexed":len(pinned&found),
                  "supplemental_verified":len(supplemental_names),
                  "supplemental_invalid":supplement_invalid,
                  "missing":missing,"passed":vector_ok},
        "pages":{"missing_categories":missing_categories,"blocked":page_blocked,
                 "raster_families_indexed":raster_family_pages,
                 "raster_families_missing":raster_family_missing,
                 "passed":sources_ok},
        "archives":{"source_links":len(archive_records),"unverified":source_unverified,
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
    p.add_argument("--supplemental-gpkg",type=Path)
    p.add_argument("--supplement-pin",type=Path)
    p.add_argument("--output",required=True,type=Path)
    a=p.parse_args()
    def load(path):
        return json.loads(path.read_text(encoding="utf-8")) if path and path.is_file() else None
    report=audit(load(a.vector_pin),a.catalog,load(a.sources),load(a.archives),
                 load(a.raster_derivatives),a.supplemental_gpkg,load(a.supplement_pin))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print("COMPLETE" if report["complete"] else "BLOCKED")
    if not report["complete"]:raise SystemExit(1)

if __name__=="__main__":main()
