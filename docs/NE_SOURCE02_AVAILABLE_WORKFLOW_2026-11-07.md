# NE-SOURCE-02 — Verified available-source acquisition

Date: 2026-11-07. PR #3. This is a **nonproduction QA workflow**.

## The boundary we must never break

Natural Earth publisher discovery contains 52 raster ZIPs. Issue #4 documents
one currently unavailable original source, US_MSR_10M.zip (official HTTP 404).
The full 52-source production pack, SHA256 lock and release certification
are NOT complete. There is no license to silently reduce the official scope.

The reviewed exception lives at:
data/natural-earth/source_exceptions_v2026-11-07.json

It is cryptographically linked to the official 52-source discovery identity
in data/natural-earth/raster_discovery_v2026-11-07.lock.json.

The missing source remains among the 52 records as KNOWN_UNAVAILABLE,
with its original publisher URL and issue link. It never counts as VERIFIED.
A later recovered real publisher file takes precedence over the exception.

## Acquire the 51 available official publisher ZIPs on Windows

On the release workstation, with Python 3.12 and sufficient persistent disk,
run at the repository root:

~~~powershell
.\packaging\Acquire-NaturalEarth.ps1 -Workspace 'D:\CartoRigBuild' -AllowNetwork -SkipReviewedUnavailable -MaxDownloads 12
~~~

Repeat the command until the JSON report says
AVAILABLE_SOURCES_VERIFIED_NOT_CERTIFIED. Each batch reuses and rehashes
previous SHA256-verified archives. The acquisition-only state is *not*
NATURAL_EARTH_COMPLETE.

Three persistent local files contain the source evidence:
- D:\CartoRigBuild\official_sources.json — exact 52-source official discovery
- D:\CartoRigBuild\downloads\source-archives.json — per-source file/SHA256,
  original publisher URL, verified bytes or known-upstream outage
- D:\CartoRigBuild\acquisition-status.json — counts and an explicit
  release_certified:false status

For an offline recheck of the downloaded ZIPs, run:

~~~powershell
.\packaging\Acquire-NaturalEarth.ps1 -Workspace 'D:\CartoRigBuild' -SkipReviewedUnavailable -MaxDownloads 0
~~~

All downloading is build-time-only and opt-in; installed OpenFX never
makes network requests or depends on Python.

## Optional local experimental data pack for Resolve Studio 20 QA

Once all 51 accessible publisher ZIPs are present, the experimental builder
can also fetch the independently pinned official vector GeoPackage and the
33 supplemental vector layers, compile atlas tiles, and build a native
offline pack. Install release-only Python dependencies and ImageMagick 7
to handle publisher PSD sources:

~~~powershell
py -m pip install -r tools/natural_earth/requirements-release.txt
.\packaging\Acquire-NaturalEarth.ps1 -Workspace 'D:\CartoRigBuild' -Output 'D:\CartoRigExperimental' -AllowNetwork -SkipReviewedUnavailable -BuildExperimental -MaxDownloads 12
~~~

The output is ALWAYS EXPERIMENTAL_INCOMPLETE with pack.complete=false.
Original 52-source source-archives.json is preserved in package provenance.
The strict production verifier must reject it by default.

Only for an explicitly accepted local QA install (Resolve closed):

~~~powershell
py -m tools.natural_earth.verify_release --root 'D:\CartoRigExperimental' --allow-incomplete
.\packaging\Install-DataPack.ps1 -SourceRoot 'D:\CartoRigExperimental' -AllowIncomplete -Confirm:$false
~~~

The standard installer and the production release pipeline remain strict:
an unavailable source still blocks a complete release.

## Engineering delivered

- tools/natural_earth/known_unavailable.py: validates exact reviewed
  original URL, source ID, fingerprint, issue and publisher-outage evidence.
- tools/natural_earth/materialize.py: preserves all 52 required source IDs,
  persists verified/unavailable/pending counts and SHA256 checkpoints.
- tools/natural_earth/acquire_available.py: explicit network opt-in and
  independent resumable acquisition with no certification shortcuts.
- tools/natural_earth/assemble_pack.py: selects verified raster subset only
  for experimental mode, retaining all 52 original source provenance.
- tools/natural_earth/build_experimental.py: opt-in QA pack with fail-closed
  production verification.
- packaging/Acquire-NaturalEarth.ps1: Windows PowerShell entrypoint.
- tests/test_natural_earth_acquire_available.py: 52-source fixtures,
  restart, no-network, tamper, source recovery and forged exception cases.
- tests/test_natural_earth_release.py: experimental full-manifest preservation
  and complete-pack certification rejection.

## Raster storage format after conversion

Production and experimental builders now use lossless PNG v2 offline atlas
tiles. One actual MSR_50M publisher source showed 90% less atlas storage
and identical native C++ output to raw RGBA v1. Three more real publisher 50m families independently reduced combined atlas bytes by 94.50%, with 5.65%–10.96% higher per-runner native 720p full-frame medians for PNG v2.
See [PNG v2 real-source evidence](NE_RASTER_PNG_V2_2026-11-07.md) and [three-family benchmark results](NE_M3_MULTIFAMILY_REAL_RASTER_2026-11-07.md).
The total 51-archive footprint has not been measured.

## Evidence and remaining blockers

- Previous real publisher audit: 24/24 pages, 52 source URLs.
- Real family samples: 15/16 publisher ZIPs sampled and CRC/SHA verified,
  654,444,735 bytes discarded after verification.
- The complete 51/52 archive acquisition on a persistent release workstation
  has NOT yet been executed. No 51/52 real raster pack is claimed.
- Pending: all 51 large ZIPs stored and independently verified, 51-source
  atlas conversion/benchmark, offline Resolve 20 real Inspector/Overlay/4K
  acceptance, and the recovery of the official 52nd ZIP.
- Policy: GitHub standard public CI only; no paid runners, LFS, Packages
  or giant persistent Actions artifacts.
