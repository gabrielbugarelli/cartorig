#!/usr/bin/env python3
"""Producer-only official Natural Earth 110m country archive integration smoke.

This intentionally never runs inside DaVinci Resolve and is only a small
real-data probe, NOT the full Natural Earth complete data pack.
"""
from pathlib import Path
import json
import zipfile
from tools.natural_earth.inventory import download_and_hash
from tools.natural_earth.verify_pack import verify_zip

URL="https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip"

def main():
    root=Path("build/natural-earth/smoke")
    root.mkdir(parents=True,exist_ok=True)
    path=root/"ne_110m_admin_0_countries.zip"
    size,digest=download_and_hash(URL,path,max_bytes=5_000_000)
    meta=verify_zip(path,max_uncompressed=15_000_000)
    with zipfile.ZipFile(path) as z:
        names=set(z.namelist())
    stem="ne_110m_admin_0_countries"
    for ext in (".shp",".shx",".dbf",".prj"):
        if not any(Path(x).name==stem+ext for x in names):
            raise ValueError("official archive is missing required Shapefile member: "+ext)
    info={"schema_version":1,"resource_id":"ne_110m_admin_0_countries",
          "source":URL,"archive_bytes":size,"sha256":digest,
          "zip_members":meta["members"],"status":"VERIFIED_SINGLE_LAYER_SMOKE",
          "complete_natural_earth":False}
    (root/"smoke.json").write_text(json.dumps(info,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(info,indent=2))

if __name__=="__main__":main()
