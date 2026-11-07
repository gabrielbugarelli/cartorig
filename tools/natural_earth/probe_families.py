#!/usr/bin/env python3
"""NE-FETCH-01: live, bounded Natural Earth raster-family acquisition probe.

Only runs with explicit --allow-network in a release/probe machine.
52 official download URLs are measured in the initial HEAD preflight;
one smallest real publisher ZIP
per each of the 16 family pages is acquired and checked, where within budget.
The report is JSON-only: NO publisher binaries uploaded to GitHub artifacts.
Known publisher issue: 10m manual-shaded-relief US_MSR_10M.zip answered
404 on both official acquisition hosts in the initial 52-URL HEAD probe.
This is family sample evidence, NEVER a lock of the 52 full archive hashes.
"""
from __future__ import annotations
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import urllib.error
import urllib.request
from urllib.parse import urlsplit
import zipfile

from tools.natural_earth import inventory, materialize, source_lock
from tools.natural_earth import verify_pack, build_rasters

MAX_ARCHIVE=250_000_000
MAX_TOTAL=1_200_000_000
ACQUISITION_UA="CartoRigNaturalEarthFamilyAudit/0.1"

def _official_https(url:str)->bool:
    p=urlsplit(url)
    return (p.scheme=="https" and p.hostname in inventory.ALLOWED_HOSTS
            and not p.username and not p.password and not p.fragment)

def probe_size(source:dict, opener=urllib.request.urlopen)->dict:
    """HEAD metadata; try a publisher S3 mirror before the WordPress link."""
    original=source["url"]
    alternative=materialize.official_raster_mirror(source)
    alternatives=[alternative,original] if alternative else [original]
    failed=[]
    for url in alternatives:
        if not _official_https(url):
            failed.append("nonpublisher URL")
            continue
        try:
            request=urllib.request.Request(
                url,headers={"User-Agent":ACQUISITION_UA},method="HEAD")
            with opener(request,timeout=40) as response:
                resolved=response.geturl()
                if not _official_https(resolved):
                    raise ValueError("publisher HEAD redirected outside official HTTPS")
                if response.getcode()!=200:
                    raise ValueError("publisher HEAD returned HTTP "+str(response.getcode()))
                length=response.headers.get("Content-Length")
                count=int(length) if length and length.isdecimal() else None
                if count is not None and count<=0:
                    raise ValueError("invalid publisher archive byte count")
                return {"status":"HEAD_OK" if count is not None else "UNKNOWN_SIZE",
                        "acquisition_url":url,"resolved_url":resolved,
                        "archive_bytes":count,
                        "etag":response.headers.get("ETag"),
                        "accept_ranges":response.headers.get("Accept-Ranges"),
                        "last_modified":response.headers.get("Last-Modified")}
        except (OSError,ValueError,urllib.error.URLError) as error:
            failed.append(type(error).__name__+": "+str(error)[:160])
    return {"status":"HEAD_BLOCKED","archive_bytes":None,
            "errors":failed[:3]}

def inspect_zip(path:Path)->dict:
    """Read every archive CRC and inventory all georeferenced source images."""
    verification=verify_pack.verify_zip(path,max_items=1500,
                                      max_uncompressed=10_000_000_000)
    with zipfile.ZipFile(path) as archive:
        all_members=[i.filename for i in archive.infolist() if not i.is_dir()]
        ignored_metadata=[n for n in all_members
                          if not build_rasters.is_payload_member(n)]
        names=[n for n in all_members if build_rasters.is_payload_member(n)]
        images=[n for n in names if PurePosixPath(n).suffix.lower()
                in build_rasters.IMAGE_EXTENSIONS]
        paired=[{"image":n,"world_file":world}
                for n in images
                if (world:=build_rasters.find_world_file(names,n))]
        nongeoreferenced=[n for n in images
                          if not build_rasters.find_world_file(names,n)]
        if not paired:
            raise ValueError("publisher ZIP has no source image with world file")
        for item in paired:
            world=archive.getinfo(item["world_file"])
            if world.file_size>4096:
                raise ValueError("publisher world file exceeds safe size")
            raw=archive.read(item["world_file"])
            try:
                values=raw.decode("ascii").split()
            except UnicodeDecodeError as error:
                raise ValueError(
                    "World file is not ASCII; filename="+item["world_file"]+
                    "; bytes="+str(len(raw))+"; prefix_hex="+raw[:160].hex()
                ) from error
            if len(values)!=6 or not all(len(v)<80 for v in values):
                raise ValueError("invalid source world-file affine dimensions")
            affine=[float(v) for v in values]
            if not (affine[0]>0 and affine[3]<0):
                raise ValueError("unsupported source world-file affine")
    return {"zip_members":verification["members"],
            "ignored_macos_metadata_members":len(ignored_metadata),
            "zip_uncompressed_bytes":verification["uncompressed_bytes"],
            "georeferenced_images":paired,
            "nongeoreferenced_images":nongeoreferenced}

def candidates_by_family(rows:list[dict],metadata:dict)->dict[str,dict]:
    """Select exactly one smallest HEAD-verified ZIP per source family."""
    by_family=defaultdict(list)
    for row in rows:
        if row.get("theme")!="raster":continue
        found=metadata.get(row["resource_id"],{})
        if found.get("status")=="HEAD_OK" and found.get("archive_bytes",0)>0:
            by_family[row["source_page"]].append((found["archive_bytes"],row["resource_id"],row))
    return {family:min(choices,key=lambda x:(x[0],x[1]))[2]
            for family,choices in by_family.items()}

def run(inventory_report:dict,reviewed_discovery:dict,*,out:Path,
        allow_network:bool=False,fetch_samples:bool=False,
        max_archive_bytes:int=MAX_ARCHIVE,max_total_bytes:int=MAX_TOTAL,
        opener=urllib.request.urlopen,downloader=inventory.download_and_hash,
        only_family:str|None=None)->dict:
    if not allow_network:
        raise ValueError("publisher HEAD/download requires --allow-network")
    source_lock.verify_discovery(reviewed_discovery,inventory_report)
    if (max_archive_bytes<=0 or max_total_bytes<=0 or
        max_archive_bytes>MAX_ARCHIVE or max_total_bytes>MAX_TOTAL):
        raise ValueError("probe budget exceeds the authorized free-runner cap")
    sources=sorted([r for r in inventory_report["resources"]
                    if r["theme"]=="raster"],key=lambda r:r["resource_id"])
    families={r["source_page"] for r in sources}
    if len(sources)!=52 or len(families)!=16:
        raise ValueError("unexpected official raster inventory size/family count")
    out.mkdir(parents=True,exist_ok=True)
    measurements={}
    for r in sources:
        measurements[r["resource_id"]]=probe_size(r,opener=opener)
    selected=candidates_by_family(sources,measurements)
    target_families=sorted(f for f in families if (
        not only_family or f.rstrip("/").endswith("/"+only_family)))
    if not target_families:
        raise ValueError("requested raster family not in reviewed official discovery")
    rows=[]
    acquired_bytes=0
    for family in target_families:
        row=selected.get(family)
        if not row:
            rows.append({"family":family,"status":"BLOCKED_NO_SIZE_VERIFIED_ZIP"})
            continue
        size=measurements[row["resource_id"]]["archive_bytes"]
        entry={"family":family,"resource_id":row["resource_id"],
               "url":row["url"],"scale":row["scale"],
               "acquisition_url":measurements[row["resource_id"]]["acquisition_url"],
               "advertised_bytes":size}
        if size>max_archive_bytes or size+acquired_bytes>max_total_bytes:
            entry["status"]="BLOCKED_BY_BUDGET"
        elif not fetch_samples:
            entry["status"]="HEAD_VERIFIED_SELECTED"
        else:
            file=out/"staging"/(row["resource_id"]+".zip")
            file.parent.mkdir(parents=True,exist_ok=True)
            try:
                bytes_seen,sha=downloader(entry["acquisition_url"],file,
                                         max_bytes=max_archive_bytes)
                if bytes_seen!=size:
                    raise ValueError("download differs from publisher HEAD length")
                detail=inspect_zip(file)
                entry.update(detail)
                entry["archive_bytes"]=bytes_seen
                entry["sha256"]=sha
                entry["status"]="ZIP_VERIFIED"
                acquired_bytes+=bytes_seen
            except Exception as error:
                entry["status"]="ACQUISITION_BLOCKED"
                entry["reason"]=type(error).__name__+": "+str(error)[:350]
            finally:
                file.unlink(missing_ok=True)
        rows.append(entry)
    verified=sum(x["status"]=="ZIP_VERIFIED" for x in rows)
    head_ready=sum(x["status"]=="HEAD_OK" for x in measurements.values())
    report={"schema_version":1,"format":"cartorig-ne-family-acquisition-probe-v1",
            "created_utc":datetime.now(timezone.utc).isoformat(),
            "publisher":"Natural Earth / NACIS",
            "source_count":len(sources),"source_head_verified":head_ready,
            "families_expected":len(families),
            "families_in_this_probe":len(target_families),
            "family_samples_verified":verified,
            "scope_complete":fetch_samples and verified==len(target_families),
            "complete":fetch_samples and only_family is None and verified==len(families),
            "sample_mode":"real-zip" if fetch_samples else "head-only",
            "bytes_acquired_and_discarded":acquired_bytes,
            "max_archive_bytes":max_archive_bytes,
            "max_total_bytes":max_total_bytes,
            "measurements":measurements,"families":rows,
            "notes":"Hashes observed on actual ZIPs are evidence, not the 52-source reviewed lock."}
    evidence=out/"family-probe.json"
    evidence.write_text(json.dumps(report,sort_keys=True,indent=2,ensure_ascii=False)+"\n",
                        encoding="utf-8")
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory",type=Path,required=True)
    parser.add_argument("--discovery-lock",type=Path,
                        default=Path("data/natural-earth/raster_discovery_v2026-11-07.lock.json"))
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--allow-network",action="store_true")
    parser.add_argument("--fetch-samples",action="store_true")
    parser.add_argument("--only-family",type=str,
                        help="Diagnostic scoped to one official raster family slug")
    parser.add_argument("--max-archive-mb",type=int,default=MAX_ARCHIVE//1_000_000)
    parser.add_argument("--max-total-mb",type=int,default=MAX_TOTAL//1_000_000)
    args=parser.parse_args()
    report=run(json.loads(args.inventory.read_text(encoding="utf-8")),
               json.loads(args.discovery_lock.read_text(encoding="utf-8")),
               out=args.out,allow_network=args.allow_network,
               fetch_samples=args.fetch_samples,
               max_archive_bytes=args.max_archive_mb*1_000_000,
               max_total_bytes=args.max_total_mb*1_000_000,
               only_family=args.only_family)
    print(json.dumps({k:v for k,v in report.items()
                      if k not in ("measurements","families")},indent=2))
    if args.fetch_samples and not (
        report["scope_complete"] if args.only_family else report["complete"]):
        raise SystemExit("Official raster families could not all be acquired in the hard budget")
    if not args.only_family and report["source_head_verified"]!=52:
        raise SystemExit("At least one official raster variant lacks verified HEAD metadata")

if __name__=="__main__":main()
