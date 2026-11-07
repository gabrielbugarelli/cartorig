"""Persistent Windows-source build orchestration: no false Complete/Resolve certification."""
from __future__ import annotations
import json
from pathlib import Path
import tempfile
import unittest

from tools.natural_earth import workstation_cycle as cycle

MATRIX=(
    "raster_pixels=230400 frame_hash=991977 atlas_levels=7\n"
    "bench_width=1280 bench_height=720 bench_passes=5 "
    "median_frame_ms=62.451 frame_hash=12001 raster_pixels=921600\n"
    "bench_width=2560 bench_height=1440 bench_passes=5 "
    "median_frame_ms=245.100 frame_hash=12002 raster_pixels=3686400\n"
    "bench_width=3840 bench_height=2160 bench_passes=5 "
    "median_frame_ms=600.888 frame_hash=12003 raster_pixels=8294400\n"
)

def acquired(n):
    return {
        "status":"AVAILABLE_SOURCES_VERIFIED_NOT_CERTIFIED" if n==51 else "PARTIAL_ACQUISITION",
        "source_count":52,"verified_archives":n,"known_unavailable":1,
        "pending_or_blocked":51-n,"release_certified":False,
    }

def completed_build(workspace,output,**kwargs):
    output.mkdir(parents=True,exist_ok=True)
    return {"status":"EXPERIMENTAL_INCOMPLETE",
            "release_certified":False,"verified_available_rasters":51,
            "known_unavailable":1,"converted_raster_sources":51}

def verified(*args,**kwargs):
    return {"pack_id":"a"*64,"complete":False,
            "raster_sources":51,"vector_sources":215}

class CycleTests(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)
        self.workspace=self.path/"workspace"
        self.output=self.path/"pack"
        self.exe=self.path/"preview.exe"
        self.exe.write_bytes(b"mock native preview")
    def test_produces_persistent_reproducible_51_archive_report_but_never_resolve_certified(self):
        seq=iter([12,24,36,48,51])
        calls=[]
        def acquire(**kwargs):
            calls.append(kwargs)
            return acquired(next(seq))
        native=lambda *a:{"status":"NATIVE_1440P_4K_PASSED","assets":[{"asset_id":"real"}]}
        result=cycle.run(
            workspace=self.workspace,output=self.output,
            allow_network=True,max_downloads=12,max_batches=10,
            min_free_gib=0,preview=self.exe,
            acquire_fn=acquire,build_fn=completed_build,
            verify_fn=verified,native_fn=native)
        self.assertEqual(len(calls),5)
        self.assertTrue(all(c["allow_network"] for c in calls))
        self.assertTrue(all(c["skip_reviewed_unavailable"] for c in calls))
        self.assertFalse(result["resolve_20_host_test"])
        self.assertFalse(result["release_certified"])
        self.assertEqual(result["status"],
            "EXPERIMENTAL_PACK_AND_NATIVE_4K_VERIFIED_HOST_QA_PENDING")
        recorded=json.loads((self.workspace/"workstation-qa-report.json").read_text())
        self.assertEqual(recorded["pack"]["raster_sources"],51)
        self.assertEqual(recorded["pack"]["vector_sources"],215)
        self.assertEqual(len(recorded["acquisition_batches"]),5)
    def test_offline_or_repeated_failed_source_does_not_falsely_build_a_pack(self):
        called=[]
        def raise_build(**kwargs):
            called.append(kwargs)
            raise AssertionError("must not build incomplete publisher pack")
        with self.assertRaisesRegex(cycle.QAIncomplete,"offline source acquisition"):
            cycle.run(
                workspace=self.workspace,output=self.output,
                allow_network=False,min_free_gib=0,max_batches=10,
                acquire_fn=lambda **_:acquired(1),
                build_fn=raise_build,verify_fn=verified)
        self.assertFalse(called)
        self.assertEqual(json.loads((self.workspace/"workstation-qa-report.json")
                        .read_text())["status"],"INCOMPLETE")
        with self.assertRaisesRegex(cycle.QAIncomplete,"no progress"):
            cycle.run(
                workspace=self.workspace,output=self.output,
                allow_network=True,min_free_gib=0,max_batches=10,
                acquire_fn=lambda **_:acquired(1),
                build_fn=raise_build,verify_fn=verified)
        self.assertFalse(called)
    def test_wrong_vector_coverage_or_fake_complete_pack_fails(self):
        with self.assertRaisesRegex(cycle.QAIncomplete,"51/215"):
            cycle.run(
                workspace=self.workspace,output=self.output,
                allow_network=True,min_free_gib=0,
                acquire_fn=lambda **_:acquired(51),
                build_fn=completed_build,
                verify_fn=lambda *args,**kw:
                  dict(verified(),vector_sources=214))
        bad=dict(verified(),complete=True)
        with self.assertRaisesRegex(cycle.QAIncomplete,"51/215"):
            cycle.run(
                workspace=self.workspace,output=self.output,
                allow_network=True,min_free_gib=0,
                acquire_fn=lambda **_:acquired(51),
                build_fn=completed_build,
                verify_fn=lambda *args,**kw:bad)
    def test_resume_after_pack_exists_never_redownloads(self):
        self.output.mkdir()
        calls=[]
        result=cycle.run(
            workspace=self.workspace,output=self.output,
            allow_network=False,min_free_gib=0,
            acquire_fn=lambda **kw:calls.append(kw),
            build_fn=lambda **_:self.fail("should reuse verified output pack"),
            verify_fn=verified)
        self.assertEqual(result["status"],
                         "EXPERIMENTAL_PACK_VERIFIED_HOST_QA_PENDING")
        self.assertFalse(calls)
        self.assertFalse(result["resolve_20_host_test"])
    def test_pixel_proof_parser_requires_three_actual_resolutions(self):
        p=cycle.parse_native_matrix(MATRIX)
        self.assertEqual(set(p["resolutions"]),
                         {"1280x720","2560x1440","3840x2160"})
        self.assertEqual(p["resolutions"]["3840x2160"]["rendered_pixels"],8294400)
        bad=[
            MATRIX.replace("bench_width=3840","bench_width=7680"),
            MATRIX.replace("raster_pixels=8294400","raster_pixels=8294401"),
            MATRIX.replace("median_frame_ms=600.888","median_frame_ms=-3.888"),
            MATRIX.replace("frame_hash=12003","frame_hash=0"),
            "\n".join(MATRIX.splitlines()[:-1]),
        ]
        for row in bad:
            with self.subTest(value=row[-80:]),self.assertRaises(cycle.QAIncomplete):
                cycle.parse_native_matrix(row)
    def test_both_storage_volumes_require_capacity_before_network(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        made=[]
        def fake_usage(path):
            made.append(str(path))
            return SimpleNamespace(free=20*1024**3)
        with patch.object(cycle.shutil,"disk_usage",side_effect=fake_usage):
            with self.assertRaisesRegex(cycle.QAIncomplete,"50 GiB threshold"):
                cycle.run(
                    workspace=self.workspace,output=self.output,
                    allow_network=True,max_downloads=12,
                    acquire_fn=lambda **_:self.fail("must not acquire without space"),
                    build_fn=lambda **_:self.fail("must not build without space"),
                    verify_fn=verified)
        self.assertTrue(made)

    def test_nested_workspaces_and_invalid_limits_fail_without_writes(self):
        with self.assertRaisesRegex(ValueError,"separate"):
            cycle.run(workspace=self.workspace,output=self.workspace/"pack")
        with self.assertRaisesRegex(ValueError,"parameters"):
            cycle.run(workspace=self.workspace,output=self.output,max_downloads=0)

if __name__=="__main__":
    unittest.main()
