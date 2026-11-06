#!/usr/bin/env python3
"""Materialize an official source inventory only during explicit release builds.

The installed OpenFX plugin never imports this module or accesses any network.
Every resource is verified with content SHA256 and ZIP security checks.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
from urllib.parse import urlsplit
from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.verify_pack import sha256_file,verify_zip

IDENT=re.compile(r"^[a-z0-9_-]{5,100}$")
EXTENSIONS={".zip",".gpkg",".sqlite",".tif",".tiff",".psd",".7z",".gz"}
OFFICIAL_S3="https://naturalearth.s3.amazonaws.com"
SAFE_RASTER_ZIP=re.compile(
    r"^/download/(10m|50m)/raster/([a-zA-Z0-9_-]{1,100}\.zip)$",
    re.I,
)
def official_raster_mirror(record: dict) -> str | None:
    """Only an explicit Natural Earth raster URL can map to the publisher S3.

    Never use arbitrary redirects or unrelated URLs as archive mirrors.
    Keep the source's original publisher URL in the manifest for audit.
    """
    if record.get("theme")!="raster":
        return None
    url=record.get("url","")
    parts=urlsplit(url)
    if (parts.scheme!="https" or
        parts.hostname not in {"www.naturalearthdata.com","naturalearthdata.com"}
        or parts.username or parts.password or parts.query or parts.fragment):
        return None
    match=SAFE_RASTER_ZIP.fullmatch(parts.path)
    if not match or match.group(1).lower()!=record.get("scale"):
        return None
    scale,name=match.groups()
    return OFFICIAL_S3+f"/{scale.lower()}_raster/{name}"


def materialize(inventory:dict,root:Path,allow_network:bool=False,
                max_downloads:int|None=None)->dict:
    if inventory.get("schema_version")!=1:
        raise ValueError("unsupported source inventory")
    root.mkdir(parents=True,exist_ok=True)
    entries=[];downloaded=0;ids=set()
    for source in inventory.get("resources",[]):
        item=dict(source)
        ident=item.get("resource_id","")
        if not IDENT.fullmatch(ident) or ident in ids:
            raise ValueError("invalid or duplicate source ID")
        ids.add(ident)
        ext=Path(item["url"].split("?",1)[0]).suffix.lower()
        if ext not in EXTENSIONS:ext=".bin"
        relative="archives/"+ident+ext
        dest=root/relative
        item["file"]=relative
        if dest.is_file() and item.get("sha256") and sha256_file(dest)==item["sha256"]:
            item["status"]="VERIFIED";item["archive_bytes"]=dest.stat().st_size
        elif allow_network and (max_downloads is None or downloaded<max_downloads):
            mirrors=[item["url"]]
            fallback=official_raster_mirror(item)
            if fallback and fallback!=item["url"]:
                mirrors.append(fallback)
            reasons=[]
            for attempt in mirrors:
                try:
                    size,digest=download_and_hash(attempt,dest)
                    if ext==".zip":verify_zip(dest,max_uncompressed=12_000_000_000)
                    item["sha256"]=digest;item["archive_bytes"]=size
                    item["acquisition_url"]=attempt
                    item["status"]="VERIFIED";downloaded+=1
                    break
                except Exception as exc:
                    dest.unlink(missing_ok=True)
                    reasons.append(type(exc).__name__+": "+str(exc)[:160])
            if item.get("status")!="VERIFIED":
                item["status"]="BLOCKED"
                item["error"]="; ".join(reasons)[:380]
                item["sha256"]=None;item["archive_bytes"]=None
        else:
            item["status"]="NOT_INSTALLED"
            item["sha256"]=None;item["archive_bytes"]=None
        entries.append(item)
    report={"schema_version":1,"publisher":"Natural Earth","resources":entries,
            "summary":{"expected":len(entries),
                       "verified":sum(x["status"]=="VERIFIED" for x in entries),
                       "complete":bool(entries) and all(x["status"]=="VERIFIED" for x in entries)}}
    (root/"source-archives.json").write_text(
        json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--inventory",type=Path,required=True)
    p.add_argument("--data-dir",type=Path,required=True)
    p.add_argument("--allow-network",action="store_true")
    p.add_argument("--max-downloads",type=int)
    a=p.parse_args()
    report=materialize(json.loads(a.inventory.read_text(encoding="utf-8")),
                       a.data_dir,a.allow_network,a.max_downloads)
    print(json.dumps(report["summary"],indent=2))
    if not report["summary"]["complete"]:raise SystemExit(1)

if __name__=="__main__":main()
