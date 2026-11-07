"""NE-SOURCE-02: reviewed upstream gap cannot certify or block other rasters."""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools.natural_earth import (
    acquire_available, known_unavailable, materialize, source_lock, verify_pack
)

ISSUE="https://github.com/gabrielbugarelli/cartorig/issues/4"


def fixtures():
    rows=[]
    for n in range(52):
        scale="10m" if n<38 else "50m"
        rows.append({
            "resource_id":f"ne-{scale}-raster-fake-{n:02}",
            "url":f"https://naturalearth.s3.amazonaws.com/{scale}_raster/FAKE_{n:02}.zip",
            "scale":scale,"theme":"raster","archive_format":"zip",
            "source_page":f"https://www.naturalearthdata.com/downloads/{scale}-raster-data/",
            "theme_version":"test",
        })
    inventory={"schema_version":1,"pages":[{"status":"INDEXED","url":"official"}],
               "resources":rows}
    discovery=source_lock.discovery_fingerprint(inventory)
    exception={
        "schema_version":1,
        "format":"cartorig-ne-publisher-exceptions-v1",
        "discovery_sha256":discovery["source_rows_sha256"],
        "exceptions":[{
            **{k:rows[0][k] for k in ("resource_id","scale","url","source_page")},
            "issue":ISSUE,"observed_status":"PUBLISHER_HTTP_404",
            "observed_utc":"2026-11-07",
        }],
    }
    return inventory,discovery,exception


class KnownUnavailableTests(unittest.TestCase):
    def setUp(self):
        self.inventory,self.discovery,self.exception=fixtures()
    def test_single_reviewed_gap_matches_all_52_original_sources(self):
        known=known_unavailable.validate(
            self.inventory,self.discovery,self.exception)
        self.assertEqual(len(known),1)
        self.assertEqual(next(iter(known)),self.inventory["resources"][0]["resource_id"])
    def test_changed_url_and_issue_and_fingerprint_rejected(self):
        for key,value in [
                ("issue","https://example.com/unreviewed"),
                ("url","https://evil.example/bad.zip"),
                ("scale","wrong"),
                ("observed_status","VERIFIED")]:
            bad=copy.deepcopy(self.exception)
            bad["exceptions"][0][key]=value
            with self.assertRaises(known_unavailable.SourceExceptionError):
                known_unavailable.validate(self.inventory,self.discovery,bad)
        bad=copy.deepcopy(self.exception)
        bad["discovery_sha256"]="0"*64
        with self.assertRaises(known_unavailable.SourceExceptionError):
            known_unavailable.validate(self.inventory,self.discovery,bad)
        bad=copy.deepcopy(self.inventory)
        bad["resources"][0]["url"]="https://naturalearth.s3.amazonaws.com/10m_raster/OTHER.zip"
        with self.assertRaises(known_unavailable.SourceExceptionError):
            known_unavailable.validate(bad,self.discovery,self.exception)
    def test_no_silent_additions_or_secondary_gap(self):
        for rows in ([],[self.exception["exceptions"][0]]*2):
            bad=copy.deepcopy(self.exception)
            bad["exceptions"]=rows
            with self.assertRaises(known_unavailable.SourceExceptionError):
                known_unavailable.validate(self.inventory,self.discovery,bad)


class AcquisitionTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root=Path(temp.name)
        self.workspace=self.root/"workspace"
        self.inventory,self.discovery,self.exception=fixtures()
        self.exceptions=known_unavailable.validate(
            self.inventory,self.discovery,self.exception)
        payload=self.root/"source.zip"
        with zipfile.ZipFile(payload,"w") as z:
            z.writestr("REAL.tfw","1\n0\n0\n-1\n0\n0\n")
        self.data=payload.read_bytes()
        self.calls=[]
    def fake_fetch(self,url,path):
        self.calls.append(url)
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(self.data)
        return len(self.data),hashlib.sha256(self.data).hexdigest()
    def acquire(self,*,max_downloads=12,allow_network=True,skip=True):
        with patch.object(acquire_available.release_pipeline,
                          "_load_verified_inventory",return_value=self.inventory),patch.object(
                          acquire_available.known_unavailable,"read_verified",
                          return_value=self.exceptions),patch.object(
                          materialize,"download_and_hash",side_effect=self.fake_fetch):
            return acquire_available.acquire(
                workspace=self.workspace,project_root=self.root,
                max_downloads=max_downloads,allow_network=allow_network,
                skip_reviewed_unavailable=skip)
    def test_first_batch_keeps_original_source_count_and_pending(self):
        result=self.acquire(max_downloads=12)
        self.assertEqual(result["verified_archives"],12)
        self.assertEqual(result["known_unavailable"],1)
        self.assertEqual(result["pending_or_blocked"],39)
        self.assertEqual(result["status"],"PARTIAL_ACQUISITION")
        self.assertFalse(result["release_certified"])
        manifest=json.loads((self.workspace/"downloads/source-archives.json").read_text())
        self.assertEqual(len(manifest["resources"]),52)
        self.assertFalse(manifest["summary"]["complete"])
        self.assertEqual(sum(r["status"]=="KNOWN_UNAVAILABLE" for r in manifest["resources"]),1)
        self.assertEqual(len(self.calls),12)
    def test_all_other_51_are_reacquired_and_sha_verified_no_network_runtime(self):
        a=self.acquire(max_downloads=12)
        self.assertEqual(a["verified_archives"],12)
        b=self.acquire(max_downloads=12)
        self.assertEqual(b["verified_archives"],24)
        complete=self.acquire(max_downloads=100)
        self.assertEqual(complete["verified_archives"],51)
        self.assertEqual(complete["pending_or_blocked"],0)
        self.assertEqual(complete["known_unavailable"],1)
        self.assertEqual(complete["status"],"AVAILABLE_SOURCES_VERIFIED_NOT_CERTIFIED")
        self.assertFalse(complete["release_certified"])
        self.assertEqual(len(self.calls),51)
        offline=self.acquire(allow_network=False)
        self.assertEqual(offline["status"],complete["status"])
        self.assertEqual(len(self.calls),51)
        manifest=json.loads((self.workspace/"downloads/source-archives.json").read_text())
        proof=verify_pack.verify_manifest(manifest,self.workspace/"downloads")
        self.assertFalse(proof["complete"])  # missing source is NOT a release
        self.assertEqual(proof["verified"],51)
    def test_power_loss_preserves_full_52_row_checkpoint_and_resumes(self):
        successful=[]
        def interrupted(url,path):
            if len(successful)==2:
                raise KeyboardInterrupt("simulated workstation power loss")
            successful.append(url)
            return self.fake_fetch(url,path)
        with patch.object(acquire_available.release_pipeline,
                          "_load_verified_inventory",return_value=self.inventory),patch.object(
                          acquire_available.known_unavailable,"read_verified",
                          return_value=self.exceptions),patch.object(
                          materialize,"download_and_hash",side_effect=interrupted):
            with self.assertRaisesRegex(KeyboardInterrupt,"power loss"):
                acquire_available.acquire(
                    workspace=self.workspace,project_root=self.root,
                    max_downloads=12,allow_network=True,
                    skip_reviewed_unavailable=True)
        checkpoint_path=self.workspace/"downloads/source-archives.json"
        self.assertTrue(checkpoint_path.is_file())
        saved=json.loads(checkpoint_path.read_text())
        self.assertTrue(saved["checkpoint_in_progress"])
        self.assertFalse(saved["summary"]["complete"])
        self.assertEqual(len(saved["resources"]),52)
        self.assertEqual(sum(r["status"]=="VERIFIED" for r in saved["resources"]),2)
        self.assertFalse((self.workspace/"acquisition-status.json").exists())
        finished=self.acquire(max_downloads=100)
        self.assertEqual(finished["verified_archives"],51)
        self.assertEqual(finished["known_unavailable"],1)
        self.assertEqual(len(self.calls),51,
                         "previous two publisher files must be rehashed, not re-downloaded")
        self.assertFalse(json.loads(checkpoint_path.read_text())["checkpoint_in_progress"])

    def test_source_recovers_later_then_no_exception_remains(self):
        self.acquire(max_downloads=100)
        result=self.acquire(max_downloads=100,skip=False)
        self.assertEqual(result["verified_archives"],52)
        self.assertEqual(result["known_unavailable"],0)
        self.assertEqual(result["status"],"ALL_52_ARCHIVES_VERIFIED_CONTENT_LOCK_PENDING")
        self.assertFalse(result["release_certified"])
        self.assertEqual(len(self.calls),52)
    def test_tampered_sha_is_not_reused_or_falsely_marked_verified(self):
        self.acquire(max_downloads=100)
        first=next(iter(self.workspace.glob("downloads/archives/*")),None)
        self.assertIsNotNone(first)
        first.write_bytes(b"tampered")
        result=self.acquire(max_downloads=0,allow_network=False)
        self.assertEqual(result["verified_archives"],50)
        self.assertEqual(result["known_unavailable"],1)
        self.assertEqual(result["status"],"PARTIAL_ACQUISITION")
        self.assertFalse(result["release_certified"])
    def test_no_network_without_explicit_opt_in(self):
        result=self.acquire(max_downloads=100,allow_network=False)
        self.assertEqual(result["verified_archives"],0)
        self.assertEqual(result["known_unavailable"],1)
        self.assertEqual(len(self.calls),0)
    def test_unknown_exceptions_are_not_allowed(self):
        with self.assertRaisesRegex(ValueError,"does not exist"):
            materialize.materialize(self.inventory,self.root/"invalid",
                                    known_unavailable={"unknown":{"issue":ISSUE}})


if __name__=="__main__":
    unittest.main()
