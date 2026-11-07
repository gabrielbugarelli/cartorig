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

def _verify_experimental_source_chain(root:Path,manifest:dict,
                                      hashes:dict[str,str])->None:
    """Cross-check a claimed 51/215 pack against its actual offline content.

    Hashing pack members alone cannot establish that 51 raster identities were
    genuinely processed: the manifest counts must match the source records,
    atlas indexes and their published tile checksums. This is still NOT a
    Natural Earth Complete or a Resolve host certification.
    """
    required=(
        "provenance/official_sources.json",
        "provenance/source-archives.json",
        "provenance/coverage-report.json",
        "raster/validated-raster-assets.json",
    )
    if any(name not in hashes for name in required):
        raise OfflinePackVerificationError(
            "experimental 51/215 pack lacks source/atlas provenance")
    def read(name:str)->dict:
        value=json.loads((root/name).read_text(encoding="utf-8"))
        if not isinstance(value,dict):
            raise OfflinePackVerificationError("invalid provenance JSON: "+name)
        return value
    source=read(required[0])
    archives=read(required[1])
    audit=read(required[2])
    raster=read(required[3])
    expected={
        record.get("resource_id"):record for record in source.get("resources",[])
        if isinstance(record,dict) and record.get("theme")=="raster"}
    received=archives.get("resources",[])
    if (len(expected)!=52 or not isinstance(received,list) or
        len(received)!=52 or
        len({r.get("resource_id") for r in received if isinstance(r,dict)})!=52 or
        set(expected)!={r.get("resource_id") for r in received if isinstance(r,dict)}):
        raise OfflinePackVerificationError("experimental publisher source inventory is not 52 unique rasters")
    verified={}
    missing=[]
    for record in received:
        source_row=expected[record["resource_id"]]
        if (record.get("theme")!="raster" or
            record.get("url")!=source_row.get("url") or
            record.get("scale")!=source_row.get("scale")):
            raise OfflinePackVerificationError("publisher source identity differs from frozen discovery")
        if record.get("status")=="VERIFIED":
            sha=record.get("sha256")
            if (not isinstance(sha,str) or len(sha)!=64 or
                any(c not in "0123456789abcdef" for c in sha) or
                type(record.get("archive_bytes")) is not int or
                record["archive_bytes"]<=0):
                raise OfflinePackVerificationError("verified publisher archive has invalid SHA256/size")
            verified[record["resource_id"]]=sha
        elif record.get("status")=="KNOWN_UNAVAILABLE":
            if (record.get("sha256") is not None or
                record.get("archive_bytes") is not None or
                not record.get("upstream_issue")):
                raise OfflinePackVerificationError("upstream missing source has unverified bytes")
            missing.append(record["resource_id"])
        else:
            raise OfflinePackVerificationError("experimental publisher archive is not verified")
    if len(verified)!=51 or len(missing)!=1:
        raise OfflinePackVerificationError("experimental source coverage must be 51 verified and 1 unavailable")
    if (audit.get("complete") is not False or
        audit.get("vector",{}).get("indexed")!=215 or
        audit.get("raster",{}).get("source_variants")!=52 or
        set(audit.get("raster",{}).get("missing",[]))!=set(missing)):
        raise OfflinePackVerificationError("experimental source audit disagrees with 51/215 coverage")
    assets=raster.get("assets")
    if (raster.get("complete") is not True or
        raster.get("sources_expected")!=51 or
        raster.get("sources_converted")!=51 or raster.get("failures") or
        not isinstance(assets,list) or len(assets)<51):
        raise OfflinePackVerificationError("experimental raster conversion report is incomplete")
    seen_assets=set()
    seen_sources=set()
    for row in assets:
        if not isinstance(row,dict):
            raise OfflinePackVerificationError("invalid experimental raster asset entry")
        asset=row.get("asset_id")
        source_id=row.get("source_id")
        if (not isinstance(asset,str) or
            not asset or len(asset)>121 or
            any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for ch in asset) or
            asset in seen_assets or
            source_id not in verified or row.get("status")!="VALIDATED"):
            raise OfflinePackVerificationError("duplicate or invalid experimental atlas identity")
        seen_assets.add(asset)
        seen_sources.add(source_id)
        base="raster/"+asset+"/"
        index_file=base+"index.json"
        checks_file=base+"tiles.sha256"
        if index_file not in hashes or checks_file not in hashes:
            raise OfflinePackVerificationError("experimental raster atlas lacks index/tile manifest")
        index=read(index_file)
        origin=index.get("provenance",{})
        if (index.get("asset_id")!=asset or
            index.get("format") not in ("cartorig-png-tiles-v2","cartorig-rgba-tiles-v1") or
            origin.get("source_id")!=source_id or
            origin.get("source_sha256")!=verified[source_id] or
            not origin.get("publisher_image") or
            not origin.get("publisher_world_file")):
            raise OfflinePackVerificationError("experimental atlas source SHA256/provenance mismatch")
        declared=set()
        for line in (root/checks_file).read_text(encoding="ascii").splitlines():
            if (len(line)<70 or line[64:66]!="  " or
                len(line[:64])!=64 or
                any(ch not in "0123456789abcdef" for ch in line[:64])):
                raise OfflinePackVerificationError("invalid experimental tile checksum line")
            tile=base+line[66:]
            if tile in declared or not tile.startswith(base+"tiles/") or hashes.get(tile)!=line[:64]:
                raise OfflinePackVerificationError("experimental tile checksum differs from pack member")
            declared.add(tile)
        packaged={name for name in hashes if name.startswith(base+"tiles/")}
        if not declared or declared!=packaged:
            raise OfflinePackVerificationError("experimental atlas has missing/extra raster tiles")
    if seen_sources!=set(verified):
        raise OfflinePackVerificationError("not all 51 verified publisher rasters have a rendered atlas")


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
    # An experimental pack with nonzero 51/215 coverage claims must also
    # prove source-to-atlas traceability, not only its self-declared pack hash.
    experimental_chain_verified=False
    if not complete and (manifest.get("raster_sources")==51 or
                         manifest.get("vector_sources")==215):
        if (manifest.get("raster_sources"),manifest.get("vector_sources"))!=(51,215):
            raise OfflinePackVerificationError("inconsistent experimental 51/215 counts")
        _verify_experimental_source_chain(
            root,manifest,{item["path"]:item["sha256"] for item in items})
        experimental_chain_verified=True
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
            "vector_sources":manifest.get("vector_sources",0),
            "experimental_source_chain_verified":experimental_chain_verified}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",required=True,type=Path)
    parser.add_argument("--allow-incomplete",action="store_true")
    args=parser.parse_args()
    print(json.dumps(verify_release(args.root,
               allow_incomplete=args.allow_incomplete),indent=2))

if __name__=="__main__":
    main()
