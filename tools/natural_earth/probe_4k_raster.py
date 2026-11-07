#!/usr/bin/env python3
"""Native 720p/1440p/4K REAL publisher TIFF->atlas->C++ QA, not Resolve QA.

Source ZIP, TIFFs and atlas tiles remain transient and are deleted on return.
The JSON-only report records independently observed publisher SHA256/CRC,
lossless raw-vs-PNG native frame parity, resolution-level hashes and timings.
Use only with explicit one-off [real-4k-probe] on standard free CI runners.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

from tools.natural_earth import probe_raster
from tools.natural_earth.build_rasters import compile_archives, reusable_asset
from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.verify_pack import verify_zip

FIRST=re.compile(r"^raster_pixels=(\d+) frame_hash=(\d+) atlas_levels=(\d+)$")
MATRIX=re.compile(
    r"^bench_width=(\d+) bench_height=(\d+) bench_passes=(\d+) "
    r"median_frame_ms=(\d+\.\d{3}) frame_hash=(\d+) raster_pixels=(\d+)$")
REQUIRED_RESOLUTIONS=((1280,720),(2560,1440),(3840,2160))
MSR_ORIGINAL_FRAME_HASH="13112041101257582482"

def parse_matrix(text:str)->dict:
    lines=text.strip().splitlines()
    if len(lines)!=4:
        raise ValueError("expected source native frame proof and exactly three render sizes")
    first=FIRST.fullmatch(lines[0])
    if not first:
        raise ValueError("original 640x360 native hash proof is invalid")
    pixels,original_hash,levels=map(int,first.groups())
    if (pixels!=230400 or str(original_hash)!=MSR_ORIGINAL_FRAME_HASH or
            levels!=7):
        raise ValueError("native raster changed from verified 50m source frame baseline")
    matrix={}
    for (w,h),line in zip(REQUIRED_RESOLUTIONS,lines[1:]):
        parsed=MATRIX.fullmatch(line)
        if not parsed:
            raise ValueError("resolution-matrix native evidence malformed")
        rw,rh,passes,ms,hashval,count=parsed.groups()
        if ((int(rw),int(rh))!=(w,h) or int(passes)!=5 or
                float(ms)<=0 or int(hashval)==0 or
                int(count)!=w*h):
            raise ValueError("native renderer did not paint entire required frame")
        matrix[f"{w}x{h}"]={
            "width":w,"height":h,"passes":5,
            "median_full_frame_ms":float(ms),
            "frame_hash":hashval,
            "painted_pixels":int(count)}
    return {"original_640x360_frame_hash":str(original_hash),
            "atlas_levels":levels,"resolution_matrix":matrix}


def probe(out:Path,exe:Path,observations:Path,
          *,downloader=download_and_hash,runner=subprocess.run)->dict:
    source=probe_raster.expected_official_sample(observations)
    out.mkdir(parents=True,exist_ok=True)
    staging=out/"temporary-real-raster"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    result={
        "schema_version":1,
        "format":"cartorig-natural-earth-real-native-4k-qa-v1",
        "official_archive_url":probe_raster.OFFICIAL_URL,
        "archive_source_sha256":source["observed_sha256"],
        "complete":False,
        "real_davinci_resolve_host_test":False,
        "certified_natural_earth_full_pack":False,
        "note":"Native C++ tests only. Exact Resolve Studio 20 Generator/Overlay/Inspector acceptance requires local licensed host.",
    }
    proof_path=out/"native-4k-qa.json"
    def save():
        tmp=proof_path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(result,sort_keys=True,indent=2)+"\n",
                       encoding="utf-8")
        tmp.replace(proof_path)
    save()
    try:
        archive=staging/probe_raster.PUBLISHER_NAME
        n,digest=downloader(probe_raster.OFFICIAL_URL,archive,
                            max_bytes=60_000_000)
        if n!=source["archive_bytes"] or digest!=source["observed_sha256"]:
            raise ValueError("official raster ZIP is not the previously SHA256-verified source")
        verified=verify_zip(archive,max_uncompressed=12_000_000_000)
        record={
            "resource_id":"ne-50m-raster-native-4k",
            "scale":"50m","theme":"raster",
            "url":probe_raster.OFFICIAL_URL,
            "file":archive.name,"archive_bytes":n,
            "sha256":digest,"status":"VERIFIED",
        }
        by_format={}
        for fmt in ("rgba","png"):
            root=staging/("atlas_"+fmt)
            compiled=compile_archives(
                {"schema_version":1,"resources":[record]},staging,root,
                tile_format=fmt)
            if (not compiled.get("complete") or
                    compiled.get("sources_converted")!=1 or
                    len(compiled.get("assets",[]))!=1):
                raise ValueError("real source atlas compilation incomplete: "+str(
                    compiled.get("failures"))[:900])
            asset=compiled["assets"][0]["asset_id"]
            meta=json.loads((root/asset/"index.json").read_text(encoding="utf-8"))
            original=meta["provenance"]
            if (original["source_sha256"]!=digest or
                    not reusable_asset(root,asset,digest,
                                       original["publisher_image"],
                                       original["publisher_world_file"],
                                       tile_format=fmt)):
                raise ValueError("publisher source/atlas PNG or RGBA SHA256 mismatch")
            command=[str(exe),str(root),asset,"--bench-matrix"]
            rendered=runner(command,capture_output=True,text=True,timeout=180,
                            check=False)
            if rendered.returncode!=0:
                raise RuntimeError("native raster 4k benchmark failed: "+
                                   rendered.stderr[-1100:])
            data=parse_matrix(rendered.stdout)
            total_bytes=sum(p.stat().st_size for p in
                            (root/asset/"tiles").rglob("*."+fmt))
            by_format[fmt]={
                "tile_format":meta["format"],
                "tiles":sum(l["tiles_x"]*l["tiles_y"] for l in meta["levels"]),
                "atlas_bytes":total_bytes,
                **data,
            }
            save()
        for size in (f"{w}x{h}" for w,h in REQUIRED_RESOLUTIONS):
            a=by_format["rgba"]["resolution_matrix"][size]
            b=by_format["png"]["resolution_matrix"][size]
            if a["frame_hash"]!=b["frame_hash"] or a["painted_pixels"]!=b["painted_pixels"]:
                raise ValueError("native 1440p or 4k lossy output between legacy RGBA and PNG")
        if by_format["rgba"]["tiles"]!=by_format["png"]["tiles"]:
            raise ValueError("source atlas LOD count changed between formats")
        result.update({
            "complete":True,
            "official_zip_size_bytes":n,
            "official_zip_crc_members":verified["members"],
            "source_verified_sha256":True,
            "native_rgba_png_same_pixel_hash_at_720_1440_4k":True,
            "formats":by_format,
        })
    except Exception as error:
        result["error"]=type(error).__name__+": "+str(error)[:1000]
        raise
    finally:
        save()
        shutil.rmtree(staging,ignore_errors=True)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",required=True,type=Path)
    parser.add_argument("--preview",required=True,type=Path)
    parser.add_argument("--observations",type=Path,
                        default=Path("data/natural-earth/family_sample_observations_2026-11-07.json"))
    opts=parser.parse_args()
    result=probe(opts.out,opts.preview,opts.observations)
    print(json.dumps({"complete":result["complete"],
                      "formats":result["formats"]},indent=2))


if __name__=="__main__":
    main()
