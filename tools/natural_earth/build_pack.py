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
import re
from tools.natural_earth.build_rasters import reusable_asset

REQUIRED = (
    "vector/natural_earth_vector.gpkg",
    "vector/supplements.gpkg",
    "vector/catalog.sqlite",
    "raster/validated-raster-assets.json",
)
MAX_FILES = 1_000_000
MIN_PINNED_VECTOR_SOURCES = 215
MIN_PUBLISHER_RASTER_VARIANTS = 52
PACK_PATH = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./-]{0,255}$")

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
    vector=coverage.get("vector",{})
    raster_gate=coverage.get("raster",{})
    pages=coverage.get("pages",{})
    archives=coverage.get("archives",{})
    source_count=raster.get("sources_expected",0)
    # Full publisher coverage is not implied by a pair of true booleans.
    certified=(coverage.get("complete") is True and raster_ok and
               vector.get("passed") is True and
               vector.get("expected")==MIN_PINNED_VECTOR_SOURCES and
               vector.get("indexed")==MIN_PINNED_VECTOR_SOURCES and
               vector.get("supplemental_verified")==33 and
               raster_gate.get("passed") is True and
               raster_gate.get("source_variants")==source_count and
               raster_gate.get("source_variants",0)>=MIN_PUBLISHER_RASTER_VARIANTS and
               raster_gate.get("validated_derivatives",0)>=source_count and
               pages.get("passed") is True and
               archives.get("pack_verified") is True and
               archives.get("source_links",0)>=source_count)
    if certified:
        required_provenance=(
            "provenance/coverage-report.json",
            "provenance/official_sources.json",
            "provenance/source-archives.json",
            "provenance/vector_layers.json",
            "provenance/supplement_pin.json",
        )
        for name in required_provenance:
            if not (root/name).is_file():
                raise ValueError("certified release is missing provenance: "+name)
        stored=json.loads((root/"provenance/coverage-report.json").read_text(
            encoding="utf-8"))
        if stored!=coverage:
            raise ValueError("release audit report differs from pack certification")
        source=json.loads((root/"provenance/official_sources.json").read_text(
            encoding="utf-8"))
        if len([r for r in source.get("resources",[]) if r.get("theme")=="raster"])!=source_count:
            raise ValueError("published raster manifest differs from certified audit")
        verified_sources=json.loads((root/"provenance/source-archives.json").read_text(
            encoding="utf-8"))
        if len(verified_sources.get("resources",[]))!=archives["source_links"]:
            raise ValueError("archive manifest differs from certified audit")
        # A claimed raster source counts only if its exact publisher SHA256
        # matches real atlas metadata and EVERY generated tile rehashes.
        archive_hashes={r.get("resource_id"):r.get("sha256")
                        for r in verified_sources.get("resources",[])
                        if r.get("theme")=="raster"}
        if len(archive_hashes)!=source_count:
            raise ValueError("certified raster archive set is incomplete")
        assets=raster.get("assets",[])
        if not isinstance(assets,list) or len(assets)<source_count:
            raise ValueError("validated raster asset set is incomplete")
        seen_assets=set();seen_sources=set()
        for asset in assets:
            ident=asset.get("asset_id")
            source_id=asset.get("source_id")
            if (not isinstance(ident,str) or ident in seen_assets or
                source_id not in archive_hashes or asset.get("status")!="VALIDATED"):
                raise ValueError("invalid, duplicate or unproven raster atlas")
            seen_assets.add(ident)
            index=root/"raster"/ident/"index.json"
            if not index.is_file() or index.is_symlink():
                raise ValueError("raster atlas metadata missing: "+ident)
            metadata=json.loads(index.read_text(encoding="utf-8"))
            provenance=metadata.get("provenance",{})
            if (provenance.get("source_id")!=source_id or
                provenance.get("source_sha256")!=archive_hashes[source_id] or
                not reusable_asset(root/"raster",ident,archive_hashes[source_id],
                                   provenance.get("publisher_image"),
                                   provenance.get("publisher_world_file"))):
                raise ValueError("raster atlas source/tile proof is invalid: "+ident)
            seen_sources.add(source_id)
        if seen_sources!=set(archive_hashes):
            raise ValueError("not all raster sources have verified atlas content")
    if not certified and not allow_incomplete:
        raise ValueError("Natural Earth Complete requires a passing source/coverage gate")
    entries=[]
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("symlinks are forbidden in the offline data pack")
        if not path.is_file():continue
        relative=path.relative_to(root).as_posix()
        if relative=="pack.json":continue
        if not PACK_PATH.fullmatch(relative) or ".." in Path(relative).parts:
            raise ValueError("unsafe or nonportable pack file path: "+relative)
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
        "vector_sources":vector.get("indexed",0),
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
