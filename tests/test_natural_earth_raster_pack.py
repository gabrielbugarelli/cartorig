"""Offline raster ingestion and certified data-pack contract tests."""
from pathlib import Path
import hashlib
import json
import sqlite3
import tempfile
import unittest
import zipfile

from tools.natural_earth import build_pack, build_rasters

class OfflineNaturalEarthPackTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def test_tfw_projection_rejects_rotation_and_bad_extent(self):
        tfw="1.40625\n0\n0\n-0.703125\n-179.296875\n89.6484375\n"
        self.assertEqual(build_rasters.georeference(tfw,256,256),[-180.0,-90.0,180.0,90.0])
        with self.assertRaises(ValueError):
            build_rasters.georeference("1\n0.5\n0\n-1\n-179\n89\n",10,10)
        with self.assertRaises(ValueError):
            build_rasters.georeference("500\n0\n0\n-1\n0\n89\n",10,10)
        self.assertIsNone(build_rasters.find_world_file(["land.jpg"],"land.jpg"))
        self.assertEqual(build_rasters.find_world_file(
            ["folder/land.TFW","folder/land.TIF"],"folder/land.TIF"),
            "folder/land.TFW")

    def make_root(self):
        root=self.root/"pack";root.mkdir()
        for relative in build_pack.REQUIRED:
            path=root/relative;path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b"test-data-"+relative.encode("utf-8"))
        (root/"raster/validated-raster-assets.json").write_text(
            json.dumps({"complete":True,"sources_expected":52,
                        "sources_converted":52,"failures":[]}),encoding="utf-8")
        asset=root/"raster/sample/index.json"
        asset.parent.mkdir(parents=True)
        asset.write_text('{"test":1}',encoding="utf-8")
        return root

    def test_pack_fails_closed_unless_audited(self):
        root=self.make_root()
        with self.assertRaisesRegex(ValueError,"requires a passing"):
            build_pack.build_pack(root,{"complete":False})
        incomplete=build_pack.build_pack(root,{"complete":False},
                                         allow_incomplete=True)
        self.assertFalse(incomplete["complete"])
        self.assertEqual(incomplete["status"],"EXPERIMENTAL_INCOMPLETE")
        self.assertTrue(incomplete["files"])
        source=next(r for r in incomplete["files"] if r["path"]=="vector/catalog.sqlite")
        self.assertEqual(source["sha256"],
                         hashlib.sha256((root/source["path"]).read_bytes()).hexdigest())
        audit={"complete":True,"vector":{"passed":True},"raster":{"passed":True}}
        # A forged 'complete': true without the 215 published vector sources,
        # 52 raster variants and verifiable archive provenance cannot pass.
        with self.assertRaisesRegex(ValueError,"passing source/coverage gate"):
            build_pack.build_pack(root,audit)
        self.assertNotIn("pack.json",{item["path"] for item in incomplete["files"]})
        self.assertEqual(incomplete["pack_id"],build_pack.build_pack(
            root,{"complete":False},allow_incomplete=True)["pack_id"])
        (root/"evil-link").symlink_to(root/"vector/catalog.sqlite")
        with self.assertRaisesRegex(ValueError,"symlinks"):
            build_pack.build_pack(root,audit,allow_incomplete=True)

    def test_windowed_geotiff_builder_uses_bounded_native_tiles(self):
        try:
            from PIL import Image
            import rasterio
        except ImportError:
            self.skipTest("release-machine rasterio and Pillow not installed")
        width,height=1600,1300
        source=self.root/"publisher-high-resolution.tif"
        Image.new("RGB",(width,height),(48,107,188)).save(source)
        dx,dy=360/width,-180/height
        tfw=f"{dx}\n0\n0\n{dy}\n{-180+dx/2}\n{90+dy/2}\n"
        output=self.root/"streamed"
        output.mkdir()
        atlas=build_rasters.build_asset(source,tfw,output,"world_tiff",{
            "source_id":"verified-publisher-raster"})
        self.assertEqual(atlas["raster_builder"],"windowed-rasterio-bilinear")
        for result,expected in zip(atlas["extent"],(-180,-90,180,90)):
            self.assertAlmostEqual(result,expected,places=8)
        self.assertGreater(len(atlas["levels"]),2)
        self.assertEqual((output/"world_tiff/tiles/0/0_0.rgba").read_bytes()[:4],
                         bytes([48,107,188,255]))
        self.assertTrue((output/"world_tiff/tiles.sha256").is_file())

    def test_georeferenced_publisher_image_and_unreferenced_preview(self):
        from PIL import Image
        source=self.root/"map.tif"
        Image.new("RGB",(256,128),(21,52,73)).save(source)
        preview=self.root/"preview.jpg"
        Image.new("RGB",(90,60),(1,1,1)).save(preview)
        folder=self.root/"official"
        folder.mkdir()
        zip_path=folder/"publisher.zip"
        with zipfile.ZipFile(zip_path,"w") as z:
            z.write(source,"map.tif")
            z.writestr("map.tfw","1.40625\n0\n0\n-1.40625\n-179.296875\n89.296875\n")
            z.write(preview,"preview.jpg")
        record={"resource_id":"ne-50m-raster-a","theme":"raster",
                "file":"publisher.zip","archive_bytes":zip_path.stat().st_size,
                "sha256":hashlib.sha256(zip_path.read_bytes()).hexdigest(),
                "status":"VERIFIED"}
        report=build_rasters.compile_archives(
            {"schema_version":1,"resources":[record]},folder,self.root/"converted")
        self.assertTrue(report["complete"])
        self.assertEqual(len(report["assets"]),1,
                         "publisher preview incorrectly counted as geospatial imagery")
        self.assertEqual(report["non_georeferenced_companions"][0]["files"],
                         ["preview.jpg"])

    def test_verified_raster_zip_to_native_tile_asset(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("Pillow is an explicit build-time dependency")
        img=self.root/"publisher.tif"
        Image.new("RGB",(256,128),(12,89,190)).save(img)
        # Pixel-center TFW for a 256x128 global raster.
        tfw="1.40625\n0\n0\n-1.40625\n-179.296875\n89.296875\n"
        archive_dir=self.root/"archives";archive_dir.mkdir()
        z=archive_dir/"official.zip"
        with zipfile.ZipFile(z,"w") as archive:
            archive.write(img,"map.tif")
            archive.writestr("map.tfw",tfw)
        record={"resource_id":"ne-50m-raster-example","theme":"raster",
                "file":"official.zip","archive_bytes":z.stat().st_size,
                "sha256":hashlib.sha256(z.read_bytes()).hexdigest(),
                "status":"VERIFIED"}
        report=build_rasters.compile_archives(
            {"schema_version":1,"resources":[record]},
            archive_dir,self.root/"tiles")
        self.assertTrue(report["complete"],report)
        self.assertEqual(report["sources_converted"],1)
        asset=report["assets"][0]["asset_id"]
        base=self.root/"tiles"/asset
        manifest=json.loads((base/"index.json").read_text())
        self.assertEqual(manifest["extent"],[-180,-90,180,90])
        self.assertEqual(manifest["original_width"],256)
        self.assertEqual((base/"tiles/0/0_0.rgba").stat().st_size,256*256*4)
        self.assertEqual((base/"tiles/0/0_0.rgba").read_bytes()[:4],
                         bytes([12,89,190,255]))
        # Hash mismatch may never produce a trusted tile tree.
        record["sha256"]="0"*64
        with self.assertRaises(ValueError):
            build_rasters.compile_archives(
                {"schema_version":1,"resources":[record]},
                archive_dir,self.root/"unverified")

if __name__=="__main__":
    unittest.main()
