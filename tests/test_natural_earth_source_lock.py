"""Reviewed locks prohibit a silently modified publisher source set."""
import copy
import json
from pathlib import Path
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
    def test_reproducible_publisher_discovery_fingerprint(self):
        inventory,acquired=self.make_fixtures()
        frozen=source_lock.discovery_fingerprint(inventory,expected=2)
        self.assertEqual(frozen["baseline_variants"],2)
        source_lock.verify_discovery(frozen,inventory,expected=2)
        changed=copy.deepcopy(inventory)
        changed["resources"][0]["theme_version"]="3.3.0"
        with self.assertRaisesRegex(source_lock.SourceLockError,"source-discovery fingerprint"):
            source_lock.verify_discovery(frozen,changed,expected=2)
        changed=copy.deepcopy(inventory)
        changed["resources"].reverse()
        source_lock.verify_discovery(frozen,changed,expected=2)

    def test_committed_52_source_fingerprint_schema(self):
        lock_path=(Path(__file__).resolve().parents[1] / "data/natural-earth/"
                   "raster_discovery_v2026-11-07.lock.json")
        lock=json.loads(lock_path.read_text(encoding="utf-8"))
        self.assertEqual(lock["baseline_variants"],52)
        self.assertEqual(lock["variants_by_scale"],{"10m":38,"50m":14})
        self.assertRegex(lock["source_rows_sha256"],r"^[0-9a-f]{64}$")

    def test_real_51_publisher_head_source_size_observation_is_not_a_sha_lock(self):
        root=Path(__file__).resolve().parents[1]/"data/natural-earth"
        official=json.loads((root/"raster_discovery_v2026-11-07.lock.json")
                            .read_text(encoding="utf-8"))
        reported=json.loads((root/"raster_51_head_size_observation_2026-11-07.json")
                            .read_text(encoding="utf-8"))
        self.assertEqual(reported["discovery_rows_sha256"],
                         official["source_rows_sha256"])
        self.assertEqual(reported["head_size_verified_variants"],51)
        self.assertEqual(reported["aggregate_advertised_zip_bytes"],6687019474)
        self.assertEqual(reported["missing_publisher_archives"],1)
        self.assertEqual(reported["content_sha256_verified_variants_from_this_head_probe"],0)
        self.assertGreaterEqual(reported["project_workstation_recommended_free_gib"],40)

    def test_snapshot_and_verification(self):
        inventory,acquired=self.make_fixtures()
        locked=source_lock.freeze(inventory,acquired,expected=2)
        self.assertEqual(locked["baseline_variants"],2)
        self.assertEqual(len(locked["resources"]),2)
        source_lock.verify(locked,inventory,acquired,expected=2)
    def test_interrupted_download_manifest_cannot_be_frozen_as_released_source_lock(self):
        inventory,acquired=self.make_fixtures()
        acquired["checkpoint_in_progress"]=True
        with self.assertRaisesRegex(source_lock.SourceLockError,
                                    "interrupted acquisition checkpoint"):
            source_lock.freeze(inventory,acquired,expected=2)
        acquired["checkpoint_in_progress"]=False
        self.assertEqual(source_lock.freeze(
            inventory,acquired,expected=2)["baseline_variants"],2)

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
