"""Offline complete-manifest identity, tamper and symlink refusal."""
from __future__ import annotations
import json
from pathlib import Path
import tempfile
import unittest
from tools.natural_earth import build_pack,verify_release

class OfflineReleaseVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        for relative in build_pack.REQUIRED:
            path=self.root/relative
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b"local synthetic artifact")
        raster=self.root/"raster/validated-raster-assets.json"
        raster.write_text(json.dumps({"complete":False,"sources_expected":1,
            "sources_converted":0,"failures":["synthetic"]}),encoding="utf-8")
        build_pack.build_pack(self.root,{"complete":False},allow_incomplete=True)

    def test_rehash_files_and_manifest_identity(self):
        report=verify_release.verify_release(self.root,allow_incomplete=True)
        self.assertFalse(report["complete"])
        self.assertEqual(report["files_verified"],len(build_pack.REQUIRED))
        with self.assertRaisesRegex(ValueError,"incomplete"):
            verify_release.verify_release(self.root)
        data=json.loads((self.root/"pack.json").read_text())
        data["pack_id"]="f"*64
        (self.root/"pack.json").write_text(json.dumps(data),encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"identity"):
            verify_release.verify_release(self.root,allow_incomplete=True)

    def test_claimed_51_215_requires_real_source_and_atlas_provenance(self):
        # A valid self-consistent SHA256 pack.json does not establish
        # provenance of 51 publisher rasters merely by setting count fields.
        manifest=self.root/"pack.json"
        data=json.loads(manifest.read_text(encoding="utf-8"))
        data["raster_sources"]=51
        data["vector_sources"]=215
        manifest.write_text(json.dumps(data),encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"source/atlas provenance"):
            verify_release.verify_release(self.root,allow_incomplete=True)

    def test_experimental_atlas_cross_checks_each_publisher_sha_and_tile(self):
        import hashlib
        records=[]
        assets=[]
        missing="ne-10m-missing"
        for index in range(51):
            ident=f"ne-10m-test-{index:02d}"
            archive_hash=hashlib.sha256(ident.encode()).hexdigest()
            records.append({
                "resource_id":ident,"theme":"raster","scale":"10m",
                "url":"https://naturalearth.example/"+ident+".zip",
                "status":"VERIFIED","sha256":archive_hash,"archive_bytes":100
            })
            asset_id=ident+"_0"
            location=self.root/"raster"/asset_id
            tile=location/"tiles/0/0_0.png"
            tile.parent.mkdir(parents=True)
            tile.write_bytes(b"test-tile-"+ident.encode())
            checksum=hashlib.sha256(tile.read_bytes()).hexdigest()
            (location/"tiles.sha256").write_text(
                checksum+"  tiles/0/0_0.png\n",encoding="ascii")
            (location/"index.json").write_text(json.dumps({
                "asset_id":asset_id,"format":"cartorig-png-tiles-v2",
                "provenance":{"source_id":ident,
                              "source_sha256":archive_hash,
                              "publisher_image":"world.tif",
                              "publisher_world_file":"world.tfw"}
            }),encoding="utf-8")
            assets.append({"asset_id":asset_id,"source_id":ident,
                           "status":"VALIDATED"})
        records.append({
            "resource_id":missing,"theme":"raster","scale":"10m",
            "url":"https://naturalearth.example/missing.zip",
            "status":"KNOWN_UNAVAILABLE","sha256":None,
            "archive_bytes":None,"upstream_issue":"#4"
        })
        for name,value in (
            ("provenance/official_sources.json",{
                "resources":[{key:entry[key] for key in
                              ("resource_id","theme","scale","url")}
                             for entry in records]}),
            ("provenance/source-archives.json",{"resources":records}),
            ("provenance/coverage-report.json",{
                "complete":False,"vector":{"indexed":215},
                "raster":{"source_variants":52,"missing":[missing]}}),
            ("raster/validated-raster-assets.json",{
                "complete":True,"sources_expected":51,
                "sources_converted":51,"failures":[],"assets":assets}),
        ):
            target=self.root/name
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_text(json.dumps(value),encoding="utf-8")
        coverage={"complete":False,"vector":{"indexed":215}}
        build_pack.build_pack(self.root,coverage,allow_incomplete=True)
        self.assertEqual(verify_release.verify_release(
            self.root,allow_incomplete=True)["raster_sources"],51)
        # Rebuild the outer manifest after deliberate corruption. Even when
        # all file hashes match the new self-declared pack_id, the source
        # and tile provenance must detect a mismatched atlas.
        path=self.root/"raster"/assets[0]["asset_id"]/"index.json"
        index=json.loads(path.read_text())
        index["provenance"]["source_sha256"]="0"*64
        path.write_text(json.dumps(index))
        build_pack.build_pack(self.root,coverage,allow_incomplete=True)
        with self.assertRaisesRegex(ValueError,"source SHA256/provenance"):
            verify_release.verify_release(self.root,allow_incomplete=True)

    def test_reject_unlisted_files_symlinks_and_tampered_bytes(self):
        source=self.root/"vector/catalog.sqlite"
        source.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError,"tampered"):
            verify_release.verify_release(self.root,allow_incomplete=True)
        source.write_bytes(b"local synthetic artifact")
        extra=self.root/"unexpected.txt"
        extra.write_text("not in manifest",encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"undeclared"):
            verify_release.verify_release(self.root,allow_incomplete=True)
        extra.unlink()
        extra.symlink_to(source)
        with self.assertRaisesRegex(ValueError,"symlink"):
            verify_release.verify_release(self.root,allow_incomplete=True)

if __name__=="__main__":
    unittest.main()
