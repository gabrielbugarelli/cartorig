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
from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.verify_pack import sha256_file,verify_zip

IDENT=re.compile(r"^[a-z0-9_-]{5,100}$")
EXTENSIONS={".zip",".gpkg",".sqlite",".tif",".tiff",".psd",".7z",".gz"}

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
            try:
                size,digest=download_and_hash(item["url"],dest)
                if ext==".zip":verify_zip(dest)
                item["sha256"]=digest;item["archive_bytes"]=size
                item["status"]="VERIFIED";downloaded+=1
            except Exception as exc:
                dest.unlink(missing_ok=True)
                item["status"]="BLOCKED"
                item["error"]=type(exc).__name__+": "+str(exc)[:200]
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
