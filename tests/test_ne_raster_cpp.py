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
    # One synthetic level has 65 horizontal tiles, exceeding the new
    # renderer's 64-tile/16MiB RAM budget. An LRU must evict and reopen
    # publisher tiles rather than raising a cache-exhaustion error.
    large=root/"wide_offline"
    large_tiles=large/"tiles"/"0"
    large_tiles.mkdir(parents=True)
    for i in range(65):
        color=bytes([(i*3)%256,(i*7)%256,(i*11)%256,255])
        (large_tiles/f"{i}_0.rgba").write_bytes(color*(256*256))
    large_meta=dict(metadata,asset_id="wide_offline",
                    original_width=65*256,original_height=256,
                    levels=[{"z":0,"width":65*256,"height":256,
                             "tiles_x":65,"tiles_y":1}])
    (large/"index.json").write_text(json.dumps(large_meta),encoding="utf-8")
    wide=launch("wide_offline")
    assert wide.returncode==0,(
        "wide raster with >64 tiles must use bounded LRU",
        wide.stdout,wide.stderr)
    assert "raster_pixels=" in wide.stdout,wide.stdout
    again=launch("wide_offline")
    assert again.returncode==0 and wide.stdout==again.stdout,(
        "bounded cache cannot change deterministic output",again.stdout)
    # All 65 tiles must be consulted, not silently skipped by the LRU.
    (large_tiles/"32_0.rgba").write_bytes(b"corrupt")
    broken=launch("wide_offline")
    assert broken.returncode!=0,"corrupted mid-pyramid tile was skipped"
    print("PASS: offline RGBA rendering; 65-tile LRU; determinism; corruption rejection")
