"""NE-FETCH-01: deterministic family selection, bounded archive integrity tests."""
from __future__ import annotations
from io import BytesIO
import hashlib
import tempfile
from pathlib import Path
import unittest
import zipfile

from tools.natural_earth import probe_families, source_lock

class FakeHead:
    def __init__(self,size,*,url):
        self.headers={"Content-Length":str(size),"Accept-Ranges":"bytes",
                      "ETag":'"test-publisher-etag"'}
        self.url=url
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def geturl(self):return self.url
    def getcode(self):return 200

def fake_inventory():
    rows=[]
    for i in range(52):
        family=i%16
        scale="10m" if family<7 else "50m"
        rows.append({"resource_id":f"ne-{scale}-raster-test-{i}",
                     "scale":scale,"theme":"raster",
                     "source_page":f"https://www.naturalearthdata.com/downloads/{scale}-raster-data/test-family-{family}/",
                     "url":f"https://www.naturalearthdata.com/download/{scale}/raster/TEST_{i}.zip",
                     "archive_format":"zip",
                     "theme_version":"3.2.0"})
    return {"schema_version":1,
            "pages":[{"url":"publisher","status":"INDEXED"}],
            "resources":rows}

def official_zip():
    output=BytesIO()
    with zipfile.ZipFile(output,"w",compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("map/earth.tif",b"TIFF-SOURCE-CONTENTS")
        z.writestr("map/earth.tfw","0.5\n0\n0\n-0.5\n-179.75\n89.75\n")
    return output.getvalue()

class FamilyTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root=Path(temp.name)
        self.report=fake_inventory()
        self.lock=source_lock.discovery_fingerprint(self.report)
        self.zip=official_zip()
        self.requests=[]
    def opener(self,req,timeout):
        self.assertEqual(req.get_method(),"HEAD")
        self.requests.append(req.full_url)
        return FakeHead(len(self.zip),url=req.full_url)
    def downloader(self,url,path,max_bytes):
        self.assertTrue(url.startswith("https://naturalearth.s3.amazonaws.com/"))
        self.assertGreater(max_bytes,len(self.zip))
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(self.zip)
        return len(self.zip),hashlib.sha256(self.zip).hexdigest()
    def test_52_real_head_metadata_and_16_selected(self):
        res=probe_families.run(self.report,self.lock,out=self.root,
                               allow_network=True,opener=self.opener,
                               downloader=self.downloader)
        self.assertEqual(res["source_head_verified"],52)
        self.assertEqual(res["families_expected"],16)
        self.assertEqual(len(res["families"]),16)
        self.assertEqual(res["sample_mode"],"head-only")
        self.assertEqual(res["family_samples_verified"],0)
        self.assertEqual(len(self.requests),52)
        self.assertTrue((self.root/"family-probe.json").is_file())
    def test_downloads_and_certifies_16_zip_samples(self):
        res=probe_families.run(self.report,self.lock,out=self.root,
                               allow_network=True,fetch_samples=True,
                               opener=self.opener,downloader=self.downloader)
        self.assertTrue(res["complete"])
        self.assertEqual(res["family_samples_verified"],16)
        self.assertEqual(len({r["family"] for r in res["families"]}),16)
        self.assertEqual(res["bytes_acquired_and_discarded"],16*len(self.zip))
        self.assertTrue(all(len(r["georeferenced_images"])==1 for r in res["families"]))
        self.assertFalse((self.root/"staging").exists() and list((self.root/"staging").iterdir()))
    def test_blocks_unreviewed_discovery(self):
        bad=dict(self.lock,source_rows_sha256="a"*64)
        with self.assertRaisesRegex(source_lock.SourceLockError,"differs"):
            probe_families.run(self.report,bad,out=self.root,
                               allow_network=True,opener=self.opener)
    def test_network_opt_in_and_absolute_budget_hardstop(self):
        with self.assertRaisesRegex(ValueError,"--allow-network"):
            probe_families.run(self.report,self.lock,out=self.root)
        with self.assertRaisesRegex(ValueError,"authorized free-runner cap"):
            probe_families.run(self.report,self.lock,out=self.root,
                               allow_network=True,max_total_bytes=probe_families.MAX_TOTAL+1)
    def test_appledouble_resource_forks_are_not_cartographic_images(self):
        archive=self.root/"prisma-source.zip"
        with zipfile.ZipFile(archive,"w") as z:
            z.writestr("PRISMA.tif",b"actual-TIFF-contents")
            z.writestr("PRISMA.tfw","0.25\\n0\\n0\\n-0.25\\n-179.875\\n89.875\\n".replace("\\n","\n"))
            z.writestr("__MACOSX/._PRISMA.tif",bytes.fromhex("0005160700020000"))
            z.writestr("__MACOSX/._PRISMA.tfw",bytes.fromhex("0005160700020000a2"))
            z.writestr(".DS_Store",b"Finder metadata")
        result=probe_families.inspect_zip(archive)
        self.assertEqual(result["ignored_macos_metadata_members"],3)
        self.assertEqual(len(result["georeferenced_images"]),1)
        self.assertEqual(result["georeferenced_images"][0]["image"],"PRISMA.tif")
        self.assertFalse(probe_families.build_rasters.is_payload_member(
            "__MACOSX/._PRISMA.tfw"))

    def test_corrupt_archive_never_reports_complete(self):
        def tampered(url,path,max_bytes):
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b"bad")
            return len(self.zip),hashlib.sha256(b"bad").hexdigest()
        result=probe_families.run(self.report,self.lock,out=self.root,
                                  allow_network=True,fetch_samples=True,
                                  opener=self.opener,downloader=tampered)
        self.assertFalse(result["complete"])
        self.assertEqual(result["family_samples_verified"],0)
        self.assertTrue(all(r["status"]=="ACQUISITION_BLOCKED" for r in result["families"]))

if __name__=="__main__":unittest.main()
