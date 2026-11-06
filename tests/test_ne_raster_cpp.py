"""Synthetic real-pixel tile atlas -> native C++ raster renderer, offline."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

exe=Path(sys.argv[1])

with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary)
    atlas=root/"synthetic_10m"
    tiles=atlas/"tiles"/"0"
    tiles.mkdir(parents=True)
    (tiles/"0_0.rgba").write_bytes(bytes([222,12,65,255])*(256*256))
    metadata={
       "schema_version":1,"format":"cartorig-rgba-tiles-v1",
       "asset_id":"synthetic_10m","tile_size":256,
       "extent":[-180,-90,180,90],
       "original_width":256,"original_height":256,
       "levels":[{"z":0,"width":256,"height":256,"tiles_x":1,"tiles_y":1}]
    }
    (atlas/"index.json").write_text(json.dumps(metadata),encoding="utf-8")
    def launch(name):
        return subprocess.run([str(exe),str(root),name],
                              capture_output=True,text=True,encoding="utf-8",timeout=25)
    success=launch("synthetic_10m")
    assert success.returncode==0,(success.stdout,success.stderr)
    assert "raster_pixels=" in success.stdout,success.stdout
    assert "atlas_levels=1" in success.stdout,success.stdout
    assert launch("../../outside").returncode!=0,"traversal attempt accepted"
    (tiles/"0_0.rgba").write_bytes(b"short")
    assert launch("synthetic_10m").returncode!=0,"corrupt tile accepted"
    print("PASS: offline synthetic RGBA atlas painted real pixels and rejected unsafe assets")
