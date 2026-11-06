#!/usr/bin/env python3
"""Offline Natural Earth raster-to-tiles compiler (release machine only).

Inputs are *already downloaded and SHA256 verified* publisher archives.  Never
download in the installed product.  Requires Pillow at build time, not runtime.
Outputs equirectangular, georeferenced 256x256 RGBA tiles plus metadata; every
source archive and its TFW/PSD derivative is recorded.  Unsupported or missing
publisher variants fail closed rather than counting as covered.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
import zipfile

TILE = 256
MAX_PIXELS = 850_000_000
IMAGE_EXTENSIONS = {".tif", ".tiff", ".png", ".jpg", ".jpeg", ".psd"}
WORLD_EXTENSIONS = (".tfw", ".tifw", ".wld", ".jgw", ".pgw")
SLUG = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,120}$")

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def georeference(worldfile: str, width: int, height: int) -> list[float]:
    values = [float(line.strip()) for line in worldfile.splitlines() if line.strip()]
    if len(values) != 6:
        raise ValueError("world file must have exactly six affine values")
    a, d, b, e, c, f = values
    if not (a > 0 and e < 0 and abs(d) < 1e-9 and abs(b) < 1e-9):
        raise ValueError("rotated or invalid Natural Earth raster; reproject explicitly")
    extent = [c - a/2, f + e*(height-.5), c+a*(width-.5), f-e/2]
    if not (-180.001 <= extent[0] < extent[2] <= 180.001 and
            -90.001 <= extent[1] < extent[3] <= 90.001):
        raise ValueError("raster georeference is outside EPSG:4326 world bounds")
    return extent

def build_asset(image_path: Path, world_text: str, root: Path,
                asset_id: str, provenance: dict) -> dict:
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError("release builder requires Pillow (pip install Pillow)") from exc
    if not SLUG.fullmatch(asset_id):
        raise ValueError("unsafe raster asset identifier")
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    with Image.open(image_path) as original:
        w,h = original.size
        if w<1 or h<1 or w*h>MAX_PIXELS:
            raise ValueError("publisher raster exceeds configured pixel budget")
        extent = georeference(world_text, w, h)
        # Work from the original pixels; each lower-resolution level is a
        # deterministic LANCZOS reduction. No upsampling or invented detail.
        sizes = [(w,h)]
        while max(sizes[-1]) > TILE:
            prev = sizes[-1]
            sizes.append((max(1,(prev[0]+1)//2), max(1,(prev[1]+1)//2)))
        sizes.reverse()
        output = root / asset_id
        if output.exists():
            raise FileExistsError("raster asset already exists: "+asset_id)
        with tempfile.TemporaryDirectory(prefix=".raster.",dir=root) as temporary:
            stage = Path(temporary) / asset_id
            stage.mkdir()
            levels = []
            for z,(zw,zh) in enumerate(sizes):
                level = stage / "tiles" / str(z)
                level.mkdir(parents=True)
                image = original.convert("RGBA") if (zw,zh)==(w,h) else original.resize(
                    (zw,zh), Image.Resampling.LANCZOS).convert("RGBA")
                tiles_x=(zw+TILE-1)//TILE
                tiles_y=(zh+TILE-1)//TILE
                for ty in range(tiles_y):
                    for tx in range(tiles_x):
                        tile = Image.new("RGBA",(TILE,TILE))
                        region = image.crop((tx*TILE,ty*TILE,
                                             min((tx+1)*TILE,zw),
                                             min((ty+1)*TILE,zh)))
                        tile.paste(region,(0,0))
                        (level / f"{tx}_{ty}.rgba").write_bytes(tile.tobytes())
                image.close()
                levels.append({"z":z,"width":zw,"height":zh,
                               "tiles_x":tiles_x,"tiles_y":tiles_y})
            metadata = {
                "schema_version":1,"format":"cartorig-rgba-tiles-v1",
                "asset_id":asset_id,"tile_size":TILE,
                "extent":extent,"original_width":w,"original_height":h,
                "levels":levels,"provenance":provenance,
            }
            (stage/"index.json").write_text(
                json.dumps(metadata,indent=2,sort_keys=True)+"\n",encoding="utf-8")
            stage.replace(output)
    return metadata

def find_world_file(names: list[str], image_name: str) -> str | None:
    name = PurePosixPath(image_name)
    lookup={p.casefold():p for p in names}
    base=str(name.with_suffix(""))
    for candidate in (base+ext for ext in WORLD_EXTENSIONS):
        if candidate.casefold() in lookup:
            return lookup[candidate.casefold()]
    return None

def compile_archives(manifest: dict, archive_root: Path, output: Path) -> dict:
    from tools.natural_earth.verify_pack import verify_manifest, verify_zip
    # Only the declared raster subset must be verified; vector archive
    # preparation is independently certified elsewhere.
    resources=[r for r in manifest.get("resources",[]) if r.get("theme")=="raster"]
    if not resources:
        raise ValueError("no official raster resources found in manifest")
    verified=verify_manifest({"schema_version":1,"resources":resources},archive_root)
    if not verified["complete"]:
        raise ValueError("official raster archives not fully verified: "+
                         json.dumps(verified["failed"][:6]))
    output.mkdir(parents=True,exist_ok=True)
    report={"schema_version":1,"complete":False,"sources_expected":len(resources),
            "sources_converted":0,"assets":[],"failures":[]}
    for r in resources:
        key=r["resource_id"]
        try:
            archive=archive_root / r["file"]
            if archive.suffix.lower()!=".zip":
                raise ValueError("unsupported publisher raster container (requires ZIP)")
            verify_zip(archive, max_uncompressed=12_000_000_000)
            with zipfile.ZipFile(archive) as z:
                names=[i.filename for i in z.infolist() if not i.is_dir()]
                images=[name for name in names
                        if PurePosixPath(name).suffix.lower() in IMAGE_EXTENSIONS]
                if not images:
                    raise ValueError("archive contains no convertible raster imagery")
                for index,img in enumerate(images):
                    world = find_world_file(names,img)
                    if world is None:
                        raise ValueError("missing matching TFW/world file: "+img)
                    # Extract one verified item at a time; no untrusted path
                    # is ever used to create a filesystem path.
                    with tempfile.TemporaryDirectory() as temp:
                        image_path=Path(temp)/"image"
                        with z.open(img) as src, image_path.open("wb") as dst:
                            shutil.copyfileobj(src,dst,1024*1024)
                        suffix=PurePosixPath(img).suffix
                        real_image=image_path.with_suffix(suffix)
                        image_path.rename(real_image)
                        world_text=z.read(world).decode("ascii")
                        asset_id=re.sub(r"[^a-zA-Z0-9_-]","_",
                                      key+"_"+str(index))
                        metadata=build_asset(real_image,world_text,output,
                                             asset_id,{
                            "source_id":key,"publisher_image":img,
                            "publisher_world_file":world,
                            "source_sha256":r["sha256"],
                        })
                        report["assets"].append({
                            "source_id":key,"asset_id":asset_id,
                            "status":"VALIDATED",
                            "original_pixels":[metadata["original_width"],
                                               metadata["original_height"]],
                            "levels":len(metadata["levels"])})
            report["sources_converted"]+=1
        except Exception as exc:
            report["failures"].append({"resource_id":key,"reason":str(exc)})
    report["complete"]=(not report["failures"] and
                        report["sources_converted"]==report["sources_expected"])
    (output/"validated-raster-assets.json").write_text(
        json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    return report

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--manifest",type=Path,required=True)
    ap.add_argument("--archives",type=Path,required=True)
    ap.add_argument("--out",type=Path,required=True)
    args=ap.parse_args()
    report=compile_archives(json.loads(args.manifest.read_text(encoding="utf-8")),
                            args.archives,args.out)
    print(json.dumps({k:v for k,v in report.items() if k!="assets"},indent=2))
    if not report["complete"]:
        raise SystemExit(1)

if __name__=="__main__":
    main()
