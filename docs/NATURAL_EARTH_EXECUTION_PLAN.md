# CartoRig — Natural Earth Complete: Engineering Execution Plan

**Version:** 1.0 (execution baseline)  
**Project:** https://github.com/gabrielbugarelli/cartorig  
**Target:** Windows 11 x64, DaVinci Resolve Studio 20 Edit, native C++17 OpenFX  
**Repository:** public, MIT-licensed, free/open-source  
**Non-negotiable policy:** no GitHub billable services; total GitHub spend = USD 0.  
**Status:** PLAN APPROVED FOR EXECUTION; DATA PACK NOT YET CERTIFIED. PR #3 remains draft until every release gate passes.  
**Baseline:** branch feat/natural-earth-offline-data; source SHA must be recorded with every acceptance artifact.

**Producer toolchain baseline:** Python 3.12 / rasterio 1.5.0; CI also exercises Python 3.11 with rasterio 1.4.4 for cross-version compatibility. The pinned producer versions and exact runtime platform are recorded in build provenance.

This is the normative work order and acceptance contract for the complete Natural Earth backend. It supersedes the older informal release plan wherever they conflict. It does not claim that an unexecuted task has passed.

## 1. Product contract and strict scope

1. The installed OpenFX Generator/Filter must execute fully offline, with no Python, ImageMagick, GDAL service, CDN, HTTP requests, cloud API, paid provider, account, authentication or telemetry. The network-enabled release producer is distinct from the plugin runtime.
2. Natural Earth is the sole authoritative geographic source for the complete baseline. No OpenStreetMap, Mapbox, paid tiles, external geocoder or fabricated territorial polygons may silently replace missing publisher data.
3. The baseline source *inventory* contains 215 pinned vector source layers: 182 in the official aggregate GeoPackage plus 33 SHA-pinned supplements from Natural Earth v5.1.2. Raster inventory initially contains 52 discovered download *variants* across 7 10m raster families and 9 50m families. These are not 52 distinct cartographic themes. Inventory counts and versions must be locked and reaudited before release.
4. 110m/50m/10m vector and 50m/10m raster sources are separate data universes. Do not assert there are 110m official raster families. Store each source's publisher version independently (some raster archives use v3.2.0).
5. Full data-source coverage requires verified ingestion and rendering of applicable vector Point/MultiPoint, LineString/MultiLineString and Polygon/MultiPolygon classes, with correct layer IDs, provenance, antimeridian handling and selection. Merely indexing a GeoPackage table does not certify rendering that layer.
6. Country/continent/state/province/city semantics must reflect publisher geometry. Cities are points unless an actual polygon source is present. Do not invent municipal boundaries or authoritative political interpretations.
7. Original layered PSD files may be flattened for a *raster-composite variant*, but Photoshop editability is not automatically part of the OpenFX product. The released inventory must say which composite/layer of each publisher archive was ingested. Every georeferenced publisher visual variant must have a validated derivative or an explicit blocking reason.
8. The complete pack must be a portable, cryptographically checked release artifact with a deterministic identity, and must survive moving a project between machines when the same pack version is installed.
9. 4K Resolve Edit render, saved/reopened project, live Inspector selections, Overlay alpha, user-authored animation and offline network-denial are release gates; 8K is a measured optional capability, not a claim.
10. No standalone HTML timeline, Electron window, MapLibre server, mandatory PNG pre-render or Fusion-page visit may be introduced to achieve the above.

### Existing code — not equal to product acceptance

Already present: official source-page inventory, pinned 215-vector manifests, SQLite FTS5/RTree catalog, runtime C++ geographical feature lookup, country/polygon renderer, opt-in Natural Earth pack paths, native multi-region RGBA selection and color keys, searchable raster dropdown, tile renderer + bounded 64-tile cache, Python release producer, disk-staged conversion, SHA256 pack verifier and Windows installer. CI builds and local synthetic tests exist.

Not yet established: frozen SHA256 lock for every real raster archive; actual 52/52 acquired/converted; every vector-class render; compressed/affordable full-package size; publisher-backed 4K/8K performance; reliable Windows install/upgrade acceptance; in-host Resolve 20 Inspector/Overlay acceptance. Until all gates pass, NEVER emit NATURAL_EARTH_COMPLETE as product marketing.

## 2. Target architecture

~~~text
PUBLISHER (network allowed ONLY on trusted build workstation)
  Natural Earth v5.1.2 vector aggregate + 33 pinned supplements
  Raster source-page inventory / 52 baseline download variants
       |
       v
SOURCE LOCK + CHECKPOINT (content addressed, publisher URLs/version/SHA256)
       |
       +--> downloader (verified byte-range resume, official allow-list)
       +--> source audit (SHA256, ZIP CRC, zip-slip, size/entry limits)
       |
       v
NORMALIZER / COMPILER (release-only Python, rasterio, Pillow, ImageMagick)
       +--> 215 vector sources / layer coverage, typed geometry and metadata
       +--> SQLite FTS5/RTree search
       +--> raster atlases, TFW affine checks, bounded tiles and LOD
       |
       v
CERTIFIER (offline, independent process and filesystem rehash)
       +--> source identity + class-level geometry + geographic alignment
       +--> per-asset proof + full tile content + manifest consistency
       |
       v
IMMUTABLE DATA PACK  (pack.json + vector/ + raster/ + provenance/)
       |
       v
RELEASE PUBLISHER (GitHub Releases: <= 1.5 GiB each volume; SHA256 index)
       |
       v
OFFLINE WINDOWS INSTALLER (verify, stage, atomic swap, rollback)
       |
       v
C++ OpenFX, Resolve Studio 20 Edit (strictly offline; no Python or network)
~~~

All stages are individually runnable and report machine-readable DONE, INCOMPLETE, FAILED or BLOCKED. A failure must not silently mutate a previously certified release.

## 3. Milestone M0 — repository, tooling and zero-cost safety

**Files:** .github/workflows/build.yml, .github/workflows/natural-earth.yml, packaging/*.ps1, tools/natural_earth/requirements-release.txt, docs/.

- Use gabrielbugarelli/cartorig exclusively; remove stale git clone URLs and old release paths.
- Use only standard GitHub-hosted public runners (Windows and Ubuntu) or voluntarily operated self-hosted runners; no larger runners, paid Codespaces, GH Packages, LFS or premium services.
- PR/push CI: run code validation, C++/OpenFX/PowerShell tests and small synthetic fixtures; do not upload huge reference PPMs or full data packs.
- Temporary bundles only on explicit workflow_dispatch; retention-days: 1; enforce a small output-size budget; no release archives in Actions Artifacts or Cache. Avoid nonessential persistent caches.
- Source probes must be explicitly invoked and upload only small textual reports with one-day retention.
- Fix PowerShell parser errors and run an actual Windows AST parse + install/upgrade/tamper tests; a syntactically plausible script is NOT certification.
- Determine runner failures from GitHub run/job annotations, account Actions permissions and workflow diagnostics. Never call a zero-step runner error a failed C++ compile.
- Keep workflow token permissions minimal. Publish Releases only through an explicit user-triggered flow, using a repository-scoped credential; never expose credentials or trusted publishing privileges to untrusted PR builds.
- Billing gate: repository public, no paid services, no unnecessary billable data stores. Account owner sets a USD 0 hard-stop spending budget for metered GitHub products wherever offered; alerts alone are not a hard stop.

**Gate G0:** the current exact PR commit runs relevant Windows and Linux tests with actual steps and green results; public-runner eligibility and nonbillable workflows are documented. If runners remain blocked, perform the same tests locally without enabling paid services.

## 4. Milestone M1 — immutable publisher inventory and source provenance

**Files:** inventory.py, materialize.py, data/natural-earth/, new raster_sources.lock.json and validator.

- Generate an explicit inventory of all eight vector/raster root category pages and raster child-family pages; record URL, resource_id, scale, theme, label, publisher version, filename/type, bytes, source-page hash and acquisition URL.
- Freeze the full baseline after an independent audit. Compare current site discovery against the frozen lock; additions/removals/renames are a reviewed source upgrade, not an automatic replacement.
- 215-vector pin proves source provenance: aggregate GPKG content (182) plus 33 independently SHA-pinned supplemental GeoJSON. Avoid downloading redundant per-vector CDN archives just to satisfy a spurious total.
- Lock each raster archive's SHA256 *after authentic acquisition and independent review*. A digest freshly calculated by the same untrusted acquisition process is only a local integrity checksum, not an independently pre-established publisher checksum.
- Preserve any ZIP/non-ZIP distinction. Inventory can discover PSD/TIFF/7z links; a ZIP-only ingestion path must be extended or records must be explicitly classified as unsupported BLOCKERS before production.
- De-duplicate by canonical publisher variant; never mistake multiple links or mirrors for unique map styles. Capture source metadata, license (Natural Earth public domain) and publisher limitations.

**Gate G1:** exact baseline manifest exists with complete audited counts; all expected source variants have stable IDs, an acknowledged acquisition strategy and no unreviewed substitutions.

## 5. Milestone M2 — robust download, persistence and source verification

**Files:** inventory.py, materialize.py, verify_pack.py, release_pipeline.py, tests/test_natural_earth_coverage.py.

- Workstation-only official HTTPS downloader with fixed hostname allow-list; preserve final redirect hostname validation and reject downgrade, credentials and traversal.
- Implement actual HTTP Range partial-byte resume guarded by ETag/Last-Modified and Content-Range. Existing implementation resumes at completed *archive* granularity, not partial bytes. On a changed remote file or incompatible server response, restart that archive safely.
- Require bounded timeouts, bounded retry with backoff, size limits appropriate per archive, streaming SHA256, atomic .part files and fsync/replace checkpoints where practical.
- Validate ZIP central directory, per-entry CRC, member type, names, symlinks, expansion ratio and cumulative decompression budget. Reject unrecognized container formats until adapter tests pass.
- Mirror fallback may use only publisher-sanctioned official endpoints and must retain the original canonical provenance and bytes/hash. Do not silently acquire repackaged third-party data.
- Recover after network interruption, process termination, stale checkpoints, hash mismatch, duplicate source ID and exhausted disk.
- Download vector GPKG pinned by known official ZIP SHA256, and 33 supplements with pinned blob identities. Verify SQLite integrity, expected tables, source checksums and feature counts.

**Gate G2:** independently verify every downloaded publisher source against the locked source inventory; the release is repeatably restartable with network disabled once all sources are local.

## 6. Milestone M3 — complete raster derivation and economical storage

**Files:** build_rasters.py, natural_earth_raster.cpp/.hpp, raster asset tests, versioned raster format specification.

- Inventory and test every real publisher raster archive. Identify all georeferenced images and TFW/WLD sidecars; distinguish thumbnails from source rasters and record all exclusions with evidence.
- For TIFF/PNG/JPEG read bounded windows and build 256x256 georeferenced tiles; use defined transparent/padding behavior, correctly sampled pixel-center transforms, and anti-aliased LOD without seams. Use source alpha where supplied.
- For layered PSD, derive the source's documented composite using release-machine ImageMagick, write a temporary tiled TIFF and process in windows. For any publisher PSD whose composite is insufficient, implement a verified per-layer adapter or explicitly block its source variant.
- Reject rotation/non-WGS84 transforms until an explicit reprojector with validation is implemented; never reinterpret coordinates. Test dateline, ±180°, poles and precise 10m/50m overlay alignment.
- Benchmark worst-case 21,600x10,800 raster sources and multiple stacked layers. Current raw RGBA pyramids can be large; compute actual disk/RAM before selecting the storage format.
- Engineering choice: retain existing raw-tile v1 reader for backwards compatibility; introduce a versioned compact tile v2 only if the full corpus demonstrates unacceptable storage/transfer. Prefer deterministic zstd tiles (or a benchmark-proven alternative), bounded decompression and a C++ adapter; compare speed, package size and image quality with raw v1. Never substitute lossy compression without editorial acceptance.
- Maintain a bounded runtime LRU and workload-aware vector/raster culling. Avoid preload of all 52 source variants. Integrity hashes for ALL atlas files must be verified by the release certifier/installer; normal per-frame C++ render should not rehash the entire data pack.

**Gate G3:** every locked raster variant has a validated derivative or production is BLOCKED; pixel golden tests cover geometry/alignment/alpha and memory/performance measurements are published for actual publisher files.

## 7. Milestone M4 — all vector classes rendered and searchable

**Files:** build_catalog.py, coverage.py, natural_earth_geometry.cpp, natural_earth_regions.cpp, ofx_plugin.cpp.

- Verify exact real GeoPackage layer table counts, EPSG, record counts, geometry type and source provenance, not just manifest names.
- Render all supported Natural Earth categories by source layer and style: polygon/multipolygon with holes, line/multiline with clipping, and point/multipoint with symbols. Support and test any additional geometry types actually present in the frozen corpus.
- Stream or spatially query large layers by view bounds; remove the current fixed whole-layer feature budget as a barrier to real data coverage. Test 110m, 50m and 10m LOD switching without gaps.
- Build typed country, continent (derived from real admin-0 polygons), state/province and city point search. Normalize accents, aliases, case and ambiguous names; retain original publisher IDs.
- Provide an actual usable layer registry in native controls: find/show/hide base map, roads, rivers, coastlines, lakes, physical/cultural layers, etc. Preserve editorial style per layer and vector-over-raster order.
- Keep geospatial geometry truthful: no imaginary municipal polygons, no stale feature refs, no uncontrolled border smoothing; mark disputed-boundary provenance where applicable.
- Cache index/geometry by pack identity and source feature revision, not by assumptions about global paths alone.

**Gate G4:** 215/215 pinned source layers are not merely indexed but have a class-appropriate, documented read/render path exercised on official data. Geographic search and selection return correct real features.

## 8. Milestone M5 — deterministic pack, independent certification and offline installer

**Files:** assemble_pack.py, build_pack.py, verify_release.py, packaging/Install-DataPack.ps1, new release splitter/restore tools.

- Treat pack.json as an immutable, versioned bill of materials: source digests, derived asset hashes, size, source version, toolchain schema, layer/variant identity and pack_id. Sort paths and canonicalize JSON.
- Verify each raw source in its stored archive and each prepared atlas in a separate certification process. Check duplicate or missing source IDs, fake complete flag, missing tiles, undeclared files, links and traversal. Add negative certification tests for every reason.
- Resume persistent stages without losing the source checkpoint during finalization. Make the final pack promotion atomic on the same volume and recovery deterministic after process death.
- Implement an exportable pack as <= 1.5 GiB numbered parts (below GitHub's 2 GiB per-asset hard cap), with part SHA256 + aggregate package SHA256; do not confuse chunked transport checksums with underlying pack_id.
- Provide a restore command that verifies every part before reconstructing the complete directory; no hidden network fallback.
- On Windows, verify source -> stage -> target identity, available disk, rollback on failed upgrade, existing pack preservation, Unicode paths, linked entries and input tampering. Source/dependency location must not be silently rewritten.
- Local installed pack may be on an external drive or default LOCALAPPDATA. UI opt-in must be deterministic; preserve manual custom path precedence.
- Render-time pack health: check compatible pack metadata cheaply at load/open time; a full per-file SHA scan belongs to install/explicit verify, not every frame.

**Gate G5:** package complete identity reproducible from the frozen source and toolchain; all per-source/asset hashes valid, reinstall/upgrade/rollback tests pass on Windows; no test fixture can be certified as complete.

## 9. Milestone M6 — DaVinci Resolve Studio 20 actual host validation

**Files:** src/ofx_plugin.cpp, src/native_controls.cpp, docs/RESOLVE20_ACCEPTANCE.md, manual evidence bundle.

- Generator and Overlay Filter must load in actual Resolve Studio 20 Edit. Source selection from the Inspector must use an installed offline pack without JSON editing.
- Geographic Region: select continent/country/state/city; verify typeahead, source-specific labels, ambiguous names, repeat selection, removal, independent RGBA style and persistent keyframes. OpenFX host refresh semantics require real host testing; if dynamic dropdown cannot work, implement a genuinely usable supported alternative instead of claiming full functionality.
- Raster: select several real publisher 50m and 10m variants; verify source ID, correct texture, bounds, alpha and layering over video. Verify no networking in process under a denied network interface.
- Animation: playhead capture uses actual OFX time; test Hold/Linear/Smoothstep, random seeks, negative time scaling, clip trim, duplicate and Undo/Redo. Confirm independent clip instances.
- Color: compare source-over on opaque video, premultiplied/straight alpha in 8-bit and float, project color management, Viewer versus Deliver, 4K and reduced-preview caches.
- Project: save/close/reopen, duplicate/move between Windows machines with same installed data pack, missing pack diagnostics, change pack version and reopen old scenes safely.
- Stress: 20 independent effects, repeated random seeks, high-detail state boundaries, large lines/markers, 4K Deliver, peak memory and leaks. 8K may be marked optional if resource budget is explicitly documented.
- Record source SHA, Resolve Studio exact build, GPU/driver, OS, pack_id, scene hash, screenshots, comparison frames, timing, RAM/VRAM and bug links for every pass.

**Gate G6:** all mandatory R20 checks pass on a real Windows Resolve Studio 20 installation. Synthetic-host and Linux tests are supporting evidence only.

## 10. Milestone M7 — GitHub Zero Cost release and update policy

**Policy invariant: total amount charged by GitHub must be USD 0.**

- Public repository and standard hosted Actions runners only. Self-hosted is optional but must be user-owned and unbilled by GitHub; external hardware/electricity are outside GitHub billing.
- No GitHub Larger Runners, LFS, Codespaces, GitHub Packages, paid AI services, private-runner overage or paid artifact/cache storage.
- Normal PR/push uploads: none of the large images, datasets or binaries to Actions Artifacts. Manual test binaries use 1-day retention and size cap; release asset transport uses GitHub Releases only.
- GitHub Releases documentation as of this plan: up to 1000 assets per release, each < 2 GiB, no documented limit on release total size or bandwidth. Split at 1.5 GiB to leave margin. Monitor future GitHub changes before publishing.
- No unbounded public CI source crawling on every PR. Publisher source probes are deliberate and small, never produce giant persistent artifacts.
- Release versioning: code tag + verified pack version and pack_id, SHA256SUMS + provenance JSON + license/credits; release draft until verification. A plugin release and compatible data-pack release should be independently versioned.
- Account-owner action: set a zero-dollar hard-stop budget for metered products wherever GitHub offers enforcement. Alerts alone do not guarantee no charges; check already incurred usage, and never enable a billable feature while resolving a runner problem.
- CI failure from missing runner/steps is a platform/account issue; distinguish from actual failing tests. Avoid paid workarounds and never merge because a test was not run.

**Gate G7:** source/build/release artifacts are available through free GitHub facilities; the pack can be downloaded, verified, installed and used offline; billing settings reviewed by repository owner, and no paid service was enabled.

## 11. Exact task sequence and proposed change sets

| Order | Change set | Exact work | Completion evidence |
| --- | --- | --- | --- |
| 01 | NE-INFRA | Public GitHub CI on current SHA, PowerShell AST, Windows installer test, artifact size/retention guards | G0 |
| 02 | NE-SOURCE | Freeze official 215 + 52 inventory lock and publisher metadata | G1 |
| 03 | NE-FETCH | HTTP byte-range resumable downloader, immutable source SHA, corruption/restart tests | G2 |
| 04 | NE-RASTER | Process actual 52 archives, debug non-ZIP/PSD cases, geographic pixel goldens | G3 |
| 05 | NE-VECTOR | Full typed geometry read/render at all 215 source layers and source registry UI | G4 |
| 06 | NE-LOD | Stress real 10m data; implement compressed raster tiles if proven necessary | G3/G4 |
| 07 | NE-PACK | Independent complete certifier, atomic staging, part splitter and restore verifier | G5 |
| 08 | NE-INSTALL | Windows production installation, tamper/rollback/missing-disk tests | G5 |
| 09 | NE-RESOLVE | Actual Resolve Studio 20 Edit Inspector, Filter, save/reopen, 4K and offline denial | G6 |
| 10 | NE-RELEASE | Publish signed/checksummed release metadata and segmented data pack via Releases | G7 |

Change sets may be commits on PR #3 during development but should produce reviewable diffs and green tests before the draft is promoted. Keep operational publisher downloads on the release workstation and never commit giant data to Git.

## 12. Test evidence matrix

| Test | Dataset | Must assert |
| --- | --- | --- |
| Lock reproducibility | frozen manifest | no duplicate/missing/cross-version sources |
| Download recovery | interrupted HTTPS fixture | correct Range/ETag or safe restart; same hash |
| Source safety | corrupt ZIP/PSD/TIFF | reject traversal, bombs, wrong CRS and mismatched bytes |
| Vector class parity | real 215-layer producer | count, geometry read, render and geographic bounds |
| Search | country/ADM1/city/continent aliases | typed results, unambiguous selection, no invented polygons |
| Raster alignment | real 10m/50m overlays | pixel/TFW center transforms, no seams and alpha errors |
| Raster integrity | modified/deleted tile | fail complete certification and installer checks |
| Pack deterministic | two equivalent source builds | same canonical pack identity under pinned tools |
| Windows installer | install/upgrade/rollback | no destroyed prior pack on any failed replacement |
| Resolve project | edited/saved/reopened | exact source IDs, colors, keys and file paths |
| Resolve render | Edit/Deliver 4K | correct output over footage, bounded memory and no crash |
| Offline denial | blocked interfaces | no runtime DNS/HTTP/CDN requests or hidden fallback |
| Release transport | multipart assets | all SHA256 parts and reconstructed pack match |

Tests must not define success as a mock summary reporting 215 or 52. At least one validation of each actual source family and source geometry type is mandatory.

## 13. Risk register and hard decisions

| Risk | Engineering mitigation |
| --- | --- |
| Official publisher link changed or unavailable | freeze source lock; retry only publisher endpoints; preserve BLOCKED source list, do not replace with third-party data |
| 52 URLs do not represent 52 unique styles | record source variants and derived asset mapping separately |
| PSD flatten may drop meaningful visual layers | inspect every official composite; add adapter or block certification |
| Uncompressed tile pack very large | measure genuine corpus; compatible v2 compression + runtime decoding if needed |
| Source hash in discovery is self-declared | require independent locked reference or explicit source-acquisition trust record |
| CI runs but Windows PowerShell is broken | real Windows Parser AST + tampering tests must pass |
| GitHub Actions storage overages | no routine artifact upload; 1-day small manual archives; Releases for distribution |
| Cached project points to wrong data version | pack_id-bound cache and actionable relink/migration |
| Render-only geometry misses most physical/cultural layers | per-layer typed renderer and systematic layer-by-layer acceptance |
| CI host never exposes expected OpenFX controls | real Resolve host capability testing and supported native Inspector fallback |
| Rehash at every render destroys performance | full hash in builder/installer, bounded cheap check in runtime |
| Excessive claims of completion | fail-closed gates G0–G7; PR remains draft until all mandatory evidence recorded |

## 14. Release readiness ledger (must be updated with exact evidence)

| Gate | Current evidence | Status |
| --- | --- | --- |
| G0 CI/Windows validation | Source tests and Windows checks exist; post-public-host run still requires confirmation | OPEN |
| G1 locked source inventory | Official 24/24-page discovery pin and 52-source fingerprint; 15 real family source SHA256 observations committed; 52-source reviewed content lock remains unavailable, including one official 10m 404 | PARTIAL |
| G2 source acquisition | Byte-range resume and archive security tests passed; 51/52 official source URLs returned HEAD metadata; 15/16 families sampled from genuine ZIPs, 654,444,735 acquired bytes; US_MSR_10M.zip 404 upstream; 52-source acquisition still blocked | PARTIAL |
| G3 raster derivative parity | Four distinct official 50m raster families now independently converted/painted by native C++, including three additional real source baselines; PNG v2 stored 94.50% fewer bytes than raw in those three samples (5.65%–10.96% slower per-runner 720p full-frame medians). Other 48 of 52 source variants still have no demonstrated end-to-end render, and 51/52 persistent acquisition is open. | PARTIAL |
| G4 all vector-layer rendering | 215/215 source inventory and primary polygons; not all types rendered | OPEN |
| G5 pack/installer | fail-closed builder and installer source; real full pack absent | OPEN |
| G6 Resolve Studio 20 host | original Generator test exists; full data Inspector/Overlay not certified | OPEN |
| G7 zero-cost public release | public MIT repo exists; full dataset release not published | OPEN |

A feature, status or source count is marked PASS only with reproducible evidence: exact source tag, pack_id, test log, real publisher data proof, CI URL or actual Resolve recording. Missing evidence means OPEN/BLOCKED, never assumed PASS.

### Publisher source discovery evidence — 2026-11-07 UTC

- A real official-source audit ran on free GitHub-hosted Ubuntu Actions:
  https://github.com/gabrielbugarelli/cartorig/actions/runs/42336954400
- 24 indexed official pages, 0 inaccessible pages, 269 discovered links.
- Exactly **52 unique official raster ZIP URLs**: **38 at 10m** and **14 at 50m**, from 16 raster-family pages. No source-archive SHA256 was claimed.
- Audited canonical source rows are fingerprinted in
  `data/natural-earth/raster_discovery_v2026-11-07.lock.json`, digest
  `dbd0bb7a3323b764570c3305e0c778aaa73143cf15d941d2a84c1dba9cd2b0b0`.
- This is **M1 discovery scope frozen**, not M1 final content provenance.
  The 52 physical ZIPs and approved `raster_sources.lock.json` are still absent.
- M2 tests include byte-range resume after interrupted transfers, servers
  ignoring Range, changes to ETag, malformed 206, foreign HTTPS redirects,
  excessive Content-Length, ZIP symlinks/drive paths and tampered source
  manifests. Real WAN full-corpus acquisition remains outstanding.
- Staging resume evidence is now stored OUTSIDE the future pack tree, surviving
  interrupted final SHA256 hashing and atomic directory rename.

### NE-FETCH-01 verified sample evidence — 2026-11-07

- Details, exact SHA256 observations, public workflow links, blocker and
  reproducible commands: [NE-FETCH-01 acceptance audit](NE_FETCH01_ACCEPTANCE_2026-11-07.md).
- 15 of 16 family examples were genuinely downloaded and validated; all ZIPs
  discarded from the free runner after verification.
- Real 50m PRISMA TIFF/TFW regression: ignore `__MACOSX/._*` sidecars.
- Unique publisher block: `US_MSR_10M.zip`, HTTP 404 on both official tested
  endpoints; tracked as [issue #4](https://github.com/gabrielbugarelli/cartorig/issues/4).
- M1/M2 and the Complete pack must **not** be marked PASSED based on this
  sample evidence alone. The 52-source content SHA lock is still missing.

### M1/M2 implementation update — reviewed upstream publisher gap (2026-11-07)

- NE-SOURCE-02 added a 52-row checked-in publisher-outage exception for the 10m US manual-shaded-relief 404 only. It is pinned to the existing discovery fingerprint and does **not** reduce required source coverage.
- All other publisher archives can be SHA256-verified in resumable batches on a persistent local workstation without waiting for the missing ZIP. A dedicated acquisition CLI and PowerShell wrapper report verified, pending and KNOWN_UNAVAILABLE sources.
- After 51 verified official raster ZIPs are actually acquired, a separately opt-in, offline, nonproduction experimental pack can be built with real vectors and rasters for Resolve tests; it retains the full 52-source audit and is deliberately rejected by the production verifier.
- Code and synthetic regression tests are implemented. **No full 51-archive workstation download or full actual raster conversion is claimed.** G1/G2 still require publisher-content evidence, and all G0–G7 complete release gates remain intact.
- Practical workflow: [NE-SOURCE-02 Available-source acquisition](NE_SOURCE02_AVAILABLE_WORKFLOW_2026-11-07.md).

New [multi-family publisher raster and native performance evidence](NE_M3_MULTIFAMILY_REAL_RASTER_2026-11-07.md) confirms Gray Earth, PRISMA Shaded Relief and Shaded Relief with exact frame hash equivalence between PNG v2 and raw v1; their atlas sizes were 1,387,528,192 vs 76,332,260 bytes. Native renderer medians at 720p are measured on an Ubuntu standard runner and do not replace Windows Resolve host QA.

### M3 native raster PNG v2 evidence — 2026-11-07

The official MSR_50M.zip (SHA256 e38f8b256f64eccae250a1e482761d4a7a585e6602c941e6bdb860e160faf609) was converted from TIFF/TFW to both raw RGBA v1 and lossless PNG v2 atlases. Both rendered identical 230,400 native C++ pixels (frame hash 13112041101257582482). Original atlas: 335,806,464 bytes; compressed PNG v2: 33,583,241 bytes (90.0% less). Both had seven LODs and 1,281 tiles. This only verifies one real 50m source, not 52/52 coverage or a Resolve host render.

Vendored portable LodePNG decodes both formats, bounds PNG input and IHDR dimensions before allocation, and retains offline runtime. Experimental and complete release producers choose PNG v2. Existing raw atlas reading remains supported. Evidence and license provenance: [NE_RASTER_PNG_V2_2026-11-07](NE_RASTER_PNG_V2_2026-11-07.md). Full M3 source conversion, 4K host profiling and total pack size remain OPEN.

## 15. Definition of Done — Natural Earth Complete

The complete release is accepted only when:

1. Every source in the locked and reviewed publisher inventory is present and verified.
2. 215/215 pinned vector layers are read and renderable according to their actual geometry class, at correct 110m/50m/10m scale.
3. Every baseline raster variant produces verified geographically aligned derivatives; exceptions require revision of the approved source scope and cannot be hidden.
4. A deterministic full data directory passes an independent offline certifier and a tamper/reconstruction test.
5. The versioned split release is published via public GitHub Releases under the file/asset limits, with SHA256SUMS, provenance and offline restore instructions.
6. An offline Windows install, clean upgrade and rollback pass.
7. The actual DaVinci Resolve Studio 20 Edit workflow passes mandatory search, independent region styling, keyframes, raster selection, alpha and 4K Deliver acceptance.
8. Installed plugin works without an internet interface, paid account or third-party data provider.
9. Public GitHub workflows and assets obey the USD 0 billing policy; no billable product is activated.
10. PR #3 is promoted only after G0–G7 have links to real evidence and all blocking bugs are closed.

### M1 source-page audit probe on public standard runner

An explicitly tagged commit `[source-probe]` launches the existing
`source-discovery` job in `.github/workflows/natural-earth.yml`. The job
fetches the official category/family pages, uploads only the small discovery
JSON with one-day retention, and performs a small independent 110m archive
check. This is a **source availability audit**, not an acquisition or
certification of all 52 raster archives. No giant data pack is stored in
Actions Artifacts. Compare the actual discovered variants with the 52-variant
baseline before creating a reviewed source lock.

## 16. Verified external policies and reference documentation

- Natural Earth downloads: https://www.naturalearthdata.com/downloads/
- Natural Earth 10m raster details: https://www.naturalearthdata.com/downloads/10m-raster-data/
- Natural Earth 50m raster details: https://www.naturalearthdata.com/downloads/50m-raster-data/
- Natural Earth public-domain terms: https://www.naturalearthdata.com/about/terms-of-use/
- GitHub Actions billing: https://docs.github.com/en/actions/concepts/billing-and-usage
- GitHub Actions plan and artifact storage: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- GitHub Releases limits: https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- GitHub budgets: https://docs.github.com/en/billing/how-tos/set-up-budgets
- Existing CartoRig release process: docs/NATURAL_EARTH_RELEASE_PLAN.md
- Real Resolve acceptance: docs/RESOLVE20_ACCEPTANCE.md

**No promise of uninterrupted GitHub availability or permanent free-plan quotas is implied.** If a free GitHub capability becomes unavailable or charged, stop that part of the pipeline and use offline/local execution rather than incur fees.
