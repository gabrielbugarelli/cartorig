"""Reviewed locks prohibit a silently modified publisher source set."""
import copy
import unittest
from tools.natural_earth import source_lock

class SourceLockTests(unittest.TestCase):
    def make_fixtures(self):
        urls=[f"https://naturalearth.s3.amazonaws.com/50m_raster/DEMO_{i}.zip"
              for i in range(2)]
        records=[{"resource_id":f"ne-50m-raster-{i}","theme":"raster","scale":"50m",
                  "url":url,"label":f"demo-{i}","source_page":"publisher",
                  "theme_version":"3.2.0"} for i,url in enumerate(urls)]
        inventory={"schema_version":1,"pages":[{"status":"INDEXED","url":"official"}],
                   "resources":records}
        acquired={"schema_version":1,"resources":[dict(r,status="VERIFIED",
                    sha256=str(i)*64,archive_bytes=123+i,acquisition_url=r["url"])
                    for i,r in enumerate(records)]}
        return inventory,acquired
    def test_snapshot_and_verification(self):
        inventory,acquired=self.make_fixtures()
        locked=source_lock.freeze(inventory,acquired,expected=2)
        self.assertEqual(locked["baseline_variants"],2)
        self.assertEqual(len(locked["resources"]),2)
        source_lock.verify(locked,inventory,acquired,expected=2)
    def test_sha_and_source_url_tampering_rejected(self):
        inventory,acquired=self.make_fixtures()
        locked=source_lock.freeze(inventory,acquired,expected=2)
        changed=copy.deepcopy(acquired)
        changed["resources"][0]["sha256"]="f"*64
        with self.assertRaisesRegex(source_lock.SourceLockError,"differs"):
            source_lock.verify(locked,inventory,changed,expected=2)
        changed=copy.deepcopy(inventory)
        changed["resources"][0]["url"]="https://naturalearth.s3.amazonaws.com/50m_raster/OTHER.zip"
        with self.assertRaises(source_lock.SourceLockError):
            source_lock.verify(locked,changed,acquired,expected=2)
    def test_missing_extra_unverified_and_duplicate_rejected(self):
        inventory,acquired=self.make_fixtures()
        for edit in (lambda d:d.pop(),lambda d:d.append(d[0])):
            broken=copy.deepcopy(inventory);edit(broken["resources"])
            with self.assertRaises(source_lock.SourceLockError):
                source_lock.freeze(broken,acquired,expected=2)
        broken=copy.deepcopy(acquired);broken["resources"][0]["status"]="BLOCKED"
        with self.assertRaisesRegex(source_lock.SourceLockError,"not independently ready"):
            source_lock.freeze(inventory,broken,expected=2)
        broken=copy.deepcopy(inventory);broken["pages"].append({"status":"BLOCKED"})
        with self.assertRaises(source_lock.SourceLockError):
            source_lock.freeze(broken,acquired,expected=2)
    def test_official_only_url(self):
        inventory,acquired=self.make_fixtures()
        inventory["resources"][0]["url"]="https://evil.example/evil.zip"
        with self.assertRaisesRegex(source_lock.SourceLockError,"invalid"):
            source_lock.freeze(inventory,acquired,expected=2)

if __name__=="__main__":unittest.main()
