# CartoRig Native — Edit-first OpenFX developer preview

## Natural Earth complete offline backend (active development)

The [Natural Earth integration](docs/NATURAL_EARTH_OFFLINE_BACKEND.md) audits the complete 215-layer pinned vector source (182 official aggregate GeoPackage layers plus 33 SHA-verified supplements), implements an offline SQLite FTS5/RTree search catalog and a native C++ geometry decoder. It also provides **opt-in local Natural Earth country rendering inside the OpenFX effect** at 110m / 50m / 10m, with native data load and rendering verified by CI on the real publisher GeoPackage.

**This is a v0.4.0 developer preview, not a complete Natural Earth installation.** Raster variants, the large offline data installer, other physical/cultural map-layer rendering, Geographic Region search Inspector, independent region colors, and real DaVinci Resolve 20 acceptance are still outstanding. No network call is introduced in the plugin runtime. See [Edit integration test guide](docs/NATURAL_EARTH_EDIT_BRIDGE.md).


**Status: developer preview v0.4.0.** The Map Generator and its antimeridian rendering fix have been validated by a user in DaVinci Resolve Studio 20. The new Overlay/alpha, persistence, keyframe/retime controls and 4K pipeline still require formal in-Resolve acceptance.

This repository is a new, independently compiled C++ project. It does not require Electron, SVG screenshots, `fuscript.exe`, the Workflow Integration bridge or the Fusion page for normal image generation.

## Edit-first: blank map and user-authored animation (0.3-dev)

**New maps no longer load the Brazil–Venezuela demonstration.** The bundled default is `data/default-map.cartorig-native.json`, with a static world camera, no camera keys, highlights, markers or routes. The old demonstration exists only as an optional repository sample, not inside the OFX bundle. Existing custom scenes are not overwritten.

The Edit Inspector now exposes editable ISO3 country highlights, animated highlight strength, a user-enabled route with editable endpoints/curvature/width, marker labels and visibility, optional RGB palette overrides, plus the camera/opacity/retiming controls. **No keyframes are authored automatically.** Details and an exact Resolve 20 test flow: [Manual Edit-first workflow](docs/EDIT_FIRST_MANUAL_WORKFLOW.md).

The Inspector build tag now identifies the *source commit* rather than the temporary GitHub Actions pull-request merge commit.

## Integration and stability phase (0.2-dev)

- **Generator + Filter:** source-over compositing of geographic graphics on live video with alpha-aware 8-bit/Float32 premultiplied pipelines, global opacity, clean transparent ocean for Overlay, validated CPU pixels and source-preserving `Opacity=0`.
- **Native Edit animation:** keyframe-able camera/route knobs plus `SceneTimeOffset` and `SceneTimeScale` (reverse/hold). Use the Edit Curve Editor for the OpenFX-exposed controls; no built-in HTML timeline.
- **Portable data:** `EmbeddedSceneJSON` and `EmbeddedCatalogJSON` are persistent OFX multiline string params. Values stored there override external file paths and can survive project transfer *if the Resolve host persists them*, subject to the manual test gate.
- **Tests:** real plugin loaded inside a simulated OpenFX host for Generator/Filter, pixel-level alpha/overlay tests, parallel seeks and tile equivalence, 1440p/4K previews, Windows installer dry-run and sanitizer tests.
- **Windows upgrades:** from the Windows GitHub Actions artifact, run `./Install-CartoRigNative.ps1 -Upgrade -Confirm:$false` in elevated PowerShell with Resolve closed. The script stages the bundle and keeps a rollback copy during the switch. `-WhatIf` performs no installation.

The verified current features and required **manual Resolve 20** checks are documented in [Edit-first release gate](docs/EDIT_FIRST_RELEASE_GATE.md).

## What exists today

- Two OpenFX Image Effect entry points: `com.cartorig.native.map` (Generator context) and `com.cartorig.native.overlay` (Filter context).
- Bundled offline country polygons, parsed as GeoJSON Polygon/MultiPolygon, with country IDs used to highlight selected countries.
- Native 8-bit and float RGBA pixel renderer with OpenFX render windows, row-byte strides and per-pixel alpha blending; byte and float tests.
- Web Mercator camera, geographic pan/zoom/bearing, geographic point projections and inverse projections, fit-to-bounds, shortest-path dateline keyframe interpolation.
- Country fill, borders, polygon holes, markers and ASCII bitmap labels, quadratic Bézier routes with reveal by approximate arc-length and arrowheads.
- Scene JSON v1 with input limits, version validation, camera keys, route time windows and style palette. Camera coordinates/zoom/bearing and route reveal/opacity are also exposed as OFX keyframe-capable parameters.
- Neutral built-in world map (no auto-animation). Optional Brazil/Venezuela example remains in the repository for explicitly requested tests, never in the installer bundle. CMake, cross-platform CI, native simulated-host tests and static preview regression checks.

## Important limitations

**This is the first functional vertical slice, not the completed 465-requirement product.** The following are **not implemented or not validated**: true edit-on-Viewer geographic selection (OpenFX Interacts); online search, tile XYZ, vector label shaping, full Unicode, independent keyframe track per dynamically created territory, unlimited live object inspector, editable route handles/waypoints, full animation parity, Undo/Redo integration with changing external scene files, 3D terrain/globe, GPU backend, HDR color pipeline, hosting tests inside Resolve Studio 20, final UX studies and certification. The map can be edited via scene JSON and exposed OFX controls, but no custom dockable GIS panel exists.

**OpenFX Generator support in the Edit-page Effects Library must be confirmed in a real Resolve 20 installation.** The filter remains an alternative entry point if the host does not expose generator context. These two contexts are not declared equivalent or guaranteed in Resolve.

## Build (CMake + C++17)

Windows 11 with VS 2022 C++:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
```

Linux (build verification, not a Resolve 20 certification):

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

Bundle output: `build/CartoRigNative.ofx.bundle/Contents/Win64/CartoRigNative.ofx` on Windows or `Contents/Linux-x86-64/CartoRigNative.ofx` on Linux, with `Contents/Resources` containing the licensed country dataset and neutral default scene. Both OpenFX entries are contained in **one binary**. The standard OFX API headers are vendored, not Blackmagic proprietary headers or binaries.

## Install and remove (Windows)

Close Resolve. Use PowerShell **as administrator** and inspect the script before running:

```powershell
.\packaging\Install.ps1 -Confirm:$false
# after testing
.\packaging\Uninstall.ps1 -Confirm:$false
```

`Install.ps1 -WhatIf` previews the destination without modifying it. Installation refuses to overwrite an existing bundle; uninstall deletes only the CartoRig Native bundle, never external projects/scenes. Default install path: `%ProgramFiles%\Common Files\OFX\Plugins\CartoRigNative.ofx.bundle`.

Restart DaVinci Resolve Studio 20. If the Generator is supported, search for **CartoRig Map (Edit)**. For a video layer, apply **CartoRig Overlay (Edit)** as OpenFX. New maps are neutral by default. Optional custom scene files should be project-owned; use **Scene .json** or **Embedded scene JSON** in the Inspector when needed.

## Inspector parameters

| Parameter | Meaning |
| --- | --- |
| Scene .json | Blank uses bundled static world map (no animation); otherwise a file path |
| GeoJSON | Blank uses bundled offline countries; otherwise GeoJSON FeatureCollection |
| Use camera animation from imported scene | **Disabled by default.** Activate only for explicitly imported JSON camera tracks |
| Camera longitude / latitude / zoom / bearing | Keyframe-capable native OFX parameters when JSON camera keys are disabled |
| Route reveal | Defaults to 1 (entire route when manually enabled); animate 0→1 to draw; -1 opts into JSON timing |
| Cartography opacity | Global opacity for all map paints, including Filter overlay (default 0.7) |
| Embedded scene JSON | Portable in-project scene; overrides external scene file |
| Embedded GeoJSON | Portable in-project data; overrides external GeoJSON |
| Scene offset / time scale | Shift, freeze and reverse JSON camera/route animation |
| Country 1 / Country 2 / More countries (ISO3 list) | Blank initially; user chooses one, two or multiple territories to highlight |
| Highlight opacity | Animatable strength for user-selected countries |
| Enable manual route | Disabled initially; creates editable route only on request |
| Start / end longitude and latitude | Keyframe-capable geographic waypoints for the manual route |
| Route curvature / width | Keyframe-capable route styling |
| Show route endpoints / origin and destination labels | Optional user-controlled markers |
| Override map colors and RGB controls | Optional native camera-independent color styling |
| Installed plugin build | Shows the **source commit SHA** (not temporary PR merge) to distinguish binaries |

**No automatic host-scene synchronization:** an external JSON file change may not invalidate a cached host frame until an Inspector parameter changes. Embed assets for project portability, or explicitly refresh the host when editing external files.

## Preview without Resolve

```bash
./build/cartorig_preview data/countries.geojson data/default-map.cartorig-native.json 96 ./frame.ppm 3840 2160
```

A PPM is produced for engineering tests only; this is **not** a pre-render requirement in the actual OFX runtime.

## Resolve 20 host compatibility — ComponentNone RGBA Float4

Initial host logs conclusively showed the generator output allocation was reported as `OfxBitDepthFloat` with `OfxImageComponentNone`, but stride matched 4×32-bit channels (1920×16). This invalid metadata made the render callback reject every frame. The plugin now explicitly requests `Output=RGBA` from clip preferences and supports a **strict** opt-in internal compatibility path for this exact Generator Float4 allocation. This remains under real-host validation; it does not imply arbitrary ComponentNone buffers are valid. See [diagnostics](docs/RESOLVE20_DIAGNOSTICS.md).

## Resolve Studio 20: image corruption diagnostics

The initial image corruption and moving horizontal stripes were addressed by output RGBA negotiation and continuous longitude polygon projection; the Map Generator was subsequently confirmed stable in a first actual Resolve 20 test. The newly added Filter and project persistence workflows are **not yet host-certified**. The Inspector now exposes **Diagnostic output (test only)** (RGB bars, grayscale, alpha split, white) and an opt-in **Write OFX diagnostic log**. Run the controlled [Resolve 20 diagnostic procedure](docs/RESOLVE20_DIAGNOSTICS.md) before proposing another pixel-format fix.

## Tests and safety

`cartorig_tests` exercises parsing, world-data lookup, holes, projection/inversion, dateline motion, keyframe interpolation, route progression, memory canaries around tile buffers, byte/float range checks, and deterministic rendering. `cartorig_ofx_exports_tests` dynamically loads the compiled binary and verifies both OFX descriptors and the no-host safety path. CI also compiles the actual OpenFX binary on Linux and Windows and generates reference PPMs. None of these substitute for Resolve Studio 20 E2E acceptance tests; see [docs/RESOLVE20_ACCEPTANCE.md](docs/RESOLVE20_ACCEPTANCE.md).

## Links

- [Engineering gates and remaining scope](docs/STATUS.md)
- [Manual Resolve Studio 20 acceptance protocol](docs/RESOLVE20_ACCEPTANCE.md)
- [Requirements traceability](docs/TRACEABILITY.md) and [all 551 original IDs](docs/REQUIREMENTS_MATRIX.csv)
- [OpenFX specification](https://openfx.readthedocs.io/en/main/)
- [Country data attribution](data/LICENSE-COUNTRYINFO.txt)
- [Third-party dependencies](third_party/NOTICE.md)

All implementation is independent of Blackmagic proprietary binaries and third-party map tool code. Copyright for datasets and libraries remains with their respective licensors.
