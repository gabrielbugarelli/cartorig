"""Release-machine-only Natural Earth publisher PSD composite ingestion."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from PIL import Image
from tools.natural_earth import build_rasters

@unittest.skipUnless(shutil.which("magick"),"Release workstation requires ImageMagick 7")
class PublisherPSDTests(unittest.TestCase):
    def test_native_rgba_composite_and_source_tile_integrity(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            png=root/"original.png"
            Image.new("RGB",(256,128),(22,75,173)).save(png)
            psd=root/"publisher.psd"
            subprocess.run(["magick",str(png),str(psd)],check=True)
            tiles=root/"out"
            tiles.mkdir()
            metadata=build_rasters.build_asset(
                psd,
                "1.40625\n0\n0\n-1.40625\n-179.296875\n89.296875\n",
                tiles,"psd_bathymetry",{"source_sha256":"a"*64})
            self.assertEqual(metadata["raster_builder"],"publisher-psd-composite-windowed")
            self.assertEqual(
                (tiles/"psd_bathymetry/tiles/0/0_0.rgba").read_bytes()[:4],
                bytes([22,75,173,255]))
            self.assertTrue(build_rasters.reusable_asset(
                tiles,"psd_bathymetry","a"*64,None,None))
            tile=tiles/"psd_bathymetry/tiles/0/0_0.rgba"
            tile.write_bytes(bytes([0])*tile.stat().st_size)
            self.assertFalse(build_rasters.reusable_asset(
                tiles,"psd_bathymetry","a"*64,None,None))

if __name__=="__main__":
    unittest.main()
