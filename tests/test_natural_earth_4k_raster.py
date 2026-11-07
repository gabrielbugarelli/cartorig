"""Strict parsing and publisher identity for 720p/1440p/4K renderer proof."""
import json
from pathlib import Path
import unittest

from tools.natural_earth import probe_4k_raster as probe
from tools.natural_earth.probe_raster import expected_official_sample

OBS=Path(__file__).resolve().parents[1]/(
    "data/natural-earth/family_sample_observations_2026-11-07.json")
GOOD=(
    "raster_pixels=230400 frame_hash=13112041101257582482 atlas_levels=7\n"
    "bench_width=1280 bench_height=720 bench_passes=5 "
    "median_frame_ms=29.100 frame_hash=123456 raster_pixels=921600\n"
    "bench_width=2560 bench_height=1440 bench_passes=5 "
    "median_frame_ms=98.100 frame_hash=987654 raster_pixels=3686400\n"
    "bench_width=3840 bench_height=2160 bench_passes=5 "
    "median_frame_ms=221.200 frame_hash=909090 raster_pixels=8294400\n"
)

class RealResolutionQATests(unittest.TestCase):
    def test_reviewed_official_50m_publisher_source_is_pinned(self):
        actual=expected_official_sample(OBS)
        self.assertEqual(actual["observed_sha256"],
            "e38f8b256f64eccae250a1e482761d4a7a585e6602c941e6bdb860e160faf609")
        self.assertEqual(actual["archive_bytes"],17984241)
    def test_valid_native_three_resolution_matrix(self):
        parsed=probe.parse_matrix(GOOD)
        self.assertEqual(parsed["atlas_levels"],7)
        self.assertEqual(parsed["original_640x360_frame_hash"],
                         "13112041101257582482")
        self.assertEqual(set(parsed["resolution_matrix"]),
                         {"1280x720","2560x1440","3840x2160"})
        self.assertEqual(parsed["resolution_matrix"]["3840x2160"]["painted_pixels"],
                         3840*2160)
        self.assertEqual(parsed["resolution_matrix"]["2560x1440"]["median_full_frame_ms"],98.1)
    def test_invalid_dimensions_hash_render_count_and_missing_resolution_rejected(self):
        invalid=[
            GOOD.replace("3840 bench_height=2160","3840 bench_height=2161"),
            GOOD.replace("raster_pixels=8294400","raster_pixels=3"),
            GOOD.replace("frame_hash=909090","frame_hash=0"),
            GOOD.replace("atlas_levels=7","atlas_levels=8"),
            GOOD.replace("13112041101257582482","13112041101257582483"),
            GOOD.replace("bench_passes=5","bench_passes=2"),
            GOOD.replace("median_frame_ms=221.200","median_frame_ms=-1.200"),
            "\n".join(GOOD.splitlines()[:3]),
            GOOD+"\nextra line\n",
        ]
        for number,text in enumerate(invalid):
            with self.subTest(number=number),self.assertRaises(ValueError):
                probe.parse_matrix(text)
    def test_documented_resolution_qa_never_implies_resolve_host(self):
        self.assertEqual(probe.REQUIRED_RESOLUTIONS,
                         ((1280,720),(2560,1440),(3840,2160)))
        self.assertNotIn("Resolve",probe.FIRST.pattern)

if __name__=="__main__":
    unittest.main()
