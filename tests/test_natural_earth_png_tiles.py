"""PNG v2 atlas: SHA256 resale, lossless RGBA, legacy v1 coexistence."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

from tools.natural_earth import build_rasters

WORLD="1\n0\n0\n-1\n-179.5\n89.5\n"
SHA="a"*64
PROVENANCE={"source_id":"ne-50m-synthetic-png",
            "source_sha256":SHA,"publisher_image":"source.tif",
            "publisher_world_file":"source.tfw"}

class PNGTileTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.image=self.root/"source.tif"
        Image.new("RGBA",(256,128),(15,35,55,220)).save(self.image)
        self.out=self.root/"atlases"
        self.out.mkdir()
    def test_png_atlas_is_lossless_and_rehashes_on_resume(self):
        data=build_rasters.build_asset(
            self.image,WORLD,self.out,"compressed",PROVENANCE,tile_format="png")
        self.assertEqual(data["format"],"cartorig-png-tiles-v2")
        first=self.out/"compressed"/"tiles"/"0"/"0_0.png"
        self.assertTrue(first.is_file())
        with Image.open(first) as png:
            self.assertEqual(png.size,(256,256))
            self.assertEqual(png.getpixel((0,0)),(15,35,55,220))
            self.assertEqual(png.getpixel((128,127)),(15,35,55,220))
            self.assertEqual(png.getpixel((128,255)),(0,0,0,0))
        self.assertLess(first.stat().st_size,256*256*4//4)
        self.assertTrue(build_rasters.reusable_asset(
            self.out,"compressed",SHA,"source.tif","source.tfw",tile_format="png"))
        self.assertFalse(build_rasters.reusable_asset(
            self.out,"compressed",SHA,"source.tif","source.tfw",tile_format="rgba"))
        self.assertTrue(build_rasters.reusable_asset(
            self.out,"compressed",SHA,"source.tif","source.tfw"))
        saved=first.read_bytes()
        first.write_bytes(saved[:-12]+b"X"+saved[-11:])
        self.assertFalse(build_rasters.reusable_asset(
            self.out,"compressed",SHA,"source.tif","source.tfw"))
    def test_raw_v1_backward_compatibility(self):
        data=build_rasters.build_asset(
            self.image,WORLD,self.out,"legacy",PROVENANCE,tile_format="rgba")
        self.assertEqual(data["format"],"cartorig-rgba-tiles-v1")
        tile=self.out/"legacy"/"tiles"/"0"/"0_0.rgba"
        self.assertEqual(tile.stat().st_size,256*256*4)
        self.assertTrue(build_rasters.reusable_asset(
            self.out,"legacy",SHA,"source.tif","source.tfw",tile_format="rgba"))
        self.assertFalse(build_rasters.reusable_asset(
            self.out,"legacy",SHA,"source.tif","source.tfw",tile_format="png"))
    def test_unknown_tile_format_rejected(self):
        with self.assertRaisesRegex(ValueError,"tile format"):
            build_rasters.build_asset(
                self.image,WORLD,self.out,"invalid",PROVENANCE,tile_format="gif")

if __name__=="__main__":
    unittest.main()
