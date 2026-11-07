# CartoRig Natural Earth — PNG v2 raster tiles

**Status:** Implemented and verified on one real official 50m raster. Not a complete Natural Earth data-pack certification.
**PR:** https://github.com/gabrielbugarelli/cartorig/pull/3

## Publisher-backed evidence

Official MSR_50M.zip: 17,984,241 bytes, SHA256
e38f8b256f64eccae250a1e482761d4a7a585e6602c941e6bdb860e160faf609.

- Raster dimensions: 10,800 x 5,400 pixels.
- Atlas: seven levels and 1,281 tiles, each 256 x 256.
- Raw RGBA v1: **335,806,464 bytes**.
- Lossless PNG v2: **33,583,241 bytes**.
- Real observed atlas storage reduction: **90.0%**.
- Both raster formats rendered **230,400 native pixels** with identical
  native frame hash **13112041101257582482**.
- The renderer independently verified the same atlas level count, source
  archive hash, ZIP CRC, TIFF/TFW georeference and native output.

Proofs:
- https://github.com/gabrielbugarelli/cartorig/actions/runs/42342818040 (legacy v1)
- https://github.com/gabrielbugarelli/cartorig/actions/runs/42343229449 (PNG v2)

Machine-readable evidence: data/natural-earth/raster_png_v2_observation_2026-11-07.json.

## Binary contract

Legacy tiles:
- index.json format: cartorig-rgba-tiles-v1
- files: tiles/Z/X_Y.rgba
- exact on-disk payload: 256 x 256 x 4 RGBA bytes.

PNG v2:
- index.json format: cartorig-png-tiles-v2
- files: tiles/Z/X_Y.png
- standard lossless RGBA PNG with 256 x 256 output pixels.

Both share EPSG:4326 extent, original dimensions, source provenance and LOD
metadata. The native C++ renderer reads both versions. PNG compressed input
is limited to 1 MiB per tile; decoded output must be exactly 256 x 256 RGBA.
All atlas tiles are SHA256 reverified on producer restart. A legacy raw tile
cannot be reused as a verified PNG v2 tile.

The renderer retains the existing per-render 64-tile (~16 MiB decoded)
LRU. Real 4K playback latency needs validation on DaVinci Resolve Studio 20.

## Builder and release behavior

The production producer and experimental local-QA producer use PNG v2.
The low-level offline raster compiler supports an explicit tile format option
(rgba for legacy or png for lossless v2). The full publisher 52-source gate,
content SHA256 lock and independent package verifier remain strict.

The installed OpenFX runtime has NO Python, ImageMagick, rasterio, external
GDAL service, web access, CDN, paid API, cloud account or telemetry.

## Native decoder legal and technical provenance

The self-contained C++ decoder LodePNG is vendored from:
https://github.com/lvandeve/lodepng
Upstream SHA: 7b2893e35891c0c85bee5595caafaf3c2044b409.
Original license: zlib-style, retained in third_party/lodepng/LICENSE,
with original notices retained in all vendored source files.

Decoder library code is not geographic input; all map sources remain
Natural Earth.

## Explicit limitations

This is a **single real 50m source measurement**, not an estimate of the
entire 51/52 corpus. The official US_MSR_10M.zip remains unavailable
(issue #4), and no 51-source persistent workstation acquisition or full
offline Resolve Edit/Overlay/4K host certification is claimed.
