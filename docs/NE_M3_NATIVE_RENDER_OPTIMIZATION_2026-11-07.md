# NE-M3 — Native raster rendering optimization (source-backed)

**Date:** 2026-11-07  
**Branch/PR:** `feat/natural-earth-offline-data` / #3 (draft)  
**Scope:** native CPU OpenFX core, identical pixels, actual publisher rasters.  
**Not certified:** real DaVinci Resolve Studio 20 playback/4K host performance, full Natural Earth package.

## Three audited reference executions

The same three original Natural Earth 50m ZIP variants were acquired from the
official S3 mirror and checked against the separately observed official SHA256
values on **every run**. They were built as raw RGBA v1 and lossless PNG v2,
rendered natively at 640×360 to compare image hashes, and benchmarked with
five native 1280×720 full-frame passes per format.

| Stage | Publisher-backed Actions run |
| --- | --- |
| Baseline: per-pixel projection and LRU | [42344497361](https://github.com/gabrielbugarelli/cartorig/actions/runs/42344497361) |
| Axis-aligned Mercator projection precomputation | [42345094882](https://github.com/gabrielbugarelli/cartorig/actions/runs/42345094882) |
| Axis-aligned projection plus row-local tile reuse | [42345342349](https://github.com/gabrielbugarelli/cartorig/actions/runs/42345342349) |

## Measured full-render median: PNG v2 (milliseconds)

| Official 50m family | Baseline | Projection optimization | Row-local tile reuse | End-to-end improvement |
| --- | ---: | ---: | ---: | ---: |
| Gray Earth | 160.544 | 84.580 | 74.386 | 53.67% |
| PRISMA Shaded Relief | 169.818 | 98.256 | 87.977 | 48.19% |
| Shaded Relief | 159.566 | 83.445 | 74.337 | 53.41% |

## Raw RGBA v1 control (milliseconds)

| Official 50m family | Baseline | Projection optimization | Row-local tile reuse | End-to-end improvement |
| --- | ---: | ---: | ---: | ---: |
| Gray Earth | 149.178 | 71.525 | 62.459 | 58.13% |
| PRISMA Shaded Relief | 153.041 | 74.163 | 66.205 | 56.74% |
| Shaded Relief | 151.037 | 70.295 | 62.467 | 58.64% |

These timings include disk tile reads, decompression, geographic projection
and alpha compositing. They do **not** isolate the decoder and should not be
interpreted as exact user FPS: they are medians from **different GitHub Actions
standard-runner executions**. The very same official source SHA256 and
unrotated camera/LOD settings were reused and checked.

**The native output hashes remained exactly identical across all three
stages**, including for both PNG v2 and RGBA v1:
- Gray Earth: `13024482577733760989`
- PRISMA: `11708255958712787630`
- Shaded Relief: `6987416738967865316`

Lossless PNG v2 also retains the verified **94.50% combined reduction in
on-disk atlas storage** for these three real publishers.

Machine-readable proof:
`data/natural-earth/native_raster_optimization_observation_2026-11-07.json`.

## Implementation

1. **Separable projection for zero-bearing cameras:** for an unrotated
   Mercator camera, longitude depends only on screen X and latitude only
   on screen Y. We compute all source X indices and all source Y indices
   once per OFX render window. Projection cost changes from
   O(width × height) to O(width + height). Geographic calculations still
   use the original `unproject()` function to preserve wrapping and
   floating-point behavior.
2. **Row-local decoded tile reuse:** adjacent output pixels with the
   same projected Y and same source tile X reuse the existing tile buffer
   directly, instead of repeatedly searching the unordered map and
   updating LRU history. The row-local reference is never retained across
   a subsequent call that could evict the tile.
3. **Fallback untouched for rotation:** nonzero camera bearing still uses
   the general per-pixel projection. The native `tests/test_ne_raster_projection.cpp`
   compares both paths with a fully independent per-pixel reference,
   checking antimeridian wrapping, partial host render windows, alpha
   blending and nonzero bearings.
4. **Bounded memory unchanged:** decoded RGBA tile cache remains at
   64 tiles / at most ~16 MiB per render request. No new Python, OpenCV,
   web requests or OS-specific services are required at Resolve runtime.

### Additional native 1440p/4K real-source acceptance

A separate one-off publisher-backed [real 720p/1440p/4K native matrix run](https://github.com/gabrielbugarelli/cartorig/actions/runs/42346691749) confirmed identical output frame hashes from the same source in PNG v2 and RGBA v1 at all three resolutions. The 2560x1440 medians were PNG 288.704ms and RGBA 256.051ms; 3840x2160 were PNG 728.366ms and RGBA 542.239ms (5 passes on an Ubuntu CI runner). This is **actual native C++ raster computation**, not the licensed Resolve Studio 20 host. Evidence: [native_real_4k_observation](../data/natural-earth/native_real_4k_observation_2026-11-07.json). No claim of 30/60 FPS on the target machine.

## Release/QA limits

The observed optimized 720p CPU frame time **still ranges from 74.337
to 87.977 ms for PNG v2** on this standard runner, so the benchmarks
do not establish real-time 30/60 FPS performance, nor extrapolate reliably
to Windows GPUs or 1440p/4K. Host frame caches and rendering behavior can
change real playback experience significantly.

The map editor's actual Windows Resolve 20 real host, video Overlay alpha,
interactive Inspector, keyframes and full 4K/Deliver acceptance still need
independent testing.

Only **four distinct official raster ZIP variants** have been converted
and natively rendered so far. The persistent 51/52 full-archive acquisition
and original `US_MSR_10M.zip` HTTP 404 are unchanged. No 52-source
complete data-pack certification is claimed.

All publisher ZIP and TIFF inputs were disposed of on the temporary
standard public runner. Actions stores JSON evidence for one day; none
of the source rasters is placed in the repository, LFS, Packages or a
paid runner.
