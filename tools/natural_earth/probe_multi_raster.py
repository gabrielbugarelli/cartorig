#!/usr/bin/env python3
"""NE-M3: bounded, real multi-family Natural Earth raster conversion and QA.

Explicit one-off publisher probe on a FREE standard public CI runner only.
Downloads exact SHA256-pinned previously observed Natural Earth ZIPs and
generates PNG v2 and legacy raw RGBA v1 separately, one family at a time.
Verifies all LOD tile hashes, native C++ pixel hash equality and measured
720p full-frame renderer medians (I/O + decode + projection + compositing).
Only JSON evidence is published, never the ZIP, TIFF or atlas.

This evidence is NOT full 52/52 source acquisition or a Resolve 20 host test.
Native performance iteration also benchmarks per-row tile reuse after the
original reference-projection parity and SHA-verified publisher baselines.
Standard free public Ubuntu runner is explicitly opt-in via [multi-raster-probe].
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
from typing import Any

from tools.natural_earth.build_rasters import compile_archives, reusable_asset
from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.verify_pack import verify_zip

SAMPLE_FAMILIES=(
    "50m-gray-earth",
    "50m-prisma-shaded-relief",
    "50m-shaded-relief",
)
# Previously verified by genuine 2026-11-07 official publisher family probe.
# These immutable SHA values are observed publisher archive digests, not
# authoritative publisher-signed hashes and NOT the required 52-source lock.
ALLOWED_SAMPLES={
    "50m-gray-earth":(
        "GRAY_50M_SR_W.zip",10983477,
        "25230eaa5c82c9e913b9acede197e29e575817e36df9925231c1a1b92a101d8c"),
    "50m-prisma-shaded-relief":(
        "PRISMA_SR_50M.zip",17991035,
        "2aa9c316bb767b4c4aecbb1c2de255d00d43ab93e7d837e85f01a6dc4e2043fe"),
    "50m-shaded-relief":(
        "SR_50M.zip",11380369,
        "ff810f5f2747463fd8ffa612b23e5f5e5d593a345218976872b6749610976ab7"),
}
# Frame hashes were measured in the previous independent, unoptimized
# official-source run: https://github.com/gabrielbugarelli/cartorig/actions/runs/42344497361
# Re-running after any renderer optimization MUST remain bit-identical.
LEGACY_NATIVE_FRAME_HASHES={
    "50m-gray-earth":"13024482577733760989",
    "50m-prisma-shaded-relief":"11708255958712787630",
    "50m-shaded-relief":"6987416738967865316",
}
PROOF_LINE=re.compile(r"^raster_pixels=(\d+) frame_hash=(\d+) atlas_levels=(\d+)$")
BENCH_LINE=re.compile(
    r"^bench_width=1280 bench_height=720 bench_passes=5 median_frame_ms=(\d+\.\d{3})$")

def select_sources(observations:dict)->list[dict[str,Any]]:
    """Never derive network downloads from a mutable unreviewed URL."""
    if (observations.get("schema_version")!=1 or
        observations.get("format")!="cartorig-natural-earth-family-sample-observation-v1" or
        observations.get("archive_source_count")!=52 or
        observations.get("verified_family_samples")!=15):
        raise ValueError("unreviewed or malformed Natural Earth sample observations")
    seen={}
    for row in observations.get("observations",[]):
        family=row.get("family")
        if family in ALLOWED_SAMPLES:
            if family in seen:
                raise ValueError("duplicate observed publisher family")
            filename,size,digest=ALLOWED_SAMPLES[family]
            publisher=f"https://www.naturalearthdata.com/download/50m/raster/{filename}"
            if (row.get("archive")!=filename or
                row.get("source_url")!=publisher or
                row.get("archive_bytes")!=size or
                row.get("observed_sha256")!=digest or
                row.get("validation")!="ZIP_CRC_PASS_WORLD_FILE_PAIR_FOUND"):
                raise ValueError("publisher sample metadata differs from independently observed SHA256")
            seen[family]={
                "family":family,"archive":filename,
                "archive_bytes":size,"sha256":digest,
                "url":f"https://naturalearth.s3.amazonaws.com/50m_raster/{filename}",
                "publisher_url":publisher,
            }
    if set(seen)!=set(SAMPLE_FAMILIES):
        raise ValueError("not all selected publisher families have independently verified evidence")
    return [seen[f] for f in SAMPLE_FAMILIES]


def native_proof(executable:Path,atlas_root:Path,asset_id:str)->dict:
    result=subprocess.run(
        [str(executable),str(atlas_root),asset_id,"--bench"],
        capture_output=True,text=True,timeout=150,check=False)
    if result.returncode!=0:
        raise RuntimeError("native raster decoder failed: "+result.stderr[-850:])
    lines=result.stdout.strip().splitlines()
    if len(lines)!=2:
        raise ValueError("unexpected native preview/benchmark evidence")
    painted=PROOF_LINE.fullmatch(lines[0])
    measured=BENCH_LINE.fullmatch(lines[1])
    if not painted or not measured:
        raise ValueError("malformed native publisher proof")
    px,frame_hash,levels=map(int,painted.groups())
    ms=float(measured.group(1))
    if px!=230400 or frame_hash==0 or not 0<ms<150000:
        raise ValueError("invalid native frame/renderer benchmark")
    return {
        "rendered_pixels":px,
        "native_frame_hash":str(frame_hash),
        "atlas_levels":levels,
        "benchmark_720p_passes":5,
        "median_720p_full_frame_ms":ms,
    }


def convert_and_compare(source:dict,workspace:Path,preview:Path,
                        *,downloader=download_and_hash)->dict:
    """One official archive at a time; discard all large contents after QA."""
    record={"family":source["family"],"archive":source["archive"],
            "official_source_url":source["publisher_url"],
            "expected_source_sha256":source["sha256"],
            "expected_archive_bytes":source["archive_bytes"],
            "status":"STARTED"}
    staging=workspace/source["family"]
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    try:
        archive=staging/source["archive"]
        size,digest=downloader(
            source["url"],archive,max_bytes=60_000_000)
        if (size!=source["archive_bytes"] or digest!=source["sha256"] or
            archive.stat().st_size!=size):
            raise ValueError("published ZIP differs from previously observed source SHA256")
        zipp=verify_zip(archive,max_uncompressed=12_000_000_000)
        manifest={"schema_version":1,"resources":[{
            "resource_id":"ne-"+source["family"].replace("-","_"),
            "theme":"raster","scale":"50m","file":archive.name,
            "url":source["publisher_url"],"archive_bytes":size,
            "sha256":digest,"status":"VERIFIED"}]}
        images={}
        for fmt in ("rgba","png"):
            root=staging/fmt
            started=time.perf_counter()
            conversion=compile_archives(
                manifest,staging,root,tile_format=fmt)
            convert_sec=round(time.perf_counter()-started,3)
            if (not conversion.get("complete") or
                conversion.get("sources_converted")!=1 or
                conversion.get("failures") or
                not conversion.get("assets")):
                raise ValueError("publisher "+fmt+" conversion failed: "+
                                 repr(conversion.get("failures",[]))[:1200])
            assets={}
            for asset in conversion["assets"]:
                asset_id=asset["asset_id"]
                metadata=json.loads((root/asset_id/"index.json").read_text(encoding="utf-8"))
                if not reusable_asset(
                    root,asset_id,digest,
                    metadata["provenance"]["publisher_image"],
                    metadata["provenance"]["publisher_world_file"],tile_format=fmt):
                    raise ValueError("publisher "+fmt+" tile SHA256 and LOD integrity failed")
                tiles=list((root/asset_id/"tiles").rglob("*."+fmt))
                if len(tiles)!=sum(l["tiles_x"]*l["tiles_y"] for l in metadata["levels"]):
                    raise ValueError("real publisher tile count disagrees with LOD metadata")
                total_bytes=sum(path.stat().st_size for path in tiles)
                metrics=native_proof(preview,root,asset_id)
                if metrics["atlas_levels"]!=len(metadata["levels"]):
                    raise ValueError("native renderer has wrong atlas LOD metadata")
                assets[asset_id]={
                    "source_image":metadata["provenance"]["publisher_image"],
                    "source_world_file":metadata["provenance"]["publisher_world_file"],
                    "image_size":[metadata["original_width"],metadata["original_height"]],
                    "extent":metadata["extent"],
                    "tile_count":len(tiles),
                    "atlas_bytes":total_bytes,
                    "levels":len(metadata["levels"]),
                    "renderer":metrics,
                }
            images[fmt]={"conversion_seconds":convert_sec,"assets":assets}
        if set(images["rgba"]["assets"])!=set(images["png"]["assets"]):
            raise ValueError("PNG and raw conversion source image sets differ")
        total_bytes={fmt:sum(
            asset["atlas_bytes"] for asset in images[fmt]["assets"].values())
            for fmt in ("rgba","png")}
        for ident in images["rgba"]["assets"]:
            old=images["rgba"]["assets"][ident]
            new=images["png"]["assets"][ident]
            if (old["renderer"]["native_frame_hash"]!=new["renderer"]["native_frame_hash"] or
                old["renderer"]["rendered_pixels"]!=new["renderer"]["rendered_pixels"] or
                old["extent"]!=new["extent"] or old["levels"]!=new["levels"]):
                raise ValueError("native PNG/RGBA pixel or geographic parity mismatch")
            if old["renderer"]["native_frame_hash"]!=LEGACY_NATIVE_FRAME_HASHES[source["family"]]:
                raise ValueError("native optimized raster frame differs from previous official source baseline")
        record.update({
            "status":"VERIFIED_REAL_PUBLISHER_NATIVE_PARITY",
            "publisher_zip_sha256_matches_previous_independent_observation":True,
            "publisher_zip_crc_members":zipp["members"],
            "assets":images,
            "raw_rgba_bytes":total_bytes["rgba"],
            "png_v2_bytes":total_bytes["png"],
            "storage_reduction_pct":round(
                100*(1-total_bytes["png"]/total_bytes["rgba"]),2),
            "note":"Native benchmark is host-runner 720p full renderer, not isolated decoder or Resolve host FPS."
        })
        return record
    finally:
        # No publisher binaries, ZIP, TIFFs or native atlases persist in CI artifacts.
        shutil.rmtree(staging,ignore_errors=True)


def run(*,out:Path,preview:Path,observations:Path,
        selected_families:tuple[str,...]=SAMPLE_FAMILIES)->dict:
    sources=select_sources(json.loads(observations.read_text(encoding="utf-8")))
    if not selected_families or len(selected_families)!=len(set(selected_families)) or (
        not set(selected_families).issubset(SAMPLE_FAMILIES)):
        raise ValueError("unreviewed probe family selection")
    out.mkdir(parents=True,exist_ok=True)
    report={
        "schema_version":1,
        "format":"cartorig-ne-real-multifamily-raster-probe-v1",
        "verified_real_families":0,
        "families_requested":len(selected_families),
        "complete":False,
        "distribution_ready":False,
        "resolve_host_test":False,
        "families":[],
    }
    def checkpoint():
        path=out/"multi-raster-proof.json"
        tmp=path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        tmp.replace(path)
    checkpoint()
    for source in sources:
        if source["family"] not in selected_families:
            continue
        try:
            result=convert_and_compare(source,out/"staging",preview)
            report["families"].append(result)
            report["verified_real_families"]+=1
        except Exception as exc:
            report["families"].append({
                "family":source["family"],
                "status":"FAILED_REAL_SOURCE_QA",
                "reason":type(exc).__name__+": "+str(exc)[:1300],
            })
        checkpoint()
    report["complete"]=report["verified_real_families"]==len(selected_families)
    checkpoint()
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--preview",type=Path,required=True)
    parser.add_argument("--observations",type=Path,
                        default=Path("data/natural-earth/family_sample_observations_2026-11-07.json"))
    parser.add_argument("--families",nargs="*",choices=SAMPLE_FAMILIES)
    args=parser.parse_args()
    selected=tuple(args.families) if args.families else SAMPLE_FAMILIES
    result=run(out=args.out,preview=args.preview,observations=args.observations,
               selected_families=selected)
    print(json.dumps({k:v for k,v in result.items() if k!="families"},indent=2))
    if not result["complete"]:
        raise SystemExit("one or more pinned official raster families failed real native conversion")


if __name__=="__main__":
    main()
