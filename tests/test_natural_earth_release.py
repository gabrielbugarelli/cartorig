"""Synthetic end-to-end offline Natural Earth release producer acceptance."""
from __future__ import annotations
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import zipfile
from tools.natural_earth import assemble_pack, release_pipeline, verify_pack

class ProducerTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root=Path(temp.name)

    def fixture(self):
        from PIL import Image
        root=self.root
        gpkg=root/"world.gpkg"
        con=sqlite3.connect(gpkg)
        try:
            con.executescript("""
              CREATE TABLE gpkg_contents(table_name TEXT,data_type TEXT);
              CREATE TABLE gpkg_geometry_columns(table_name TEXT,column_name TEXT,geometry_type_name TEXT);
              CREATE TABLE ne_10m_admin_0_countries(
                fid INTEGER PRIMARY KEY,name TEXT,name_en TEXT,
                adm0_a3 TEXT,continent TEXT,geometry BLOB);
              INSERT INTO gpkg_contents VALUES('ne_10m_admin_0_countries','features');
              INSERT INTO gpkg_geometry_columns VALUES(
                'ne_10m_admin_0_countries','geometry','POLYGON');
              INSERT INTO ne_10m_admin_0_countries(name,name_en,adm0_a3,continent)
                VALUES('Brazil','Brazil','BRA','South America');
            """)
            con.commit()
        finally:con.close()
        supplement=root/"supplements.gpkg"
        supplement.write_bytes(b"synthetic supplement, intentionally uncertified")
        img=root/"original.tif"
        Image.new("RGB",(256,128),(17,90,211)).save(img)
        downloads=root/"downloads"
        downloads.mkdir()
        archive=downloads/"publisher.zip"
        with zipfile.ZipFile(archive,"w") as z:
            z.write(img,"world.tif")
            z.writestr("world.tfw","1.40625\n0\n0\n-1.40625\n-179.296875\n89.296875\n")
        record={"resource_id":"ne-50m-raster-fixture",
                "url":"https://naturalearth.s3.amazonaws.com/50m_raster/fixture.zip",
                "theme":"raster","scale":"50m","status":"VERIFIED",
                "file":"publisher.zip","archive_bytes":archive.stat().st_size,
                "sha256":verify_pack.sha256_file(archive)}
        source=root/"official_sources.json"
        source.write_text(json.dumps({"schema_version":1,"pages":[],
            "resources":[dict(record,status="DISCOVERED_UNVERIFIED")]}),encoding="utf-8")
        archived=root/"archives.json"
        archived.write_text(json.dumps({"schema_version":1,
            "resources":[record],"summary":{"complete":True}}),encoding="utf-8")
        vector_pin=root/"vector_pin.json"
        vector_pin.write_text(json.dumps({"layer_count":1,"layers":[
            {"source_path":"10m_cultural/ne_10m_admin_0_countries.shp"}]}),
            encoding="utf-8")
        supplement_pin=root/"supplement_pin.json"
        supplement_pin.write_text(json.dumps({"entries":[]}),encoding="utf-8")
        return dict(vector=gpkg,supplement=supplement,sources=source,
                    archives=archived,archive_root=downloads,
                    vector_pin=vector_pin,supplement_pin=supplement_pin)

    def test_explicit_offline_mode_never_fetches_publisher_inventory(self):
        workspace=self.root/"workspace"
        workspace.mkdir()
        with patch.object(release_pipeline.inventory,"audit",
                          side_effect=AssertionError("unexpected network request")):
            with self.assertRaisesRegex(release_pipeline.ReleaseNotReady,
                                        "inventory is absent"):
                release_pipeline._load_verified_inventory(workspace,False)
        self.assertFalse((workspace/"official_sources.json").exists())

    def test_official_vector_archive_fails_closed_on_sha_mismatch(self):
        folder=self.root/"publisher"
        folder.mkdir()
        (folder/"natural_earth_vector.gpkg.zip").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError,"SHA256 mismatch"):
            release_pipeline._extract_pinned_vector(self.root,False)

    def test_staged_build_source_pin_changes_and_verified_raster_resume(self):
        cfg=self.fixture()
        dest=self.root/"CartoRigNaturalEarth"
        stage=self.root/".CartoRigNaturalEarth.assembling"
        with self.assertRaisesRegex(ValueError,"audit failed"):
            assemble_pack.assemble(**cfg,out=dest)
        self.assertFalse(dest.exists())
        self.assertTrue((stage/"raster/ne-50m-raster-fixture_0/index.json").is_file())
        self.assertTrue((stage/".cartorig-build-inputs.json").is_file())
        with self.assertRaisesRegex(FileExistsError,"partial producer build"):
            assemble_pack.assemble(**cfg,out=dest,allow_incomplete=True)
        different=dict(cfg)
        pin=self.root/"other.json"
        pin.write_text(json.dumps({"layer_count":0,"layers":[]}),encoding="utf-8")
        different["vector_pin"]=pin
        with self.assertRaisesRegex(ValueError,"provenance differs"):
            assemble_pack.assemble(**different,out=dest,
                                   allow_incomplete=True,resume=True)
        report=assemble_pack.assemble(**cfg,out=dest,
                                      allow_incomplete=True,resume=True)
        self.assertFalse(report["complete"])
        self.assertEqual(report["raster_sources"],1)
        self.assertEqual(report["reused_raster_assets"],1)
        self.assertTrue(dest.is_dir())
        self.assertFalse(stage.exists())
        manifest=json.loads((dest/"pack.json").read_text())
        self.assertEqual(manifest["status"],"EXPERIMENTAL_INCOMPLETE")
        self.assertGreater(len(manifest["files"]),7)
        self.assertEqual(len(manifest["pack_id"]),64)
        with self.assertRaises(FileExistsError):
            assemble_pack.assemble(**cfg,out=dest,allow_incomplete=True,resume=True)

if __name__=="__main__":
    unittest.main()
