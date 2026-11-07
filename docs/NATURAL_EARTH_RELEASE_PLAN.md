# CartoRig Native — Natural Earth complete offline release

> **Engineering authority:** [Natural Earth Complete — Execution Plan](NATURAL_EARTH_EXECUTION_PLAN.md) defines the current zero-cost policy, mandatory gate G0–G7, immutable source lock, real raster acceptance, GitHub Releases distribution, and final Definition of Done. This file remains a practical CLI runbook; it must not be treated as completion evidence.


Date: 2026-11-06. PR #3. Experimental v0.4.0, not yet a certified release.

## Goals and source-of-truth

Release one verified offline data pack for the DaVinci Resolve Studio 20 Edit
generator/filter, using published Natural Earth only. The publisher inventory
pins 215 vector sources: 182 in the official GeoPackage, plus 33 independently
SHA-pinned v5.1.2 supplemental layers. The official raster offering has 7
families at 10m and 9 at 50m, with 52 inventoried download variants, not 52
independent visual themes. Raster releases may have their own 3.2.0 version.

Completion is a full local-data audit, not a list of download URLs or a JSON
boolean. Missing sources, invalid TIFF/TFW georeferencing or failed installs
must prevent certification.

## Phase A — Full source acquisition (release workstation only)

Use an external disk with ample free space. Raw RGBA raster pyramids may
consume tens of gigabytes. Python/rasterio/Pillow are build-time dependencies
only; the installed OpenFX runtime remains native C++ and entirely offline.

Install release-only dependencies (and install **ImageMagick 7** so `magick` is on PATH for official layered PSD raster archives):

    py -m pip install -r tools/natural_earth/requirements-release.txt

Run the producer, repeating the identical command as necessary:

    py -m tools.natural_earth.release_pipeline --workspace "D:\CartoRigBuild" --output "D:\CartoRigNaturalEarth" --allow-network --max-downloads 100 --resume

The producer downloads only the independently needed raster archive variants. The 215 pinned vector sources are verified through the official aggregate GeoPackage (182 layers) and independently SHA-pinned supplements (33 layers), not through redundant individual vector download links. With `--max-downloads 100`, one acquisition invocation may fetch all 52 raster variants if official hosts remain accessible. The per-source checkpoint allows safe continuation after interruption. It rehashes
and reuses earlier verified archives from the atomic checkpoint in
D:\CartoRigBuild\downloads\source-archives.json. Exit code 2/INCOMPLETE means
repeat; it is never a release. Network use is explicit: omit --allow-network
when all publisher archives already exist on disk.

The official publisher audit was performed by a free public Actions runner:
https://github.com/gabrielbugarelli/cartorig/actions/runs/42336954400 .
It discovered 24/24 pages and exactly 52 unique ZIP links (38 at 10m,
14 at 50m). Its URL/version inventory has been frozen by the checked-in
`data/natural-earth/raster_discovery_v2026-11-07.lock.json`. This is
separate from — and cannot substitute for — the 52 actual archive SHA256 pins.

### Mandatory reviewed raster source lock (M1)

The download report is a **local observation**, not a trusted publisher checksum
reference by itself. The Complete producer now refuses to advance beyond archive
acquisition until a separate reviewed lock is committed to this repository.

When the 52 raster archives are acquired (the pipeline reports that the review
lock is absent), create a candidate from the *exact* source audit and the
verified local archive report, while in the repository root:

    py -m tools.natural_earth.source_lock \
      --inventory "D:\CartoRigBuild\official_sources.json" \
      --archives "D:\CartoRigBuild\downloads\source-archives.json" \
      --out "data\natural-earth\raster_sources.lock.json"

On PowerShell, put those arguments on one line or use PowerShell backtick
continuations. Review all 52 source IDs, URLs, versions, sizes and SHA256
digests, then commit the lock to the feature branch. The command refuses to
overwrite an existing approved lock. Verify before any new build:

    py -m tools.natural_earth.source_lock --verify \
      --inventory "D:\CartoRigBuild\official_sources.json" \
      --archives "D:\CartoRigBuild\downloads\source-archives.json" \
      --out "data\natural-earth\raster_sources.lock.json"

Rerun the producer with --resume after the reviewed lock has been committed.
A publisher release change requires a new explicit review, not an automatic
overwrite of the lock. No real raster source lock has been committed yet:
acquisition of the 52 official source files is still an OPEN gate.

Downloads themselves now support HTTP Range + strong ETag (or Last-Modified)
safe byte-level resume, with persisted .part/.part.json files. If an official
server cannot verify a range, the download starts over instead of appending
unknown data. Wrong redirects, incomplete Content-Range responses and changed
source identities fail closed; source ZIP symlinks and Windows drive paths are
rejected. All such recovery checks are exercised with synthetic HTTP fixtures.

After acquiring all official archives, the producer checks the known SHA256
of the official vector GeoPackage ZIP, imports the 33 publisher-pinned
supplements, builds the SQLite FTS5 index and converts all raster variants.
Large TIFFs are decoded in bounded rasterio windows, using matching world
files and independently verified tile checksums.

Conversion happens in a same-volume persistent staging directory named
.CartoRigNaturalEarth.assembling, with a sibling
.CartoRigNaturalEarth.assembling.resume.json proof file that survives even
a crash during the final manifest SHA256 scan. A failed conversion can resume from
fully rehashed tiles; changed publisher source hashes invalidate the stage.
The 52 publisher raster variants are distinct source archives, not 52 unique
styles. TIFF, JPG and PNG can be read in windows; official layered PSD raster
composites require release-machine ImageMagick 7 and are converted to TIFF
before the same bounded tile preparation. The installed plugin requires none
of these release dependencies.

For a PowerShell end-to-end entrypoint on the release workstation, use:

    ./packaging/Build-NaturalEarth.ps1 -Workspace "D:\CartoRigBuild" -Output "D:\CartoRigNaturalEarth" -AllowNetwork -MaxDownloads 100 -SetupDependencies

This command verifies the final pack identity before permitting distribution.
Its product is a large local data directory, not a GitHub Actions ZIP artifact.
Only a passing full coverage report is promoted to D:\CartoRigNaturalEarth
with status NATURAL_EARTH_COMPLETE in pack.json.

Any TIFF lacking georeferencing fails. Decorative unreferenced thumbnails are
reported but not counted as cartographic layers. Unsupported PSD conversion
fails rather than fabricating data or claiming source coverage.

## Phase B — Verification and air-gapped Windows installation

On the release workstation, rehash the entire produced data directory:

    py -m tools.natural_earth.verify_release --root "D:\CartoRigNaturalEarth"

Transfer the final directory by USB or other offline medium. Close Resolve
before installing. Install the OpenFX bundle, then run:

    .\Install-CartoRigNaturalEarth-DataPack.ps1 -SourceRoot "E:\CartoRigNaturalEarth" -Confirm:$false

Use -Upgrade only when replacing an existing installation. The PowerShell
installer checks every SHA256, file length, manifest pack ID, undeclared
files, symlinks and adequate disk space. It stages and verifies the data
before switching the active installation, and keeps a rollback directory.
The default local location is:

    %LOCALAPPDATA%\CartoRigNative\NaturalEarth

Never use -AllowIncomplete for a production pack.

## Phase C — Resolve Studio 20 Edit acceptance

1. Verify Map Generator and Overlay Filter display the normal neutral map
   before opt-in. Enable installed Natural Earth and load official country
   geometry without typing file paths.
2. Test Continent, Country, State/Province and City search using Brazil,
   São Paulo and ambiguous location names. Check actual parent territory,
   no fictitious municipal polygons and live dropdown refresh.
3. Select multiple features with independent RGBA styles, then add/delete
   color keyframes at frames 0, 50 and 100. Test backward scrubbing,
   random seeks, Hold/Linear/Smoothstep, undo/redo and project re-opening.
4. Select official 50m and 10m raster atlases from the local searchable
   picker. Confirm geodetic position, dateline continuity, alpha blending,
   regional vector overlays and texture selection.
5. Measure 1440p responsiveness, 3840x2160 Deliver and 8K if feasible.
   Record CPU use, peak RAM, repeated-export hashes and any OFX errors.
6. Repeat with networking physically disabled. No CDN, tile HTTP, keys or
   background downloading is permitted at runtime.
7. Record Windows/Resolve versions, OpenFX build SHA, screenshots, test
   project and 4K export evidence before accepting the release.

A synthetic OpenFX host cannot certify the true Resolve Inspector, 4K
Deliver performance, saving/re-opening, GPU/CPU integration or undo/redo.

## Current acceptance gates

- [x] 215/215 pinned vector source provenance and native rendering groundwork
- [x] Resumable, SHA256-verified official archive acquisition
- [x] Bounded raster conversion, per-tile checksum and resumable atlas staging
- [x] Complete-data certification gate and offline verifier/Windows installer
- [x] Multi-region search, independent RGBA animation and raster picker source
- [ ] All 52 raster source variants actually downloaded, converted and packaged
- [ ] Distribution size/memory benchmark on genuine 10m/50m raster combinations
- [ ] Current Windows CI runner restored and installer verified on Windows
- [ ] Actual Resolve Studio 20 Edit+Overlay, project and 4K/8K acceptance

The PR must remain draft until the unchecked gates pass.
