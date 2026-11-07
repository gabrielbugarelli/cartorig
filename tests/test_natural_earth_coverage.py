"""Coverage gate must never mistake a sample or a URL for a full data pack."""
import hashlib
import json
import sqlite3
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
    def test_complete_offline_pack_requires_acquired_sources_and_raster_derivatives(self):
        catalog=self.root/"catalog.sqlite"
        db=sqlite3.connect(catalog)
        db.execute("CREATE TABLE layers(table_name TEXT)")
        db.executemany("INSERT INTO layers VALUES(?)",[
            ("ne_10m_admin_0_countries",),
            ("ne_50m_rivers_lake_centerlines",),
        ])
        db.commit();db.close()
        pages=[]
        for scale,theme in sorted(coverage.GROUPS):
            category="raster-data" if theme=="raster" else theme+"-vectors"
            root=f"https://www.naturalearthdata.com/downloads/{scale}-{category}/"
            pages.append({"status":"INDEXED","url":root})
            for index in range(1,coverage.RASTER_COUNTS.get(scale,0)):
                if theme=="raster":
                    pages.append({"status":"INDEXED",
                                  "url":root+f"raster-family-{index}/"})
        source_id="ne-50m-raster-test"
        source_url="https://naciscdn.org/naturalearth/50m/raster/test.zip"
        sources={"pages":pages,"resources":[
            {"theme":"raster","resource_id":source_id,"url":source_url,
             "status":"DISCOVERED_UNVERIFIED"}]}
        archive={"summary":{"complete":True},"resources":[
            {"resource_id":source_id,"url":source_url,"status":"VERIFIED",
             "sha256":"a"*64,"archive_bytes":123}]}
        derivatives={"complete":True,"sources_converted":1,"sources_expected":1,
                     "failures":[],"assets":[
                         {"source_id":source_id,"status":"VALIDATED"}]}
        complete=coverage.audit(self.pin,catalog,sources,archive,derivatives)
        self.assertTrue(complete["complete"],complete)
        self.assertEqual(complete["vector"]["indexed"],2)
        self.assertEqual(complete["raster"]["source_variants"],1)
        damaged=dict(archive)
        damaged["resources"]=[dict(archive["resources"][0],sha256=None)]
        self.assertFalse(coverage.audit(
            self.pin,catalog,sources,damaged,derivatives)["complete"])
        self.assertFalse(coverage.audit(
            self.pin,catalog,sources,archive,
            dict(derivatives,complete=False))["complete"])
        self.assertFalse(coverage.audit(
            self.pin,catalog,sources,
            dict(archive,summary={"complete":False}),derivatives)["complete"])

    def test_official_publisher_s3_fallback_is_raster_only_and_safe(self):
        url="https://www.naturalearthdata.com/download/50m/raster/MSR_50M.zip"
        record={"theme":"raster","scale":"50m","url":url}
        self.assertEqual(
            materialize.official_raster_mirror(record),
            "https://naturalearth.s3.amazonaws.com/50m_raster/MSR_50M.zip")
        for change in (
            {"theme":"physical"},
            {"url":"https://evil.example/download/50m/raster/MSR_50M.zip"},
            {"url":"https://www.naturalearthdata.com/download/50m/raster/../evil.zip"},
            {"scale":"10m"},
            {"url":url+"?debug=true"},
        ):
            self.assertIsNone(
                materialize.official_raster_mirror(dict(record,**change)))

    def test_materializer_uses_official_mirror_only_after_verified_failure(self):
        from unittest.mock import patch
        url="https://www.naturalearthdata.com/download/50m/raster/MSR_50M.zip"
        source={"resource_id":"ne-50m-raster-test","theme":"raster",
                "scale":"50m","url":url,"status":"DISCOVERED_UNVERIFIED"}
        sample=self.root/"archive.zip"
        with zipfile.ZipFile(sample,"w") as z:z.writestr("MSR_50M.tfw",b"safe")
        payload=sample.read_bytes()
        urls=[]
        def fake_fetch(request,path):
            urls.append(request)
            if request==url:
                raise ValueError("publisher WordPress URL no longer available")
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(payload)
            return len(payload),hashlib.sha256(payload).hexdigest()
        with patch.object(materialize,"download_and_hash",side_effect=fake_fetch):
            report=materialize.materialize(
                {"schema_version":1,"resources":[source]},
                self.root/"acquired",allow_network=True)
        self.assertTrue(report["summary"]["complete"],report)
        self.assertEqual(urls,[url,"https://naturalearth.s3.amazonaws.com/50m_raster/MSR_50M.zip"])
        self.assertEqual(report["resources"][0]["url"],url)
        self.assertEqual(report["resources"][0]["acquisition_url"],urls[-1])

    def test_resumable_acquisition_reuses_verified_archives_and_rejects_stale_source(self):
        from unittest.mock import patch
        root=self.root/"release"
        a="https://naturalearth.s3.amazonaws.com/50m_raster/A.zip"
        b="https://naturalearth.s3.amazonaws.com/50m_raster/B.zip"
        inventory={"schema_version":1,"resources":[
            {"resource_id":ident,"theme":"raster","scale":"50m","url":url,
             "status":"DISCOVERED_UNVERIFIED"}
            for ident,url in (("ne-50m-raster-a",a),("ne-50m-raster-b",b))]}
        sample=self.root/"publisher.zip"
        with zipfile.ZipFile(sample,"w") as z:z.writestr("world.tfw",b"source")
        data=sample.read_bytes()
        calls=[]
        def fake(url,path):
            calls.append(url)
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(data)
            return len(data),hashlib.sha256(data).hexdigest()
        with patch.object(materialize,"download_and_hash",side_effect=fake):
            one=materialize.materialize(inventory,root,allow_network=True,max_downloads=1)
            self.assertEqual(one["summary"]["verified"],1)
            two=materialize.materialize(inventory,root,allow_network=True,max_downloads=1)
            self.assertTrue(two["summary"]["complete"])
            self.assertEqual(calls,[a,b])
            self.assertTrue(materialize.materialize(inventory,root)["summary"]["complete"])
            self.assertEqual(calls,[a,b])
            (root/"archives/ne-50m-raster-a.zip").write_bytes(b"damaged")
            self.assertTrue(materialize.materialize(
                inventory,root,allow_network=True,max_downloads=1)["summary"]["complete"])
            self.assertEqual(calls,[a,b,a])
            changed={"schema_version":1,"resources":[
                dict(x,url="https://naturalearth.s3.amazonaws.com/50m_raster/C.zip")
                if x["resource_id"]=="ne-50m-raster-a" else x
                for x in inventory["resources"]]}
            self.assertFalse(materialize.materialize(changed,root)["summary"]["complete"])

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
