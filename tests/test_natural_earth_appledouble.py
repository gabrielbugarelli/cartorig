"""A genuine source TIFF must win over non-cartographic AppleDouble .tif/.tfw files."""
import hashlib
from io import BytesIO
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from PIL import Image

from tools.natural_earth.build_rasters import compile_archives

class PublisherMacMetadataTests(unittest.TestCase):
    def test_end_to_end_converter_ignores_appledouble_and_emits_real_tiles(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            raster=Image.new("RGB",(8,4),(27,85,194))
            source=BytesIO()
            raster.save(source,format="TIFF")
            archive=root/"publisher-prisma.zip"
            with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED) as z:
                z.writestr("PRIMSA_SR_50M.tif",source.getvalue())
                z.writestr("PRIMSA_SR_50M.tfw","45\n0\n0\n-45\n-157.5\n67.5\n")
                # Real publisher PRISMA ZIP includes AppleDouble resource forks.
                z.writestr("__MACOSX/._PRIMSA_SR_50M.tif",
                           bytes.fromhex("0005160700020000"))
                z.writestr("__MACOSX/._PRIMSA_SR_50M.tfw",
                           bytes.fromhex("0005160700020000a200"))
                z.writestr(".DS_Store",b"Finder desktop metadata")
            digest=hashlib.sha256(archive.read_bytes()).hexdigest()
            manifest={"schema_version":1,"resources":[{
                "resource_id":"ne-50m-raster-prisma",
                "theme":"raster","scale":"50m","url":"https://naturalearth.s3.amazonaws.com/50m_raster/PRISMA_SR_50M.zip",
                "status":"VERIFIED","file":archive.name,
                "sha256":digest,"archive_bytes":archive.stat().st_size,
            }]}
            report=compile_archives(manifest,root,root/"converted")
            self.assertTrue(report["complete"],report)
            self.assertEqual(report["sources_converted"],1)
            self.assertEqual(len(report["assets"]),1,report)
            asset=report["assets"][0]["asset_id"]
            metadata=json.loads((root/"converted"/asset/"index.json").read_text())
            self.assertEqual(metadata["provenance"]["publisher_image"],"PRIMSA_SR_50M.tif")
            self.assertEqual(metadata["provenance"]["publisher_world_file"],"PRIMSA_SR_50M.tfw")
            self.assertEqual(metadata["extent"],[-180.0,-90.0,180.0,90.0])
            tile=(root/"converted"/asset/"tiles"/"0"/"0_0.rgba").read_bytes()
            self.assertEqual(tile[:4],bytes([27,85,194,255]))

if __name__=="__main__":unittest.main()
