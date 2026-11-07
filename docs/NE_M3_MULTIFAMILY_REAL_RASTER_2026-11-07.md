# NE-M3 — Three more official Natural Earth raster families

**Date:** 2026-11-07. **Branch:** `feat/natural-earth-offline-data`. **PR:** #3 (draft).  
**Scope:** verified official source ZIP -> TIFF/TFW -> PNG v2 + RGBA v1 atlas -> native C++ render, not Resolve host acceptance.

## Verifiable results

One-off standard public Ubuntu GitHub Actions runner:
https://github.com/gabrielbugarelli/cartorig/actions/runs/42344497361

All three publisher ZIPs matched **independently observed SHA256** values from
`data/natural-earth/family_sample_observations_2026-11-07.json`. All passed
publisher ZIP CRC, TIFF/world-file geographic conversion, per-tile SHA256,
full LOD topology, and exact native frame hash parity between PNG v2 and
legacy raw RGBA v1. Temporary binaries were discarded. Only a tiny JSON
evidence artifact was uploaded with one-day retention.

| Official 50m family | RGBA v1 atlas bytes | PNG v2 atlas bytes | Saved | Native median 720p v1 (ms) | Native median 720p v2 (ms) |
|---|---:|---:|---:|---:|---:|
| Gray Earth | 335,806,464 | 21,404,460 | 93.63% | 149.178 | 160.544 |
| PRISMA Shaded Relief | 715,915,264 | 30,031,801 | 95.81% | 153.041 | 169.818 |
| Shaded Relief | 335,806,464 | 24,895,999 | 92.59% | 151.037 | 159.566 |
| **Three-family total** | **1,387,528,192** | **76,332,260** | **94.50%** | — | — |

Each format rendered exactly 230,400 pixels at 640 × 360 with identical
frame hashes. Gray Earth and Shaded Relief each produced 1,281 tiles at
10,800 × 5,400 pixels; PRISMA produced 2,731 tiles at 16,200 × 8,100
pixels. Each contains seven levels of detail.

The three source ZIP files were 10,983,477, 17,991,035 and 11,380,369
bytes respectively. See the per-source SHA256 and exact hashes in
`data/natural-earth/multi_raster_native_observation_2026-11-07.json`.

## Benchmark interpretation

The benchmark is `cartorig_ne_raster_preview --bench`, which measures
the full C++ 1280 × 720 pixel rendering pipeline: source tile reads,
PNG decoding, coordinate projection and color compositing. Five passes per
format produce a median. A fresh per-render 64-tile LRU is used on each
pass. It is **not** an isolated PNG decoder benchmark, guaranteed user
FPS, or a DaVinci Resolve 20 Studio host measurement.

PNG v2 took **5.65% to 10.96%** more time in these three full-frame
samples. Build-time PNG creation is also slower than raw RGBA output,
but no build-time Python or decoder is shipped in the plugin. The
94.50% source-sample storage saving significantly reduces installed disk
space and data-pack transfer requirements. Other datasets, cameras,
hardware and 4K host render performance remain unmeasured.

## Engineering changes

- `tools/ne_raster_preview.cpp` supports optional `--bench` while
  preserving its original pixel-hash proof mode and ABI.
- `tools/natural_earth/probe_multi_raster.py` selects exactly three
  previously source-SHA-pinned raster families and fails closed if a
  source URL/digest, georeference, atlas SHA256, pixel hash or metadata
  disagrees.
- `tests/test_natural_earth_multi_raster.py` adversarially tests
  publisher pin tampering, duplicate/missing sources, malformed benchmark
  output and checkpointed failures.
- `.github/workflows/natural-earth.yml` adds an intentionally tagged
  `[multi-raster-probe]` job, standard free runner, JSON-only artifacts.
- `tools/natural_earth/materialize.py` writes an atomic, full-inventory
  checkpoint after each source. Already verified ZIPs are rehashed and
  reused after a simulated workstation power loss. Interim checkpoints
  cannot represent a complete download.
- `tools/natural_earth/source_lock.py` refuses to freeze a SHA256 lock
  from an interrupted/in-progress acquisition checkpoint.

## Reproduction on standard GitHub runner

The actual three-family probe is deliberately not part of routine CI
because it downloads publisher ZIPs and converts temporary atlases.
A single explicit source commit tagged `[multi-raster-probe]` on this
branch triggers it. Routine Python/C++/Windows CI performs all offline
regression tests without publisher downloads.

For a build workstation with pinned observations and the C++ preview
binary, the equivalent explicit command is:

```powershell
python -m tools.natural_earth.probe_multi_raster --out D:\CartoRigQA\MultiRaster --preview D:\CartoRigBuild\cartorig_ne_raster_preview.exe
```

**No GitHub LFS, paid runner, Codespace, hosted publisher archive, or
long-term Actions artifact is used.**

## Remaining approval gates

- **4 of 16 official raster families** have now been truly compiled and
  rendered (three new samples plus the earlier 50m Manual Shaded Relief).
  The 15/16 family ZIP *integrity* sampling is separate and must not
  be confused with converted/visually accepted maps.
- Persistent workstation download and SHA/CRC proof of **all 51 currently
  available ZIPs** is **not complete**. The full current-source metadata
  baseline remains 52 variants, of which US_MSR_10M.zip is HTTP 404
  (issue #4). It is still required for a certified complete release.
- Actual Resolve 20 Inspector/Overlay alpha, interactive geographic
  region selection and 4K playback acceptance on Windows remain open.
- PR #3 stays **draft** and no full Natural Earth Complete package
  is claimed.
