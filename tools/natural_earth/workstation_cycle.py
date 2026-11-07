#!/usr/bin/env python3
"""Local release-workstation cycle: 51 publisher ZIPs -> offline experimental QA pack.

This command MUST run on a persistent workstation, never in the installed OFX
plugin. Its only network operations are explicitly enabled by --allow-network,
and are routed through audited official Natural Earth publisher downloader.

It can acquire/reverify all 51 currently available archives, produce a
completely verified EXPERIMENTAL_INCOMPLETE 51/52 pack, and test genuine
installed raster assets at native 720p/1440p/4K. A native C++ preview is
NOT a DaVinci Resolve 20 host test. Full Natural Earth certification remains
blocked by the original 52nd publisher source.
The Windows kit deliberately ships no publisher data; the release workstation
must obtain the real source bytes and record its own SHA256 evidence.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any,Callable

from tools.natural_earth import acquire_available, build_experimental, verify_release

MATRIX=re.compile(
    r"^bench_width=(\d+) bench_height=(\d+) bench_passes=(\d+) "
    r"median_frame_ms=(\d+\.\d{3}) frame_hash=(\d+) raster_pixels=(\d+)$")
BASIC=re.compile(r"^raster_pixels=(\d+) frame_hash=(\d+) atlas_levels=(\d+)$")
SIZES=((1280,720),(2560,1440),(3840,2160))
REPORT_FORMAT="cartorig-ne-workstation-qa-v1"

class QAIncomplete(RuntimeError):
    pass

def parse_native_matrix(raw:str)->dict:
    lines=raw.strip().splitlines()
    if len(lines)!=4 or not (head:=BASIC.fullmatch(lines[0])):
        raise QAIncomplete("native renderer did not return a complete 4-size proof")
    pixels,frame,levels=map(int,head.groups())
    if pixels<100 or frame==0 or not 1<=levels<=20:
        raise QAIncomplete("native raster failed 640x360 baseline paint")
    samples={}
    for (w,h),line in zip(SIZES,lines[1:]):
        match=MATRIX.fullmatch(line)
        if not match:
            raise QAIncomplete("malformed 720p/1440p/4K timing or pixel proof")
        rw,rh,passes,ms,hashvalue,painted=match.groups()
        if ((int(rw),int(rh))!=(w,h) or int(passes)!=5 or
                not 0<float(ms)<1_000_000 or int(hashvalue)==0 or
                not 100<=int(painted)<=w*h):
            raise QAIncomplete("bad dimension/pixel count in native 4K proof")
        samples[f"{w}x{h}"]={
            "median_ms":float(ms),
            "native_frame_hash":hashvalue,
            "rendered_pixels":int(painted),
            "frames_measured":5,
        }
    return {"baseline_frame_hash":str(frame),"lod_levels":levels,
            "resolutions":samples}

def _select_qa_assets(pack:Path)->list[str]:
    data=json.loads((pack/"raster/validated-raster-assets.json")
                    .read_text(encoding="utf-8"))
    if not data.get("complete") or data.get("sources_converted")!=51:
        raise QAIncomplete("native QA requires a real fully compiled 51-source experimental pack")
    entries=data.get("assets",[])
    selected=[]
    for scale in ("ne-10m-","ne-50m-"):
        matching=sorted(row["asset_id"] for row in entries
                        if row.get("source_id","").startswith(scale))
        if not matching:
            # Official source IDs may use hashed theme suffixes; derive their
            # scale exclusively from the verified publisher provenance manifest.
            archives=json.loads((pack/"provenance/source-archives.json")
                                .read_text(encoding="utf-8"))
            lookup={r["resource_id"]:r["scale"] for r in archives["resources"]
                    if r.get("status")=="VERIFIED"}
            target="10m" if "10m" in scale else "50m"
            matching=sorted(row["asset_id"] for row in entries
                            if lookup.get(row.get("source_id"))==target)
        if not matching:
            raise QAIncomplete("cannot find a rendered publisher raster from "+scale)
        selected.append(matching[0])
    return selected

def verify_native(pack:Path,executable:Path,
                  *,runner:Callable[...,Any]=subprocess.run)->dict:
    if not executable.is_file():
        raise QAIncomplete("native CartoRig raster preview executable is missing")
    results=[]
    for asset in _select_qa_assets(pack):
        p=runner([str(executable),str(pack/"raster"),asset,"--bench-matrix"],
                 capture_output=True,text=True,timeout=600,check=False)
        if p.returncode!=0:
            raise QAIncomplete("real 1440p/4K native QA failed for "+asset+": "+
                               p.stderr[-900:])
        sample=parse_native_matrix(p.stdout)
        results.append({"asset_id":asset,**sample})
    return {"status":"NATIVE_1440P_4K_PASSED",
            "native_rendered_asset_count":len(results),
            "assets":results,
            "resolve_20_host_test":False}

def run(*,workspace:Path,output:Path,allow_network:bool=False,
        max_downloads:int=12,max_batches:int=10,
        min_free_gib:float=4,preview:Path|None=None,
        acquire_fn:Callable[...,dict]=acquire_available.acquire,
        build_fn:Callable[...,dict]=build_experimental.produce,
        verify_fn:Callable[...,dict]=verify_release.verify_release,
        native_fn:Callable[...,dict]=verify_native)->dict:
    if (max_downloads<1 or max_downloads>52 or max_batches<1 or
            max_batches>100 or min_free_gib<0 or min_free_gib>1000):
        raise ValueError("invalid bounded workstation acquisition parameters")
    workspace=workspace.resolve()
    output=output.resolve()
    if (workspace==output or output in workspace.parents or
            workspace in output.parents):
        raise ValueError("workspace and output must be separate, non-nested paths")
    workspace.mkdir(parents=True,exist_ok=True)
    report_file=workspace/"workstation-qa-report.json"
    report={
        "schema_version":1,"format":REPORT_FORMAT,
        "status":"STARTED","release_certified":False,
        "resolve_20_host_test":False,
        "started_utc":datetime.now(timezone.utc).isoformat(),
        "workspace":str(workspace),"output":str(output),
        "acquisition_batches":[],"native_qa":None,"pack":None,
    }
    def save():
        tmp=report_file.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(report,sort_keys=True,indent=2)+"\n",
                       encoding="utf-8")
        tmp.replace(report_file)
    save()
    previous=-1
    stagnant=0
    try:
        if not output.is_dir():
            for index in range(max_batches):
                available=shutil.disk_usage(workspace).free
                if available<min_free_gib*1024**3:
                    raise QAIncomplete(
                        "persistent workstation disk space below configured floor")
                acquired=acquire_fn(
                    workspace=workspace,allow_network=allow_network,
                    max_downloads=max_downloads,
                    skip_reviewed_unavailable=True)
                count=acquired["verified_archives"]
                unavailable=acquired["known_unavailable"]
                if (acquired["source_count"]!=52 or
                        not 0<=count<=52 or unavailable not in (0,1) or
                        count+unavailable>52 or
                        acquired["release_certified"] is not False):
                    raise QAIncomplete("publisher acquisition returned invalid provenance counts")
                report["acquisition_batches"].append({
                    "batch":index+1,"verified_archives":count,
                    "known_unavailable":unavailable,
                    "pending_or_blocked":acquired["pending_or_blocked"],
                    "acquisition_status":acquired["status"],
                })
                save()
                if acquired["status"]=="AVAILABLE_SOURCES_VERIFIED_NOT_CERTIFIED":
                    if count!=51 or unavailable!=1 or acquired["pending_or_blocked"]!=0:
                        raise QAIncomplete("expected exact 51 verified and one upstream 404")
                    break
                if acquired["status"]!="PARTIAL_ACQUISITION":
                    raise QAIncomplete("full 52-source approval is not experimental QA")
                stagnant=stagnant+1 if previous==count else 0
                previous=count
                if stagnant>=2:
                    raise QAIncomplete(
                        "publisher download made no progress across two batches; "
                        "review downloads/source-archives.json and resume later")
                if not allow_network:
                    raise QAIncomplete("offline source acquisition is incomplete")
            else:
                raise QAIncomplete("acquisition batch limit reached; resume the same command")
            report["status"]="AVAILABLE_SOURCES_REHASHED"
            save()
            built=build_fn(workspace=workspace,output=output,
                           allow_network=allow_network,max_downloads=0)
            if (built["status"]!="EXPERIMENTAL_INCOMPLETE" or
                    built["release_certified"] is not False or
                    built["verified_available_rasters"]!=51 or
                    built["known_unavailable"]!=1 or
                    built["converted_raster_sources"]!=51):
                raise QAIncomplete("experimental producer did not prove 51 official source conversions")
        proof=verify_fn(output,allow_incomplete=True)
        if (proof["complete"] is not False or
                proof["raster_sources"]!=51 or
                proof["vector_sources"]!=215):
            raise QAIncomplete("experimental data pack verification lacks 51/215 source coverage")
        report["pack"]=proof
        report["status"]="EXPERIMENTAL_PACK_VERIFIED_HOST_QA_PENDING"
        save()
        if preview is not None:
            report["native_qa"]=native_fn(output,preview)
            if report["native_qa"]["status"]!="NATIVE_1440P_4K_PASSED":
                raise QAIncomplete("native 1440p/4K renderer acceptance failed")
            report["status"]="EXPERIMENTAL_PACK_AND_NATIVE_4K_VERIFIED_HOST_QA_PENDING"
        return report
    except Exception as exc:
        report["status"]="INCOMPLETE"
        report["error"]=type(exc).__name__+": "+str(exc)[:2000]
        raise
    finally:
        report["finished_utc"]=datetime.now(timezone.utc).isoformat()
        save()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--workspace",required=True,type=Path)
    p.add_argument("--output",required=True,type=Path)
    p.add_argument("--allow-network",action="store_true")
    p.add_argument("--max-downloads",default=12,type=int)
    p.add_argument("--max-batches",default=10,type=int)
    p.add_argument("--min-free-gib",default=4,type=float)
    p.add_argument("--native-preview",type=Path)
    args=p.parse_args()
    try:
        result=run(workspace=args.workspace,output=args.output,
                   allow_network=args.allow_network,
                   max_downloads=args.max_downloads,
                   max_batches=args.max_batches,
                   min_free_gib=args.min_free_gib,
                   preview=args.native_preview)
        print(json.dumps({"status":result["status"],"pack":result["pack"],
                          "native_qa":result["native_qa"],
                          "resolve_20_host_test":False},indent=2))
    except (QAIncomplete,ValueError,RuntimeError,FileNotFoundError) as exc:
        print("NOT CERTIFIED: "+str(exc))
        raise SystemExit(2) from exc

if __name__=="__main__":
    main()
