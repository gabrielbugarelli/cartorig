#!/usr/bin/env python3
"""One-off release-machine proof against a real Natural Earth 50m TIFF ZIP.

Downloads exactly ONE official 17.15 MB 50m shaded relief source, never as
part of normal tests or inside the installed Resolve product.
"""
from pathlib import Path
import argparse
import json
import subprocess
from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.build_rasters import compile_archives

OFFICIAL_URL="https://naturalearth.s3.amazonaws.com/50m_raster/MSR_50M.zip"

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out",type=Path,required=True)
    p.add_argument("--preview",type=Path,required=True)
    args=p.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    root=args.out/"publisher";root.mkdir(exist_ok=True)
    file=root/"MSR_50M.zip"
    size,sha=download_and_hash(OFFICIAL_URL,file,max_bytes=60_000_000)
    record={"resource_id":"ne-50m-raster-manual-shaded-relief",
            "scale":"50m","theme":"raster","label":"Manual Shaded Relief 50m",
            "url":OFFICIAL_URL,"file":file.name,"archive_bytes":size,
            "sha256":sha,"status":"VERIFIED"}
    report=compile_archives(
        {"schema_version":1,"resources":[record]},root,args.out/"rasters")
    if not report["complete"] or not report["assets"]:
        raise RuntimeError("publisher raster conversion failed: "+repr(report))
    frames=[]
    for asset in report["assets"]:
        output=subprocess.run(
            [str(args.preview),str(args.out/"rasters"),asset["asset_id"]],
            capture_output=True,text=True,timeout=90)
        if output.returncode!=0:
            raise RuntimeError("native raster pixel test failed: "+
                               output.stderr[:600])
        frames.append({"asset_id":asset["asset_id"],
                       "source":"Natural Earth manual shaded relief 50m",
                       "native_render":output.stdout.strip()})
    proof={"source_url":OFFICIAL_URL,"source_sha256":sha,
           "archive_bytes":size,"converted":report["sources_converted"],
           "images":frames}
    (args.out/"real-raster-proof.json").write_text(
        json.dumps(proof,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(proof,indent=2))

if __name__=="__main__":
    main()
