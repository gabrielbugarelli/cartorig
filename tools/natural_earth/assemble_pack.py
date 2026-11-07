#!/usr/bin/env python3
"""Build a portable, verified Natural Earth data pack from LOCAL publisher files.

No downloads. In particular, this command is not a Resolve runtime feature.
It composes the 182-layer official GeoPackage, the 33-layer supplement, the
offline SQLite search index and ALL inventoried raster variants into one
manifest-verified directory. Failed audits never label a pack complete.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import sqlite3
from pathlib import Path
import shutil

from tools.natural_earth import (
    build_catalog, build_pack, build_rasters, coverage, verify_pack
)

def _verified_raster_subset(acquired:dict,discovery:dict,root:Path,
                            reviewed_unavailable:dict[str,dict])->dict:
    """Only for an explicitly reviewed, non-certified experimental pack.

    Do not remove the missing source from source-archives.json or the official
    publisher inventory. Compile the verified subset, but independently audit
    the original full manifest and always mark the resulting pack incomplete.
    """
    from tools.natural_earth.verify_pack import verify_manifest
    records=acquired.get("resources",[])
    discovered={r["resource_id"]:r for r in discovery.get("resources",[])
                if r.get("theme")=="raster"}
    if (not reviewed_unavailable or not isinstance(records,list) or
            len(records)!=len(discovered) or len(discovered)<2 or
            len({r.get("resource_id") for r in records})!=len(records)):
        raise ValueError("experimental data pack must preserve all discovered raster source IDs")
    actual_ids={r.get("resource_id") for r in records}
    if actual_ids!=set(discovered):
        raise ValueError("experimental archive manifest omits or invents source IDs")
    missing={r["resource_id"] for r in records if r.get("status")!="VERIFIED"}
    if not missing or missing!=set(reviewed_unavailable):
        raise ValueError("only the exact reviewed upstream source gap may be excluded")
    for row in records:
        source=discovered[row["resource_id"]]
        if (row.get("url")!=source.get("url") or
            row.get("theme")!="raster" or row.get("scale")!=source.get("scale")):
            raise ValueError("experimental archive provenance differs from reviewed discovery")
        if row["resource_id"] in missing:
            exception=reviewed_unavailable[row["resource_id"]]
            if (row.get("status")!="KNOWN_UNAVAILABLE" or
                row.get("upstream_issue")!=exception.get("issue") or
                row.get("sha256") is not None or row.get("archive_bytes") is not None):
                raise ValueError("missing source was not explicitly marked upstream unavailable")
    subset={"schema_version":1,
            "resources":[r for r in records if r["resource_id"] not in missing]}
    proof=verify_manifest(subset,root)
    if not proof["complete"] or proof["verified"]!=len(subset["resources"]):
        raise ValueError("verified subset contains corrupt or unproven publisher archives")
    return subset


def assemble(*,vector:Path,supplement:Path,sources:Path,
             archives:Path,archive_root:Path,vector_pin:Path,
             supplement_pin:Path,out:Path,allow_incomplete:bool=False,
             resume:bool=False,
             reviewed_unavailable:dict[str,dict]|None=None,
             raster_tile_format:str="rgba")->dict:
    out=out.resolve()
    if out.exists():
        raise FileExistsError("offline data pack output already exists: "+str(out))
    out.parent.mkdir(parents=True,exist_ok=True)
    discovery=json.loads(sources.read_text(encoding="utf-8"))
    acquired=json.loads(archives.read_text(encoding="utf-8"))
    pinned=json.loads(vector_pin.read_text(encoding="utf-8"))
    supplemental_pin=json.loads(supplement_pin.read_text(encoding="utf-8"))
    verified=verify_pack.verify_manifest(acquired,archive_root)
    raster_inputs=acquired
    if not verified["complete"]:
        if not allow_incomplete or not reviewed_unavailable:
            raise ValueError("publisher source archives are not fully SHA256/CRC verified")
        raster_inputs=_verified_raster_subset(
            acquired,discovery,archive_root,reviewed_unavailable)
    # Persistent same-volume staging permits bounded, resumable 50+ GB builds.
    root=out.with_name("."+out.name+".assembling")
    # Resume proof lives OUTSIDE the future data pack. A hard kill during
    # final SHA256 hashing or the atomic rename must not destroy recovery.
    checkpoint=root.with_name(root.name+".resume.json")
    legacy_checkpoint=root/".cartorig-build-inputs.json"
    provenance_inputs={
        "schema_version":1,
        "raster_tile_format":raster_tile_format,
        "vector_pin_sha256":build_pack.digest(vector_pin),
        "supplement_pin_sha256":build_pack.digest(supplement_pin),
        "discovery_sha256":build_pack.digest(sources),
        "archives_manifest_sha256":build_pack.digest(archives),
        "primary_vector_sha256":build_pack.digest(vector),
        "supplemental_vector_sha256":build_pack.digest(supplement),
    }
    if root.exists():
        if not resume:
            raise FileExistsError(
                "partial producer build found; use --resume after checking source manifests: "+
                str(root))
        if root.is_symlink() or (not checkpoint.is_file() and not legacy_checkpoint.is_file()):
            raise ValueError("partial build provenance missing; refusing unsafe resume")
        # Migrate an older in-tree checkpoint, but only when its pins agree.
        verified_checkpoint=checkpoint if checkpoint.is_file() else legacy_checkpoint
        if json.loads(verified_checkpoint.read_text(encoding="utf-8"))!=provenance_inputs:
            raise ValueError("partial build provenance differs; refusing unsafe resume")
        if legacy_checkpoint.is_file():
            checkpoint.write_text(json.dumps(provenance_inputs,indent=2)+"\n",
                                  encoding="utf-8")
            legacy_checkpoint.unlink()
    else:
        if checkpoint.exists():
            raise ValueError("orphaned producer checkpoint exists; refuse unsafe new stage")
        root.mkdir(parents=True)
        checkpoint.write_text(json.dumps(provenance_inputs,indent=2)+"\n",
                              encoding="utf-8")
    def ensure_copy(source:Path,target:Path)->None:
        if target.is_file() and not target.is_symlink() and (
                target.stat().st_size==source.stat().st_size and
                build_pack.digest(target)==build_pack.digest(source)):
            return
        target.parent.mkdir(parents=True,exist_ok=True)
        tmp=target.with_name(target.name+".copying")
        tmp.unlink(missing_ok=True)
        shutil.copy2(source,tmp)
        tmp.replace(target)
    for source,target in (
        (vector,root/"vector/natural_earth_vector.gpkg"),
        (supplement,root/"vector/supplements.gpkg"),
        (sources,root/"provenance/official_sources.json"),
        (archives,root/"provenance/source-archives.json"),
        (vector_pin,root/"provenance/vector_layers.json"),
        (supplement_pin,root/"provenance/supplement_pin.json"),
    ):
        if not source.is_file():raise FileNotFoundError(source)
        ensure_copy(source,target)
    catalog=root/"vector/catalog.sqlite"
    rebuild=not catalog.is_file()
    if not rebuild:
        try:
            db=sqlite3.connect(catalog.resolve().as_uri()+"?mode=ro",uri=True)
            try:
                stored=db.execute(
                    "SELECT value FROM metadata WHERE key='source_sha256'").fetchone()
                rebuild=not stored or stored[0]!=provenance_inputs["primary_vector_sha256"]
            finally:db.close()
        except sqlite3.Error:
            rebuild=True
    if rebuild:
        build_catalog.index_source(
            root/"vector/natural_earth_vector.gpkg",catalog)
    raster=build_rasters.compile_archives(
        raster_inputs,archive_root,root/"raster",
        resume=resume,tile_format=raster_tile_format)
    audit=coverage.audit(
        pinned,catalog,discovery,acquired,raster,
        root/"vector/supplements.gpkg",supplemental_pin)
    (root/"provenance/coverage-report.json").write_text(
        json.dumps(audit,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    if reviewed_unavailable and raster_inputs is not acquired and audit["complete"]:
        raise ValueError("experimental upstream gap cannot produce complete certification")
    if not audit["complete"] and not allow_incomplete:
        raise ValueError("Natural Earth Complete audit failed: "+
                         json.dumps({k:v.get("passed") for k,v in audit.items()
                                     if isinstance(v,dict)}))
    # Keep the checkpoint through final hashing and atomic promotion. If the
    # process dies here, the complete staging tree can still be resumed.
    manifest=build_pack.build_pack(
        root,audit,allow_incomplete=allow_incomplete)
    root.replace(out)
    checkpoint.unlink(missing_ok=True)
    return {"pack_id":manifest["pack_id"],"complete":manifest["complete"],
            "raster_sources":raster["sources_converted"],
            "reused_raster_assets":raster.get("reused_assets",0),
            "vector_verified":audit["vector"]["indexed"],
            "files":len(manifest["files"]),"destination":str(out)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("vector","supplement","sources","archives","archive-root",
                 "vector-pin","supplement-pin","out"):
        parser.add_argument("--"+name,type=Path,required=True)
    parser.add_argument("--allow-incomplete",action="store_true")
    parser.add_argument("--resume",action="store_true",
        help="Resume validated staged raster atlas conversions after interruption")
    args=parser.parse_args()
    result=assemble(
        vector=args.vector,supplement=args.supplement,
        sources=args.sources,archives=args.archives,
        archive_root=args.archive_root,vector_pin=args.vector_pin,
        supplement_pin=args.supplement_pin,out=args.out,
        allow_incomplete=args.allow_incomplete,resume=args.resume)
    print(json.dumps(result,indent=2))

if __name__=="__main__":
    main()
