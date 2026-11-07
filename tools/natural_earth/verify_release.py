#!/usr/bin/env python3
"""Offline cross-platform verification of the installed Natural Earth data pack.

Rehash every file, validate the canonical SHA256 pack ID, and reject extra
files, symlinks, missing metadata or incomplete certification. No network.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from typing import Any
from tools.natural_earth.build_pack import PACK_PATH,REQUIRED,MAX_FILES,digest

class OfflinePackVerificationError(ValueError):
    pass

def verify_release(root:Path,*,allow_incomplete:bool=False)->dict[str,Any]:
    root=root.resolve(strict=True)
    if not root.is_dir():
        raise OfflinePackVerificationError("data pack root must be a directory")
    manifest_file=root/"pack.json"
    if not manifest_file.is_file():
        raise OfflinePackVerificationError("offline pack.json not found")
    manifest=json.loads(manifest_file.read_text(encoding="utf-8"))
    if manifest.get("schema_version")!=1 or manifest.get("format")!=\
            "cartorig-natural-earth-offline-v1":
        raise OfflinePackVerificationError("unsupported Natural Earth pack format")
    complete=manifest.get("complete") is True
    if not complete and not allow_incomplete:
        raise OfflinePackVerificationError("incomplete experimental data pack is not permitted")
    expected_status=("NATURAL_EARTH_COMPLETE" if complete else
                     "EXPERIMENTAL_INCOMPLETE")
    if manifest.get("status")!=expected_status:
        raise OfflinePackVerificationError("inconsistent pack certification status")
    items=manifest.get("files")
    if not isinstance(items,list) or not 1<=len(items)<=MAX_FILES:
        raise OfflinePackVerificationError("offline pack file count is invalid")
    names=set()
    total_bytes=0
    for item in items:
        if not isinstance(item,dict) or set(item)!={"path","bytes","sha256"}:
            raise OfflinePackVerificationError("invalid file manifest entry")
        rel=item["path"]
        size=item["bytes"]
        digest_expected=item["sha256"]
        if (not isinstance(rel,str) or not PACK_PATH.fullmatch(rel) or
            ".." in Path(rel).parts or rel in names or rel=="pack.json"):
            raise OfflinePackVerificationError("duplicate or unsafe pack path")
        if (type(size) is not int or size<0 or
            not isinstance(digest_expected,str) or len(digest_expected)!=64 or
            any(c not in "0123456789abcdef" for c in digest_expected)):
            raise OfflinePackVerificationError("invalid pack hash or byte count")
        names.add(rel)
        path=root/rel
        if path.is_symlink() or not path.is_file():
            raise OfflinePackVerificationError("missing or linked offline file: "+rel)
        if path.stat().st_size!=size or digest(path)!=digest_expected:
            raise OfflinePackVerificationError("tampered offline pack file: "+rel)
        total_bytes+=size
    if not set(REQUIRED).issubset(names):
        raise OfflinePackVerificationError("essential vector/raster data are missing")
    for path in root.rglob("*"):
        if path.is_symlink():
            raise OfflinePackVerificationError("offline pack contains a symlink")
        if path.is_file() and path.relative_to(root).as_posix() not in names|{"pack.json"}:
            raise OfflinePackVerificationError("undeclared file in offline pack: "+
                                               path.relative_to(root).as_posix())
    stable=json.dumps(items,sort_keys=True,separators=(",",":")).encode("utf-8")
    actual_id=hashlib.sha256(stable).hexdigest()
    if actual_id!=manifest.get("pack_id"):
        raise OfflinePackVerificationError("offline pack identity hash mismatch")
    if complete:
        audit=root/"provenance/coverage-report.json"
        if not audit.is_file():
            raise OfflinePackVerificationError("certified pack lacks provenance audit")
        report=json.loads(audit.read_text(encoding="utf-8"))
        if (report.get("complete") is not True or
            report.get("vector",{}).get("indexed")!=215 or
            report.get("raster",{}).get("source_variants",0)<52 or
            report.get("archives",{}).get("pack_verified") is not True):
            raise OfflinePackVerificationError(
                "certified Natural Earth report fails full publisher gates")
    return {"pack_id":actual_id,"complete":complete,"files_verified":len(items),
            "verified_bytes":total_bytes,"raster_sources":manifest.get("raster_sources",0),
            "vector_sources":manifest.get("vector_sources",0)}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",required=True,type=Path)
    parser.add_argument("--allow-incomplete",action="store_true")
    args=parser.parse_args()
    print(json.dumps(verify_release(args.root,
               allow_incomplete=args.allow_incomplete),indent=2))

if __name__=="__main__":
    main()
