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
import hmac
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

def _write_windowed_tiff(
        image_path: Path, stage: Path,
        sizes: list[tuple[int,int]], width: int, height: int) -> None:
    """Stream one TIFF tile at a time using rasterio on release machines.

    Large Natural Earth TIFF images can exceed 230 million pixels; building
    complete RGBA images in Pillow would require many gigabytes of RAM.
    rasterio/numpy/GDAL are build-time only, never installed inside Resolve.
    """
    try:
        import numpy as np
        import rasterio
        from rasterio.enums import Resampling
        from rasterio.windows import Window
    except ImportError as exc:
        raise RuntimeError(
            "Large publisher TIFF requires release-only rasterio and numpy "
            "(pip install rasterio numpy); no dependency is needed in Resolve"
        ) from exc
    with rasterio.open(image_path) as src:
        if (src.width, src.height) != (width, height) or src.count not in (1,2,3,4):
            raise ValueError("TIFF dimensions or channel count is unsupported")
        if any(dtype!="uint8" for dtype in src.dtypes):
            raise ValueError("TIFF requires 8-bit channels; normalize explicitly")
        for z, (zw,zh) in enumerate(sizes):
            level=stage/"tiles"/str(z)
            level.mkdir(parents=True)
            for ty in range((zh+TILE-1)//TILE):
                for tx in range((zw+TILE-1)//TILE):
                    start_x,start_y=tx*TILE,ty*TILE
                    tw,th=min(TILE,zw-start_x),min(TILE,zh-start_y)
                    fx=width/zw
                    fy=height/zh
                    window=Window(start_x*fx,start_y*fy,tw*fx,th*fy)
                    channels=src.read(
                        window=window,out_shape=(src.count,th,tw),
                        resampling=Resampling.bilinear)
                    tile=np.zeros((TILE,TILE,4),dtype=np.uint8)
                    if src.count in (1,2):
                        tile[:th,:tw,0]=channels[0]
                        tile[:th,:tw,1]=channels[0]
                        tile[:th,:tw,2]=channels[0]
                        tile[:th,:tw,3]=channels[1] if src.count==2 else 255
                    else:
                        tile[:th,:tw,:3]=np.moveaxis(channels[:3],0,2)
                        tile[:th,:tw,3]=channels[3] if src.count==4 else 255
                    (level/f"{tx}_{ty}.rgba").write_bytes(tile.tobytes())

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
            levels = [{"z":z,"width":zw,"height":zh,
                       "tiles_x":(zw+TILE-1)//TILE,
                       "tiles_y":(zh+TILE-1)//TILE}
                      for z,(zw,zh) in enumerate(sizes)]
            use_windows=(image_path.suffix.lower() in (".tif", ".tiff") and
                         w*h>2_000_000)
            if use_windows:
                _write_windowed_tiff(image_path,stage,sizes,w,h)
            else:
                if w*h>25_000_000:
                    raise RuntimeError(
                        "Large non-TIFF image cannot be safely resized in memory; "
                        "convert it to a georeferenced TIFF first")
                for z,(zw,zh) in enumerate(sizes):
                    level=stage/"tiles"/str(z)
                    level.mkdir(parents=True)
                    image=(original.convert("RGBA") if (zw,zh)==(w,h) else
                           original.resize((zw,zh),Image.Resampling.LANCZOS).convert("RGBA"))
                    for ty in range(levels[z]["tiles_y"]):
                        for tx in range(levels[z]["tiles_x"]):
                            tile=Image.new("RGBA",(TILE,TILE))
                            region=image.crop((tx*TILE,ty*TILE,
                                               min((tx+1)*TILE,zw),
                                               min((ty+1)*TILE,zh)))
                            tile.paste(region,(0,0))
                            (level/f"{tx}_{ty}.rgba").write_bytes(tile.tobytes())
                    image.close()
            checksums=[]
            for z,level in enumerate(levels):
                for ty in range(level["tiles_y"]):
                    for tx in range(level["tiles_x"]):
                        name=f"tiles/{z}/{tx}_{ty}.rgba"
                        checksums.append(sha256(stage/name)+"  "+name)
            (stage/"tiles.sha256").write_text("\n".join(checksums)+"\n",
                                               encoding="ascii")
            metadata = {
                "schema_version":1,"format":"cartorig-rgba-tiles-v1",
                "asset_id":asset_id,"tile_size":TILE,
                "extent":extent,"original_width":w,"original_height":h,
                "levels":levels,"provenance":provenance,
                "raster_builder":"windowed-rasterio-bilinear" if use_windows else
                                 "pillow-lanczos",
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

def reusable_asset(output: Path, asset_id: str, source_sha: str,
                   publisher_image: str, world_file: str) -> bool:
    """Rehash every generated tile before reusing an interrupted producer job."""
    directory=output/asset_id
    path=directory/"index.json"
    if not path.is_file() or directory.is_symlink():
        return False
    try:
        metadata=json.loads(path.read_text(encoding="utf-8"))
        provenance=metadata.get("provenance",{})
        if (metadata.get("schema_version")!=1 or
            metadata.get("format")!="cartorig-rgba-tiles-v1" or
            metadata.get("asset_id")!=asset_id or
            provenance.get("source_sha256")!=source_sha or
            provenance.get("publisher_image")!=publisher_image or
            provenance.get("publisher_world_file")!=world_file):
            return False
        levels=metadata.get("levels",[])
        if not isinstance(levels,list) or not 1<=len(levels)<=20:
            return False
        proof=directory/"tiles.sha256"
        if proof.is_symlink() or not proof.is_file():
            return False
        lines=proof.read_text(encoding="ascii").splitlines()
        expected={}
        for line in lines:
            if len(line)<70 or line[64:66]!="  ":
                return False
            key=line[66:]
            if key in expected or len(line[:64])!=64:
                return False
            expected[key]=line[:64]
        if len(expected)!=sum(l["tiles_x"]*l["tiles_y"] for l in levels):
            return False
        for index,level in enumerate(levels):
            w,h=level["width"],level["height"]
            nx,ny=level["tiles_x"],level["tiles_y"]
            if (level["z"]!=index or not isinstance(w,int) or
                not isinstance(h,int) or w<1 or h<1 or
                nx!=(w+TILE-1)//TILE or ny!=(h+TILE-1)//TILE or
                nx*ny>100000):
                return False
            for ty in range(ny):
                for tx in range(nx):
                    tile=directory/"tiles"/str(index)/f"{tx}_{ty}.rgba"
                    if (tile.is_symlink() or not tile.is_file() or
                        tile.stat().st_size!=TILE*TILE*4 or
                        not hmac.compare_digest(
                            sha256(tile),expected.get(f"tiles/{index}/{tx}_{ty}.rgba",""))):
                        return False
        return True
    except (ValueError,KeyError,TypeError,OSError):
        return False

def compile_archives(manifest: dict, archive_root: Path, output: Path,
                     *, resume: bool=False) -> dict:
    from tools.natural_earth.verify_pack import verify_manifest
    resources=[r for r in manifest.get("resources",[]) if r.get("theme")=="raster"]
    if not resources:
        raise ValueError("no official raster resources found in manifest")
    verified=verify_manifest({"schema_version":1,"resources":resources},archive_root)
    if not verified["complete"]:
        raise ValueError("official raster archives not fully verified: "+
                         json.dumps(verified["failed"][:6]))
    output.mkdir(parents=True,exist_ok=True)
    report={"schema_version":1,"complete":False,"sources_expected":len(resources),
            "sources_converted":0,"assets":[],"failures":[],"reused_assets":0}
    def checkpoint()->None:
        path=output/"validated-raster-assets.json"
        temp=path.with_suffix(".json.tmp")
        temp.write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",
                        encoding="utf-8")
        temp.replace(path)
    for r in resources:
        key=r["resource_id"]
        try:
            archive=archive_root / r["file"]
            if archive.suffix.lower()!=".zip":
                raise ValueError("unsupported publisher raster container (requires ZIP)")
            # verify_manifest already checked source SHA256 and all ZIP CRCs.
            with zipfile.ZipFile(archive) as z:
                names=[i.filename for i in z.infolist() if not i.is_dir()]
                images=[name for name in names
                        if PurePosixPath(name).suffix.lower() in IMAGE_EXTENSIONS]
                geo_images=[(name,find_world_file(names,name)) for name in images]
                unreferenced=[name for name,world in geo_images if world is None]
                missing_tiff=[name for name in unreferenced
                              if PurePosixPath(name).suffix.lower() in (".tif",".tiff")]
                if missing_tiff:
                    raise ValueError("unreferenced publisher TIFF layer: "+missing_tiff[0])
                georeferenced=[(name,world) for name,world in geo_images if world]
                if not georeferenced:
                    raise ValueError("archive contains no georeferenced renderable raster")
                for index,(img,world) in enumerate(georeferenced):
                    asset_id=re.sub(r"[^a-zA-Z0-9_-]","_",
                                    key+"_"+str(index))
                    if resume and reusable_asset(
                            output,asset_id,r["sha256"],img,world):
                        metadata=json.loads((output/asset_id/"index.json").read_text(
                            encoding="utf-8"))
                        report["reused_assets"]+=1
                    else:
                        prior=output/asset_id
                        if prior.exists():
                            if not resume:
                                raise FileExistsError("raster asset already exists: "+asset_id)
                            if prior.is_symlink() or not prior.is_dir():
                                raise ValueError("unsafe existing raster staging path")
                            shutil.rmtree(prior)
                        # Avoid decompressing unchanged atlas images on resume.
                        with tempfile.TemporaryDirectory() as temp:
                            image_path=Path(temp)/"image"
                            with z.open(img) as src, image_path.open("wb") as dst:
                                shutil.copyfileobj(src,dst,1024*1024)
                            suffix=PurePosixPath(img).suffix
                            real_image=image_path.with_suffix(suffix)
                            image_path.rename(real_image)
                            metadata=build_asset(
                                real_image,z.read(world).decode("ascii"),
                                output,asset_id,{
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
            if unreferenced:
                report.setdefault("non_georeferenced_companions",[]).append({
                    "source_id":key,"files":unreferenced})
            report["sources_converted"]+=1
        except Exception as exc:
            report["failures"].append({"resource_id":key,"reason":str(exc)})
        checkpoint()
    report["complete"]=(not report["failures"] and
                        report["sources_converted"]==report["sources_expected"])
    checkpoint()
    return report

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--manifest",type=Path,required=True)
    ap.add_argument("--archives",type=Path,required=True)
    ap.add_argument("--out",type=Path,required=True)
    ap.add_argument("--resume",action="store_true",
                    help="Reuse fully validated source-hash-matching tile atlases")
    args=ap.parse_args()
    report=compile_archives(json.loads(args.manifest.read_text(encoding="utf-8")),
                            args.archives,args.out,resume=args.resume)
    print(json.dumps({k:v for k,v in report.items() if k!="assets"},indent=2))
    if not report["complete"]:
        raise SystemExit(1)

if __name__=="__main__":
    main()
