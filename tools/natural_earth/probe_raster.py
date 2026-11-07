#!/usr/bin/env python3
"""Real official 50m raster ZIP -> atlas tiles -> native C++ rendered pixels.

Opt-in release-machine probe; never part of ordinary CI, never in Resolve.
Publisher archives/tiles remain on the transient runner and only small JSON
evidence is uploaded. The official SHA256 is cross-checked against the
previously committed independent real family sample observation.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess

from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.build_rasters import compile_archives
from tools.natural_earth.verify_pack import verify_zip

OFFICIAL_URL="https://naturalearth.s3.amazonaws.com/50m_raster/MSR_50M.zip"
PUBLISHER_NAME="MSR_50M.zip"
FAMILY="50m-manual-shaded-relief"
NATIVE_PROOF=re.compile(
    r"^raster_pixels=(\d+) frame_hash=(\d+) atlas_levels=(\d+)$")


def expected_official_sample(observations:Path)->dict:
    """Pin the actual publisher archive to a different, earlier GitHub probe."""
    data=json.loads(observations.read_text(encoding="utf-8"))
    if (data.get("schema_version")!=1 or
        data.get("format")!="cartorig-natural-earth-family-sample-observation-v1"):
        raise ValueError("unexpected independent publisher sample evidence schema")
    matches=[r for r in data.get("observations",[]) if
             r.get("family")==FAMILY and r.get("archive")==PUBLISHER_NAME]
    if len(matches)!=1:
        raise ValueError("missing or duplicate independently acquired official sample")
    expected=matches[0]
    if (expected.get("scale")!="50m" or
        expected.get("source_url")!=
            "https://www.naturalearthdata.com/download/50m/raster/MSR_50M.zip" or
        expected.get("archive_bytes")!=17984241 or
        expected.get("observed_sha256")!=
            "e38f8b256f64eccae250a1e482761d4a7a585e6602c941e6bdb860e160faf609"):
        raise ValueError("publisher sample observation differs from approved evidence")
    return expected


def probe(out:Path, preview:Path,observations:Path,
          *, downloader=download_and_hash,renderer=subprocess.run)->dict:
    expected=expected_official_sample(observations)
    out.mkdir(parents=True,exist_ok=True)
    publisher=out/"publisher"
    publisher.mkdir(exist_ok=True)
    archive=publisher/PUBLISHER_NAME
    size,sha=downloader(OFFICIAL_URL,archive,max_bytes=60_000_000)
    if size!=expected["archive_bytes"] or sha!=expected["observed_sha256"]:
        raise ValueError("real publisher MSR_50M archive differs from approved independent SHA256")
    zip_proof=verify_zip(archive,max_uncompressed=12_000_000_000)
    record={
        "resource_id":"ne-50m-raster-manual-shaded-relief",
        "scale":"50m","theme":"raster","label":"Manual Shaded Relief 50m",
        "url":OFFICIAL_URL,"file":archive.name,"archive_bytes":size,
        "sha256":sha,"status":"VERIFIED",
    }
    root=out/"rasters"
    report=compile_archives({"schema_version":1,"resources":[record]},publisher,root)
    if (not report["complete"] or report["sources_converted"]!=1 or
        not report["assets"] or report["failures"]):
        raise RuntimeError("real publisher raster conversion failed: "+repr(report))
    assets=[]
    raw_bytes=0
    total_tiles=0
    for asset in report["assets"]:
        ident=asset["asset_id"]
        meta=json.loads((root/ident/"index.json").read_text(encoding="utf-8"))
        if (meta.get("format")!="cartorig-rgba-tiles-v1" or
            meta.get("provenance",{}).get("source_sha256")!=sha):
            raise RuntimeError("raster atlas source provenance was lost")
        counts=[level["tiles_x"]*level["tiles_y"] for level in meta["levels"]]
        tiles=sum(counts)
        if tiles<=0:
            raise RuntimeError("publisher raster produced no real atlas tiles")
        actual_tiles=list((root/ident/"tiles").rglob("*.rgba"))
        if len(actual_tiles)!=tiles:
            raise RuntimeError("publisher raster tile count mismatch")
        byte_count=sum(p.stat().st_size for p in actual_tiles)
        if byte_count!=tiles*256*256*4:
            raise RuntimeError("raw atlas tiles disagree with 256x256 RGBA contract")
        output=renderer([str(preview),str(root),ident],
                        capture_output=True,text=True,timeout=90)
        if output.returncode!=0:
            raise RuntimeError("native C++ raster preview failed: "+
                               output.stderr[:900])
        match=NATIVE_PROOF.fullmatch(output.stdout.strip())
        if not match:
            raise RuntimeError("native raster preview evidence is malformed: "+
                               output.stdout[:300])
        native_pixels,native_frame_hash,native_levels=map(int,match.groups())
        if native_pixels<100 or native_levels!=len(meta["levels"]) or native_frame_hash==0:
            raise RuntimeError("native C++ raster rendered invalid pixels/LOD")
        total_tiles+=tiles
        raw_bytes+=byte_count
        assets.append({
            "asset_id":ident,
            "publisher_image":meta["provenance"]["publisher_image"],
            "publisher_world_file":meta["provenance"]["publisher_world_file"],
            "original_size":[meta["original_width"],meta["original_height"]],
            "extent":meta["extent"],
            "lod_levels":len(meta["levels"]),
            "tile_count":tiles,
            "raw_tile_bytes":byte_count,
            "native_rendered_pixels":native_pixels,
            "native_frame_hash":native_frame_hash,
        })
    proof={
        "schema_version":1,
        "source_url":OFFICIAL_URL,
        "source_sha256":sha,
        "source_sha256_independently_matched":True,
        "archive_bytes":size,
        "zip_crc_verified":True,
        "zip_member_count":zip_proof["members"],
        "converted_source_count":report["sources_converted"],
        "atlas_asset_count":len(assets),
        "total_atlas_tiles":total_tiles,
        "total_raw_rgba_tile_bytes":raw_bytes,
        "assets":assets,
        "scope":"one official 50m raster; not a 51/52 production pack or real DaVinci Resolve host test",
    }
    (out/"real-raster-proof.json").write_text(
        json.dumps(proof,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    return proof


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--preview",type=Path,required=True)
    parser.add_argument("--observations",type=Path,default=Path(
        "data/natural-earth/family_sample_observations_2026-11-07.json"))
    args=parser.parse_args()
    proof=probe(args.out,args.preview,args.observations)
    print(json.dumps(proof,indent=2))


if __name__=="__main__":
    main()
