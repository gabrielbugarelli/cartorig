# NE-FETCH-01 — Official raster family sample acquisition, 2026-11-07

**Project:** https://github.com/gabrielbugarelli/cartorig  
**PR:** https://github.com/gabrielbugarelli/cartorig/pull/3  
**Policy:** use only free standard runners on this public GitHub repository, no LFS/Packages/larger runners, upload small JSON reports with one-day retention.  
**Outcome:** **15 of 16 families sampled from real official ZIP files; one upstream source URL remains HTTP 404.** Do NOT classify the complete Natural Earth pack as certified.

## Evidence

| Verification | Result | Evidence |
| --- | --- | --- |
| Public official source pages | 24 indexed, 0 blocked | [Publisher source audit](https://github.com/gabrielbugarelli/cartorig/actions/runs/42336954400) |
| Discovered raster ZIP URLs | 52; 38 at 10m, 14 at 50m | `data/natural-earth/raster_discovery_v2026-11-07.lock.json` |
| Publisher HEAD verification | 51/52 HTTP HEAD responses verified | [52-source preflight](https://github.com/gabrielbugarelli/cartorig/actions/runs/42338726085) |
| Genuine ZIP contents and source image/world file | 14/16 source families | [Full real-family probe](https://github.com/gabrielbugarelli/cartorig/actions/runs/42338899344) |
| PRISMA 50m real ZIP and TIFF/TFW recovered | 1 additional family, SHA-verified | [Scoped PRISMA probe](https://github.com/gabrielbugarelli/cartorig/actions/runs/42339183252) |
| Sample bytes actually acquired, checked, then discarded | **654,444,735 bytes** across 15 ZIPs | `data/natural-earth/family_sample_observations_2026-11-07.json` |
| Blocked official source | 10m US manual relief returns HTTP 404 from publisher and official S3 | [Issue #4](https://github.com/gabrielbugarelli/cartorig/issues/4) |
| Windows/C++ and Python regressions | Standard public runner tests pass | [GitHub Actions](https://github.com/gabrielbugarelli/cartorig/actions) |

## What was implemented

- `tools/natural_earth/probe_families.py`: HEAD survey of all 52 sources; per-family selection of the smallest accessible publisher ZIP; hard archive cap of 250,000,000 bytes; hard aggregate cap of 1,200,000,000 bytes; official HTTPS/redirect checks; SHA256, ZIP CRC, georeferenced image + TFW/WLD pair; JSON-only report; optional single-family diagnostics.
- `tests/test_natural_earth_families.py`: 52-source and 16-family selection, hard budget, opt-in network, corrupt archive rejection, Mac AppleDouble fixture.
- `.github/workflows/natural-earth.yml`: on-demand, explicitly tagged `[family-head]`, `[family-samples]` and `[prisma-diagnostic]` probes on free standard Ubuntu runners; one-day JSON artifact retention; no publisher binary artifacts.
- `tools/natural_earth/build_rasters.py`: `is_payload_member()` excludes AppleDouble `__MACOSX/._*` and Finder files from geographic inputs. The entire archive remains subject to ZIP CRC/security checking.
- `tests/test_natural_earth_appledouble.py`: actual TIFF-to-RGBA-tile converter regression with binary macOS resource forks.
- `data/natural-earth/family_sample_observations_2026-11-07.json`: permanent observed source SHA256 evidence from the **real** official family archive samples. It is **not** the full reviewed SHA256 lock.

## Actual upstream defect uncovered and resolved in CartoRig

The real Natural Earth `PRISMA_SR_50M.zip` contains binary AppleDouble metadata, including `__MACOSX/._PRIMSA_SR_50M.tfw`. The first parser incorrectly treated this as geographic data and failed on non-ASCII bytes.

The corrected build filters these resource-fork members; the genuine `PRIMSA_SR_50M.tif` and `PRIMSA_SR_50M.tfw` were revalidated against the official ZIP.

Observed source SHA256:
`2aa9c316bb767b4c4aecbb1c2de255d00d43ab93e7d837e85f01a6dc4e2043fe`

## Publisher-side blocker: 10m US manual shaded relief

- Publisher page: https://www.naturalearthdata.com/downloads/10m-raster-data/10m-manual-shaded-relief/
- Site link: https://www.naturalearthdata.com/download/10m/raster/US_MSR_10M.zip
- Official S3 mirror: https://naturalearth.s3.amazonaws.com/10m_raster/US_MSR_10M.zip
- Status: **HTTP 404** from both URLs during official HEAD survey.
- Known publisher page declares v3.4.0; a visible page link is not proof that the ZIP is downloadable.
- Upstream publisher GitHub tree inspection did not establish a valid, authoritative replacement ZIP.
- Tracking issue: https://github.com/gabrielbugarelli/cartorig/issues/4

No invented replacement URL, third-party mirror, missing tile or fabricated SHA is acceptable. When the publisher makes an authenticated alternate source available, record the evidence, revise the frozen discovery fingerprint *with review*, and rerun the affected tests.

## NE-FETCH-01 exit condition

The technical infrastructure, complete inventory, budgeted live probe, 15 working families, provenance evidence and bugfix are **delivered**. However, the planned criterion **16/16 actual family samples** is **BLOCKED externally** by the 404. This is **not** M2 full acquisition and **not** a verified complete data pack.

M2 must next acquire all 52 approved archives on a persistent release workstation, rehash every source, review/commit `raster_sources.lock.json`, and refuse `NATURAL_EARTH_COMPLETE` until the missing official source has been recovered or an explicitly reviewed scope change is approved.

## Reproduction

On a network-enabled release machine with a local clone of the PR branch:

```bash
python -m tools.natural_earth.inventory --output build/natural-earth/family-probe/official_sources.json
python -m tools.natural_earth.probe_families \
  --inventory build/natural-earth/family-probe/official_sources.json \
  --out build/natural-earth/family-probe --allow-network --fetch-samples \
  --max-archive-mb 250 --max-total-mb 1200
```

The full-family command must exit nonzero while `US_MSR_10M.zip` is unavailable. A scoped 50m PRISMA diagnostic uses `--only-family 50m-prisma-shaded-relief` in addition to the sample arguments. Do not use these network-enabled probes from within the installed Resolve plugin.

