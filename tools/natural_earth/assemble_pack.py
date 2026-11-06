#!/usr/bin/env python3
"""Build a portable, verified Natural Earth data pack from LOCAL publisher files.

No downloads. In particular, this command is not a Resolve runtime feature.
It composes the 182-layer official GeoPackage, the 33-layer supplement, the
offline SQLite search index and ALL inventoried raster variants into one
manifest-verified directory. Failed audits never label a pack complete.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import tempfile

from tools.natural_earth import (
    build_catalog, build_pack, build_rasters, coverage, verify_pack
)

def assemble(*,vector:Path,supplement:Path,sources:Path,
             archives:Path,archive_root:Path,vector_pin:Path,
             supplement_pin:Path,out:Path,allow_incomplete:bool=False)->dict:
    if out.exists():raise FileExistsError("output data pack already exists")
    parent=out.resolve().parent
    parent.mkdir(parents=True,exist_ok=True)
    discovery=json.loads(sources.read_text(encoding="utf-8"))
    acquired=json.loads(archives.read_text(encoding="utf-8"))
    pinned=json.loads(vector_pin.read_text(encoding="utf-8"))
    supplemental_pin=json.loads(supplement_pin.read_text(encoding="utf-8"))
    verified=verify_pack.verify_manifest(acquired,archive_root)
    if not verified["complete"] and not allow_incomplete:
        raise ValueError("all publisher source archives must be SHA256-verified")
    with tempfile.TemporaryDirectory(prefix=".cartorig-pack.",dir=parent) as temp:
        root=Path(temp)/"data"
        (root/"vector").mkdir(parents=True)
        (root/"raster").mkdir(parents=True)
        (root/"provenance").mkdir(parents=True)
        for source,target in (
            (vector,root/"vector/natural_earth_vector.gpkg"),
            (supplement,root/"vector/supplements.gpkg"),
            (sources,root/"provenance/official_sources.json"),
            (archives,root/"provenance/source-archives.json"),
            (vector_pin,root/"provenance/vector_layers.json"),
            (supplement_pin,root/"provenance/supplement_pin.json"),
        ):
            if not source.is_file():raise FileNotFoundError(source)
            shutil.copy2(source,target)
        build_catalog.index_source(
            root/"vector/natural_earth_vector.gpkg",
            root/"vector/catalog.sqlite")
        # build_rasters itself verifies every raster archive before reading it.
        raster=build_rasters.compile_archives(
            acquired,archive_root,root/"raster")
        # Fail-closed coverage ties independent evidence together, not merely
        # the presence of names in a directory.
        audit=coverage.audit(
            pinned,root/"vector/catalog.sqlite",
            discovery,acquired,raster,
            root/"vector/supplements.gpkg",supplemental_pin)
        (root/"provenance/coverage-report.json").write_text(
            json.dumps(audit,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        if not audit["complete"] and not allow_incomplete:
            raise ValueError("Natural Earth Complete audit failed: "+
                             json.dumps({k:v.get("passed") for k,v in audit.items()
                                         if isinstance(v,dict)}))
        manifest=build_pack.build_pack(
            root,audit,allow_incomplete=allow_incomplete)
        root.replace(out)
        return {"pack_id":manifest["pack_id"],"complete":manifest["complete"],
                "raster_sources":raster["sources_converted"],
                "vector_verified":audit["vector"]["indexed"],
                "files":len(manifest["files"]),"destination":str(out)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("vector","supplement","sources","archives","archive-root",
                 "vector-pin","supplement-pin","out"):
        parser.add_argument("--"+name,type=Path,required=True)
    parser.add_argument("--allow-incomplete",action="store_true")
    args=parser.parse_args()
    result=assemble(
        vector=args.vector,supplement=args.supplement,
        sources=args.sources,archives=args.archives,
        archive_root=args.archive_root,vector_pin=args.vector_pin,
        supplement_pin=args.supplement_pin,out=args.out,
        allow_incomplete=args.allow_incomplete)
    print(json.dumps(result,indent=2))

if __name__=="__main__":
    main()
