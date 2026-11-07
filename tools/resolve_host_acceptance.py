#!/usr/bin/env python3
"""Actual Windows DaVinci Resolve Studio 20 QA bridge (run ON the user's PC).

'probe' is read-only: checks locally running Resolve 20, installed native OFX
and SHA256-verified experimental 51-source offline pack. 'prepare' creates
ONLY a new, dedicated QA project and two OFX-generator timelines, one at
2560x1440 and one at 3840x2160. The user then configures Inspector:
 Use installed offline Natural Earth data pack = true
 Raster asset ID = an actual verified asset from the installed pack
 Save both timelines, and visually inspect the source/image/alpha.
'render' renders those already-prepared, user-configured QA timelines to
MP4/H264 using Resolve's supported Scripting API and optionally uses ffprobe
to validate actual output resolution. No existing user project is overwritten.

CRITICAL: Resolve's public timeline scripting API does not expose reliable
OFX Inspector controls for this plugin. A successful render is evidence of a
live Resolve OFX generator frame pipeline, NOT automatic proof that the full
Natural Earth atlas or Overlay was selected. Those acceptance gates remain
unverified unless documented separately with real host evidence.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from tools.natural_earth.verify_release import verify_release

WIDTHS=(("CartoRig-1440p",2560,1440),("CartoRig-4K",3840,2160))
DEFAULT_PROJECT="CartoRig_NaturalEarth_20_QA"

class HostQAError(RuntimeError):
    pass

def load_resolve():
    if sys.platform!="win32":
        raise HostQAError("Actual Resolve host QA requires Windows with Studio 20 running")
    module_root=os.environ.get("RESOLVE_SCRIPT_API",
        r"C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting")
    module_path=Path(module_root)/"Modules"
    if not module_path.is_dir():
        raise HostQAError("Resolve scripting module not found: "+str(module_path))
    sys.path.insert(0,str(module_path))
    try:
        import DaVinciResolveScript as dvr
    except (ImportError,OSError) as err:
        raise HostQAError("Unable to import the installed Resolve 20 scripting API") from err
    app=dvr.scriptapp("Resolve")
    if not app:
        raise HostQAError("Resolve is not running or External Scripting is not enabled locally")
    return app

def installed_bundle_path()->Path:
    return Path(os.environ.get("ProgramFiles",r"C:\Program Files")) / (
        "Common Files/OFX/Plugins/CartoRigNative.ofx.bundle/"
        "Contents/Win64/CartoRigNative.ofx")

def installed_pack_path()->Path:
    return Path(os.environ.get("LOCALAPPDATA",
             str(Path.home()/"AppData/Local"))) / "CartoRigNative/NaturalEarth"

def inspect(app,*,bundle:Path,pack:Path)->dict:
    version=app.GetVersion()
    version_string=app.GetVersionString()
    if not isinstance(version,(list,tuple)) or not version or int(version[0])!=20:
        raise HostQAError("Actual DaVinci Resolve 20 is required")
    name=str(app.GetProductName())
    if "DaVinci Resolve" not in name:
        raise HostQAError("Connected app is not a recognized DaVinci Resolve product")
    if not bundle.is_file():
        raise HostQAError("CartoRigNative OFX Windows DLL has not been installed")
    pack_proof=verify_release(pack,allow_incomplete=True)
    if (pack_proof["complete"] is not False or
        pack_proof["raster_sources"]!=51 or
        pack_proof["vector_sources"]!=215):
        raise HostQAError("installed pack is not the expected SHA256-verified experimental 51/215 dataset")
    digest=hashlib.sha256()
    with bundle.open("rb") as source:
        for part in iter(lambda:source.read(1024*1024),b""):
            digest.update(part)
    return {
        "status":"LIVE_RESOLVE_20_CONNECTED_OFFLINE_PACK_VERIFIED",
        "resolve_name":name,"resolve_version":str(version_string),
        "ofx_bundle_sha256":digest.hexdigest(),
        "ofx_bundle_path":str(bundle),
        "offline_pack_id":pack_proof["pack_id"],
        "offline_pack_sources":pack_proof["raster_sources"],
        "offline_vector_sources":pack_proof["vector_sources"],
        "actual_resolve_host_connected":True,
        "source_raster_selected_in_inspector":False,
        "overlay_alpha_tested":False,
        "four_k_render_accepted":False,
        "complete_natural_earth_release":False,
    }

def prepare(app,*,name:str)->dict:
    if not name.startswith("CartoRig_") or len(name)>80:
        raise HostQAError("only dedicated CartoRig_ QA project names are permitted")
    manager=app.GetProjectManager()
    project=manager.CreateProject(name)
    if not project:
        raise HostQAError("dedicated QA project already exists; never modify another project")
    media=project.GetMediaPool()
    created=[]
    for label,w,h in WIDTHS:
        # These are independent Resolve timelines, not simulations.
        tl=media.CreateEmptyTimeline(label)
        if not tl or not project.SetCurrentTimeline(tl):
            raise HostQAError("Resolve could not create/switch the required QA timeline")
        if not tl.SetSetting("timelineResolutionWidth",str(w)):
            raise HostQAError("Resolve refused 1440p or 4K timeline width")
        if not tl.SetSetting("timelineResolutionHeight",str(h)):
            raise HostQAError("Resolve refused 1440p or 4K timeline height")
        item=tl.InsertOFXGeneratorIntoTimeline("CartoRig Map (Edit)")
        if not item:
            raise HostQAError("CartoRig Map (Edit) was not discovered as an OFX generator")
        created.append({
            "timeline":label,"width":w,"height":h,
            "inserted_item_name":str(item.GetName()),
            "ofx_map_generator_inserted":True,
            "inspector_raster_asset_configured":False,
        })
    if not manager.SaveProject():
        raise HostQAError("DaVinci Resolve refused to save the QA project")
    return {
        "status":"RESOLVE_QA_PROJECT_PREPARED_USER_INSPECTOR_CONFIGURATION_REQUIRED",
        "project_name":name,"timelines":created,
        "rendered_frames_verified":False,
        "real_host_used":True,
        "note":"Enable installed offline Natural Earth and select a verified raster asset in both Inspector panels before 'render'.",
    }

def _video_resolution(path:Path)->tuple[int,int]|None:
    exe=shutil.which("ffprobe")
    if not exe:
        return None
    completed=subprocess.run([
        exe,"-v","error","-select_streams","v:0",
        "-show_entries","stream=width,height",
        "-of","json",str(path)
    ],capture_output=True,text=True,timeout=60,check=False)
    if completed.returncode!=0:
        raise HostQAError("ffprobe could not decode actual rendered video")
    data=json.loads(completed.stdout)
    streams=data.get("streams",[])
    if not streams:
        raise HostQAError("rendered video has no decodable video stream")
    return int(streams[0]["width"]),int(streams[0]["height"])

def render(app,*,name:str,target:Path,timeout_seconds:int=1800,
           clock=time.monotonic,sleeper=time.sleep)->dict:
    if not name.startswith("CartoRig_"):
        raise HostQAError("Refusing to render any non-CartoRig QA project")
    manager=app.GetProjectManager()
    project=manager.LoadProject(name)
    if not project or project.GetName()!=name:
        raise HostQAError("dedicated CartoRig QA project not found")
    target=target.resolve()
    target.mkdir(parents=True,exist_ok=True)
    if any(target.glob("CartoRig-QA-*.mp4")):
        raise HostQAError("QA output directory already has renders; choose a fresh output folder")
    queue=[]
    for label,w,h in WIDTHS:
        found=None
        for number in range(1,int(project.GetTimelineCount())+1):
            tl=project.GetTimelineByIndex(number)
            if tl.GetName()==label:
                found=tl
                break
        if not found or not project.SetCurrentTimeline(found):
            raise HostQAError("QA timeline missing: "+label)
        clips=[]
        for idx in range(1,int(found.GetTrackCount("video"))+1):
            clips.extend(found.GetItemListInTrack("video",idx) or [])
        if not any("CartoRig" in str(c.GetName()) for c in clips):
            raise HostQAError("CartoRig generator not found on "+label)
        if not project.SetCurrentRenderFormatAndCodec("mp4","H264"):
            raise HostQAError("Resolve MP4/H264 preset is not available; cannot validate video dimensions")
        output_name=f"CartoRig-QA-{w}x{h}"
        if not project.SetRenderSettings({
            "SelectAllFrames":True,"TargetDir":str(target),
            "CustomName":output_name,"ExportVideo":True,
            "ExportAudio":False,"FormatWidth":w,"FormatHeight":h,
        }):
            raise HostQAError("Resolve refused full-frame settings for "+output_name)
        job=project.AddRenderJob()
        if not job:
            raise HostQAError("Resolve rejected QA render job "+output_name)
        queue.append((job,w,h,output_name))
    if not app.OpenPage("deliver"):
        raise HostQAError("Resolve could not open its Deliver page")
    ids=[x[0] for x in queue]
    if not project.StartRendering(ids):
        raise HostQAError("DaVinci Resolve refused to start queued QA jobs")
    started=clock()
    while project.IsRenderingInProgress():
        if clock()-started>timeout_seconds:
            project.StopRendering()
            raise HostQAError("Resolve rendering exceeded the configured host test timeout")
        sleeper(1)
    output=[]
    for job,w,h,namepart in queue:
        job_data=project.GetRenderJobStatus(job)
        if not isinstance(job_data,dict) or job_data.get("JobStatus")!="Complete":
            raise HostQAError("Resolve render job failed: "+namepart+"; "+str(job_data))
        choices=[p for p in target.rglob("*") if p.is_file() and
                 p.name.startswith(namepart) and p.suffix.lower()==".mp4"]
        if len(choices)!=1 or choices[0].stat().st_size<1024:
            raise HostQAError("Resolve created no nonempty MP4 for "+namepart)
        seen=_video_resolution(choices[0])
        if seen is not None and seen!=(w,h):
            raise HostQAError("ffprobe output dimensions differ from actual Resolve job settings")
        output.append({
            "resolution":f"{w}x{h}",
            "source":"live DaVinci Resolve 20 H264/MP4 Deliver job",
            "job_status":"Complete",
            "video_file":str(choices[0]),"bytes":choices[0].stat().st_size,
            "decoded_video_dimensions":list(seen) if seen else None,
            "dimensions_independently_verified":seen is not None,
        })
    return {
        "status":"LIVE_RESOLVE_QA_RENDER_JOBS_COMPLETE_INSPECTOR_AND_OVERLAY_UNVERIFIED",
        "project_name":name,"renders":output,"real_resolve_host_rendered":True,
        "pack_raster_selected_by_script":False,
        "overlay_alpha_tested":False,
        "full_resolve_acceptance":False,
        "note":"The public Resolve API did not confirm OFX Inspector raster selection. Visually inspect outputs and separately test the Overlay and alpha.",
    }

def run_cli(*,mode:str,report_path:Path,project:str,target:Path|None,
            bundle:Path|None,pack:Path|None,app=None)->dict:
    report_path.parent.mkdir(parents=True,exist_ok=True)
    result={
        "schema_version":1,
        "format":"cartorig-resolve-20-real-host-qa-v1",
        "utc":datetime.now(timezone.utc).isoformat(),
        "mode":mode,"status":"NOT_RUN",
        "real_resolve_host_rendered":False,"complete_natural_earth_release":False,
    }
    try:
        if app is None:
            app=load_resolve()
        result["preflight"]=inspect(
            app,bundle=bundle or installed_bundle_path(),
            pack=pack or installed_pack_path())
        if mode=="inspect":
            result["status"]="PREFLIGHT_PASSED_HOST_RENDER_PENDING"
        elif mode=="prepare":
            result["action"]=prepare(app,name=project)
            result["status"]=result["action"]["status"]
        elif mode=="render":
            if target is None:
                raise HostQAError("real Resolve video output folder is required")
            result["action"]=render(app,name=project,target=target)
            result["status"]=result["action"]["status"]
            result["real_resolve_host_rendered"]=True
        else:
            raise ValueError("invalid real Resolve QA mode")
        return result
    except Exception as error:
        result["status"]="BLOCKED"
        result["blocker"]=type(error).__name__+": "+str(error)[:900]
        raise
    finally:
        tmp=report_path.with_suffix(report_path.suffix+".tmp")
        tmp.write_text(json.dumps(result,sort_keys=True,indent=2)+"\n",
                       encoding="utf-8")
        tmp.replace(report_path)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode",choices=("inspect","prepare","render"),required=True)
    p.add_argument("--project",default=DEFAULT_PROJECT)
    p.add_argument("--report",type=Path,required=True)
    p.add_argument("--render-dir",type=Path)
    p.add_argument("--plugin-binary",type=Path)
    p.add_argument("--pack",type=Path)
    args=p.parse_args()
    try:
        result=run_cli(mode=args.mode,report_path=args.report,project=args.project,
                       target=args.render_dir,bundle=args.plugin_binary,
                       pack=args.pack)
        print(json.dumps({"status":result["status"],
                          "report":str(args.report)},indent=2))
    except (HostQAError,OSError,ValueError,RuntimeError) as error:
        print("RESOLVE 20 HOST QA NOT CERTIFIED: "+str(error),file=sys.stderr)
        raise SystemExit(2) from error

if __name__=="__main__":
    main()
