"""Coverage gate must never mistake a sample or a URL for a full data pack."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.natural_earth import coverage, materialize, verify_pack

class CompletenessTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root=Path(temp.name)
        self.pin={"layer_count":2,"layers":[
            {"source_path":"10m_cultural/ne_10m_admin_0_countries.shp"},
            {"source_path":"50m_physical/ne_50m_rivers_lake_centerlines.shp"}]}
    def test_empty_or_discovered_is_blocked(self):
        r=coverage.audit(self.pin)
        self.assertFalse(r["complete"])
        self.assertEqual(r["vector"]["expected"],2)
        self.assertEqual(len(r["vector"]["missing"]),2)
        self.assertEqual(len(r["pages"]["missing_categories"]),8)
    def test_duplicate_layer_pin_is_rejected(self):
        d={"layer_count":2,"layers":[self.pin["layers"][0],self.pin["layers"][0]]}
        with self.assertRaises(ValueError):coverage.audit(d)
    def test_materializer_is_offline_without_flag(self):
        manifest={"schema_version":1,"resources":[
            {"resource_id":"ne-10m-countries","url":"https://naciscdn.org/naturalearth/10m/cultural/a.zip",
             "status":"DISCOVERED_UNVERIFIED","sha256":None}]}
        result=materialize.materialize(manifest,self.root,allow_network=False)
        self.assertFalse(result["summary"]["complete"])
        self.assertEqual(result["resources"][0]["status"],"NOT_INSTALLED")
        self.assertFalse((self.root/"archives"/"ne-10m-countries.zip").exists())
    def test_reuse_previously_verified_local_archive(self):
        path=self.root/"archives"/"ne-10m-countries.zip"
        path.parent.mkdir(parents=True)
        with zipfile.ZipFile(path,"w") as z:z.writestr("countries.shp",b"offline")
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        manifest={"schema_version":1,"resources":[
            {"resource_id":"ne-10m-countries","url":"https://naciscdn.org/naturalearth/10m/cultural/a.zip",
             "status":"DISCOVERED_UNVERIFIED","sha256":digest}]}
        result=materialize.materialize(manifest,self.root,allow_network=False)
        self.assertTrue(result["summary"]["complete"])
        self.assertEqual(result["resources"][0]["status"],"VERIFIED")
        report=verify_pack.verify_manifest(result,self.root)
        self.assertTrue(report["complete"])
        self.assertEqual(report["verified"],1)

if __name__=="__main__":
    unittest.main()
