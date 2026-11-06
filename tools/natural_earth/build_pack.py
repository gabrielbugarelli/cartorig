#!/usr/bin/env python3
"""Deterministic SHA256 manifest builder for a preassembled, 100% OFFLINE pack.

Expected layout:
  ROOT/vector/natural_earth_vector.gpkg
  ROOT/vector/supplements.gpkg
  ROOT/vector/catalog.sqlite
  ROOT/raster/validated-raster-assets.json
  ROOT/raster/<asset_id>/index.json and tiles/...
  ROOT/source-archives.json (optional publisher provenance)
The caller prepares the assets separately. This tool never downloads data or
claims Natural Earth Complete until the independent coverage gate has passed.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import stat

REQUIRED = (
    "vector/natural_earth_vector.gpkg",
    "vector/supplements.gpkg",
    "vector/catalog.sqlite",
    "raster/validated-raster-assets.json",
)
MAX_FILES = 1_000_000

def digest(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()

def build_pack(root: Path,coverage:dict,*,allow_incomplete:bool=False)->dict:
    root=root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("data pack must be a directory")
    for item in REQUIRED:
        if not (root/item).is_file():
            raise ValueError("required offline pack component missing: "+item)
    raster=json.loads((root/"raster/validated-raster-assets.json").read_text(encoding="utf-8"))
    # Do not trust a boolean without checking source-count agreement.
    raster_ok=(raster.get("complete") is True and
               raster.get("sources_expected",0)>=1 and
               raster.get("sources_converted")==raster.get("sources_expected") and
               not raster.get("failures"))
    certified=(coverage.get("complete") is True and raster_ok and
               coverage.get("vector",{}).get("passed") is True and
               coverage.get("raster",{}).get("passed") is True)
    if not certified and not allow_incomplete:
        raise ValueError("Natural Earth Complete requires a passing source/coverage gate")
    entries=[]
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("symlinks are forbidden in the offline data pack")
        if not path.is_file():continue
        relative=path.relative_to(root).as_posix()
        if relative=="pack.json":continue
        if len(entries)>=MAX_FILES:
            raise ValueError("data pack file count exceeds safe limit")
        if not path.resolve().is_relative_to(root):
            raise ValueError("data pack contains out-of-root file")
        entries.append({"path":relative,"bytes":path.stat().st_size,
                        "sha256":digest(path)})
    names={e["path"] for e in entries}
    if not all(name in names for name in REQUIRED):
        raise ValueError("required data pack entries absent")
    if not any(name.endswith("/index.json") and name.startswith("raster/") for name in names):
        if certified:raise ValueError("certified pack has no raster atlases")
    stable=json.dumps(entries,sort_keys=True,separators=(",",":")).encode("utf-8")
    pack_id=hashlib.sha256(stable).hexdigest()
    manifest={
        "schema_version":1,"format":"cartorig-natural-earth-offline-v1",
        "pack_id":pack_id,"complete":certified,
        "status":"NATURAL_EARTH_COMPLETE" if certified else "EXPERIMENTAL_INCOMPLETE",
        "raster_sources":raster.get("sources_converted",0),
        "files":entries,
    }
    (root/"pack.json").write_text(
        json.dumps(manifest,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    return manifest

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",type=Path,required=True)
    parser.add_argument("--coverage",type=Path,required=True)
    parser.add_argument("--allow-incomplete",action="store_true")
    args=parser.parse_args()
    report=build_pack(args.root,
                      json.loads(args.coverage.read_text(encoding="utf-8")),
                      allow_incomplete=args.allow_incomplete)
    print(json.dumps({k:v for k,v in report.items() if k!="files"},indent=2))

if __name__=="__main__":
    main()
