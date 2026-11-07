#!/usr/bin/env python3
"""Build a non-distributable experimental offline Natural Earth pack (51/52).

Only for LOCAL DaVinci Resolve Studio 20 acceptance testing while one official
raster archive remains unavailable. The 52-source audit and the genuine missing
record stay intact; pack.complete=False and status=EXPERIMENTAL_INCOMPLETE.
Production release_pipeline and its 52-source SHA256 locks are NOT weakened.

Example:
 py -m tools.natural_earth.build_experimental --workspace D:\CartoRigBuild \
   --output D:\CartoRigExperimental --allow-network --max-downloads 12
Repeat until all 51 *available* publisher sources have been acquired.
Installed OpenFX never downloads or imports Python.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

from tools.natural_earth import (
    acquire_available, assemble_pack, known_unavailable,
    release_pipeline, verify_release
)


def produce(*,workspace:Path,output:Path,allow_network:bool=False,
            max_downloads:int=12,project_root:Path|None=None)->dict:
    root=(project_root or Path(__file__).resolve().parents[2]).resolve()
    workspace=workspace.resolve()
    output=output.resolve()
    if output.exists():
        raise FileExistsError("experimental data-pack output already exists")
    source_status=acquire_available.acquire(
        workspace=workspace,project_root=root,
        allow_network=allow_network,max_downloads=max_downloads,
        skip_reviewed_unavailable=True)
    if source_status["status"]!="AVAILABLE_SOURCES_VERIFIED_NOT_CERTIFIED":
        raise release_pipeline.ReleaseNotReady(
            "Experimental pack requires all 51 available official raster ZIPs "
            "independently verified; current acquisition status: "+
            source_status["status"]+" ("+
            str(source_status["verified_archives"])+"/52)")
    inventory=json.loads((workspace/"official_sources.json").read_text(
        encoding="utf-8"))
    exceptions=known_unavailable.read_verified(root,inventory)
    vector=release_pipeline._extract_pinned_vector(workspace,allow_network)
    supplement_pin=root/"data/natural-earth/aggregate_geojson_supplements_v5.1.2.json"
    vector_pin=root/"data/natural-earth/vector_layers_v5.1.2.json"
    supplement_manifest=json.loads(supplement_pin.read_text(encoding="utf-8"))
    supplemental=release_pipeline._make_supplements(
        workspace,supplement_manifest,allow_network)
    built=assemble_pack.assemble(
        vector=vector,supplement=supplemental,
        sources=workspace/"official_sources.json",
        archives=workspace/"downloads/source-archives.json",
        archive_root=workspace/"downloads",
        vector_pin=vector_pin,supplement_pin=supplement_pin,
        out=output,resume=True,allow_incomplete=True,
        reviewed_unavailable=exceptions)
    if built["complete"]:
        raise ValueError("unexpected certification: an experimental pack MUST NOT be complete")
    audited=verify_release.verify_release(output,allow_incomplete=True)
    if audited["complete"] is not False or audited["pack_id"]!=built["pack_id"]:
        raise ValueError("experimental offline pack verification/identity mismatch")
    return {
        "status":"EXPERIMENTAL_INCOMPLETE",
        "release_certified":False,
        "pack_id":built["pack_id"],
        "verified_available_rasters":source_status["verified_archives"],
        "known_unavailable":source_status["known_unavailable"],
        "vector_sources_indexed":built["vector_verified"],
        "converted_raster_sources":built["raster_sources"],
        "destination":str(output),
        "note":"For offline Resolve QA only; never publish as Natural Earth Complete.",
    }


def main()->None:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--workspace",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--allow-network",action="store_true")
    p.add_argument("--max-downloads",type=int,default=12)
    opts=p.parse_args()
    try:
        proof=produce(workspace=opts.workspace,output=opts.output,
                      allow_network=opts.allow_network,max_downloads=opts.max_downloads)
        print(json.dumps(proof,indent=2))
    except release_pipeline.ReleaseNotReady as error:
        print(json.dumps({"status":"INCOMPLETE","reason":str(error)},indent=2))
        raise SystemExit(2) from error

if __name__=="__main__":main()
