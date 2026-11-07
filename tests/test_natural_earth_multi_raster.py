"""NE-M3: all source pins and native benchmark outputs must be independently proved."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.natural_earth import probe_multi_raster as multi

OBS=Path(__file__).resolve().parents[1]/"data/natural-earth/family_sample_observations_2026-11-07.json"

class MultiRasterTests(unittest.TestCase):
    def setUp(self):
        self.observations=json.loads(OBS.read_text(encoding="utf-8"))
    def test_three_observations_pinned_to_official_source_zip_and_digest(self):
        selected=multi.select_sources(self.observations)
        self.assertEqual(len(selected),3)
        self.assertEqual({s["family"] for s in selected},set(multi.SAMPLE_FAMILIES))
        self.assertTrue(all(s["url"].startswith(
            "https://naturalearth.s3.amazonaws.com/50m_raster/") for s in selected))
        self.assertTrue(all(len(s["sha256"])==64 for s in selected))
    def test_changed_publisher_hash_or_url_rejected_before_download(self):
        for field,value in [
            ("archive_bytes",5),("observed_sha256","0"*64),
            ("source_url","https://attacker.example/gray.zip"),
            ("validation","UNVERIFIED")]:
            altered=copy.deepcopy(self.observations)
            row=next(r for r in altered["observations"]
                     if r["family"]==multi.SAMPLE_FAMILIES[0])
            row[field]=value
            with self.subTest(field=field),self.assertRaisesRegex(
                    ValueError,"sample metadata"):
                multi.select_sources(altered)
        missing=copy.deepcopy(self.observations)
        missing["observations"]=[
            row for row in missing["observations"]
            if row["family"]!=multi.SAMPLE_FAMILIES[0]]
        with self.assertRaisesRegex(ValueError,"not all selected"):
            multi.select_sources(missing)
    def test_duplicate_rejected(self):
        altered=copy.deepcopy(self.observations)
        altered["observations"].append(copy.deepcopy(
            next(r for r in altered["observations"] if
                 r["family"]==multi.SAMPLE_FAMILIES[1])))
        with self.assertRaisesRegex(ValueError,"duplicate observed"):
            multi.select_sources(altered)
    def test_native_benchmark_requires_strict_two_line_measurement(self):
        class Result:
            returncode=0
            stdout=("raster_pixels=230400 frame_hash=87199 atlas_levels=7\n"
                    "bench_width=1280 bench_height=720 bench_passes=5 median_frame_ms=26.370\n")
            stderr=""
        with patch.object(multi.subprocess,"run",return_value=Result()) as run:
            proof=multi.native_proof(Path("demo"),Path("root"),"asset")
        self.assertEqual(proof["median_720p_full_frame_ms"],26.37)
        self.assertEqual(proof["native_frame_hash"],"87199")
        self.assertEqual(run.call_args.args[0][-1],"--bench")
        for bad in [
            Result.stdout.replace("230400","0"),
            Result.stdout.replace("median_frame_ms=26.370","median_frame_ms=-10.000"),
            "render_ok=1",
        ]:
            with patch.object(multi.subprocess,"run",return_value=type(
                    "Bad",(),{"returncode":0,"stdout":bad,"stderr":""})()):
                with self.assertRaises(ValueError):
                    multi.native_proof(Path("demo"),Path("root"),"asset")
    def test_checkpoint_retains_failures_and_does_not_claim_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with patch.object(multi,"convert_and_compare",
                              side_effect=RuntimeError("publisher temporarily down")):
                summary=multi.run(
                    out=root,preview=Path("dummy"),
                    observations=OBS,
                    selected_families=(multi.SAMPLE_FAMILIES[0],))
            self.assertEqual(summary["verified_real_families"],0)
            self.assertFalse(summary["complete"])
            self.assertFalse(summary["distribution_ready"])
            self.assertFalse(summary["resolve_host_test"])
            stored=json.loads((root/"multi-raster-proof.json").read_text())
            self.assertEqual(stored["families"][0]["status"],"FAILED_REAL_SOURCE_QA")
            self.assertEqual(len(stored["families"]),1)
    def test_persisted_real_publisher_metrics_match_independent_source_hashes(self):
        proof=Path(__file__).resolve().parents[1]/(
            "data/natural-earth/multi_raster_native_observation_2026-11-07.json")
        row=json.loads(proof.read_text(encoding="utf-8"))
        self.assertFalse(row["full_source_lock_certified"])
        self.assertFalse(row["resolve_host_test"])
        originals={r["archive"]:r for r in self.observations["observations"]}
        self.assertEqual(row["summary"]["verified_new_official_families"],3)
        self.assertEqual(len(row["families"]),3)
        self.assertEqual({r["family"] for r in row["families"]},set(multi.SAMPLE_FAMILIES))
        raw=png=0
        for sample in row["families"]:
            with self.subTest(family=sample["family"]):
                official=originals[sample["archive"]]
                self.assertEqual(sample["sha256"],official["observed_sha256"])
                self.assertEqual(sample["source_archive_bytes"],official["archive_bytes"])
                self.assertEqual(sample["rgba_v1_bytes"],
                                 sample["tiles"]*256*256*4)
                self.assertGreater(sample["rgba_v1_bytes"],sample["png_v2_bytes"])
                self.assertEqual(sample["storage_reduction_pct"],round(
                    100*(1-sample["png_v2_bytes"]/sample["rgba_v1_bytes"]),2))
                self.assertGreater(sample["render_720p_v1_median_ms"],0)
                self.assertGreater(sample["render_720p_v2_median_ms"],0)
                self.assertEqual(sample["native_720p_v2_time_overhead_pct"],round(
                    100*(sample["render_720p_v2_median_ms"]/
                         sample["render_720p_v1_median_ms"]-1),2))
                self.assertTrue(sample["native_640x360_frame_hash"].isdigit())
                raw+=sample["rgba_v1_bytes"]
                png+=sample["png_v2_bytes"]
        self.assertEqual(row["summary"]["sum_rgba_v1_bytes"],raw)
        self.assertEqual(row["summary"]["sum_png_v2_bytes"],png)
        self.assertEqual(row["summary"]["storage_reduction_pct"],round(
            100*(1-png/raw),2))

    def test_render_optimization_proof_matches_prior_real_publisher_frame_hashes(self):
        root=Path(__file__).resolve().parents[1]/"data/natural-earth"
        previous=json.loads((root/"multi_raster_native_observation_2026-11-07.json")
                            .read_text(encoding="utf-8"))
        updated=json.loads((root/"native_raster_optimization_observation_2026-11-07.json")
                           .read_text(encoding="utf-8"))
        self.assertTrue(updated["native_frame_hash_equal_to_previous_versions"])
        self.assertTrue(updated["strict_52_source_release_gate_unchanged"])
        self.assertFalse(updated["resolve_20_host_or_4k_test"])
        self.assertEqual(updated["official_variant_count_verified_in_this_benchmark"],3)
        old={r["family"]:r for r in previous["families"]}
        self.assertEqual(len(updated["families"]),len(old))
        for row in updated["families"]:
            with self.subTest(family=row["family"]):
                historic=old[row["family"]]
                self.assertEqual(row["source_archive_sha256"],historic["sha256"])
                self.assertEqual(row["native_640x360_frame_hash_identical_all_stages"],
                                 historic["native_640x360_frame_hash"])
                stages=row["benchmarks_by_stage"]
                self.assertEqual(len(stages),3)
                self.assertEqual(stages[0]["rgba_v1_720p_median_ms"],
                                 historic["render_720p_v1_median_ms"])
                self.assertEqual(stages[0]["png_v2_720p_median_ms"],
                                 historic["render_720p_v2_median_ms"])
                for stage in stages:
                    self.assertGreater(stage["rgba_v1_720p_median_ms"],0)
                    self.assertGreater(stage["png_v2_720p_median_ms"],0)
                self.assertEqual(row["png_v2_overall_render_time_reduction_pct"],
                                 round(100*(1-stages[2]["png_v2_720p_median_ms"]/
                                              stages[0]["png_v2_720p_median_ms"]),2))
                self.assertEqual(row["rgba_v1_overall_render_time_reduction_pct"],
                                 round(100*(1-stages[2]["rgba_v1_720p_median_ms"]/
                                              stages[0]["rgba_v1_720p_median_ms"]),2))

    def test_bounded_selection_cannot_request_undiscovered_families(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError,"unreviewed probe"):
                multi.run(out=Path(tmp),preview=Path("dummy"),
                          observations=OBS,selected_families=("10m-missing",))

if __name__=="__main__":
    unittest.main()
