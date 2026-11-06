# CartoRig Native — engineering status and release gates

Version: `0.1.0-dev`. Target: **DaVinci Resolve Studio 20 / Windows 11 x64 / Edit-first**.

## Implemented in code (not certified in Resolve)

| Module | Present implementation | Remaining risk |
| --- | --- | --- |
| OpenFX image-effects | Both Generator and Filter entrypoints, C API, render callback | Actual Resolve 20 discovery, parameter UI and alpha composition |
| Geometry | GeoJSON Polygon/MultiPolygon, polygon holes, geographic index by ISO3, world dataset | Complex crossing of antimeridian, precise topology, 10k-feature stress |
| Projection | Web Mercator + inversion, bearing, dateline interpolation | Edge cases and 3D projections |
| Camera | Static and JSON keyframes, OFX animatable numerical overrides | Host timebase retime, duration, splines parity |
| Objects | Highlights, geo markers, bitmap ASCII labels, quadratic animated route | Waypoints, point editor, Arabic/UTF-8 shaping, dynamic regions and camera-linked label collision |
| Raster | CPU RGBA byte+float; render tiles / separate rows and stride | Performance, HDR and host premultiplication/clip preference negotiation |
| Persistence | Strict JSON version and limits; file-path source, asset mtime cache | Portable embedded snapshots, project exchange and undo integration |
| Quality | Unit tests, mock-free core render, native builds, CI previews | Host E2E, usability, memory sanitizer, performance profiling |

## Go/no-go validation on Windows Resolve 20

1. **GATE-OFX-01**: resolve discovers `com.cartorig.native.map` and `com.cartorig.native.overlay` without crash.
2. **GATE-EDIT-02**: generator is available from Edit Effects Library, or fallback Edit-first template approach must be implemented.
3. **GATE-EDIT-03**: OFX double params appear in Inspector and can be animated in Edit Keyframe/Curve editor.
4. **GATE-RENDER-04**: alpha, 8-bit and float render are correct over arbitrary image/time ranges and Deliver export.
5. **GATE-PROJECT-05**: project save/open duplicates a clip without corrupting effect parameters; investigate file relocation.
6. **GATE-PERF-06**: 4K production image and seek/retime under memory, cache and latency thresholds.
7. **GATE-UX-07**: test accessibility, parameter names, scene path selection and error messages in Resolve.
8. **GATE-INTERACT-08**: measure the actual OpenFX Viewer Interacts exposed by the host before designing GIS picking.

**No gate is marked passed solely because a C++ unit test is green.**

## Architecture decisions still open

- OFX Generator directly versus Fusion Generator template wrapping an OFX Filter.
- Native overlay interaction support in Edit 20 (API suite query + real on-screen gesture).
- Immutable scene snapshot stored inside plugin parameter versus sidecar file and autosync.
- How to expose thousands of per-object animations given OpenFX immutable parameter descriptors.
- Color linearization, premultiplication, wide gamut/HDR and deterministic 4K.
- Separate GPU renderer (AMD-friendly OpenCL or Vulkan/Metal) after CPU baseline and performance evidence.
- Text shaping (FreeType/HarfBuzz) and collision priorities.
- 2.5D/terrain/3D benchmark and licensed DEM data pipeline.

## Next milestones (not implemented)

- M1: mock OpenFX host and real Resolve 20 manual acceptance, repair any failing callbacks.
- M2: scene portability, hash-based asset manager, GeoJSON/TopoJSON/CSV import workflows, label typography.
- M3: dedicated in-Viewer geographic interactions, route waypoints, richer native animation.
- M4: data visualization + rich styled map layers, caching and GPU acceleration.
- M5: 2.5D/3D terrain/globe by independent host and renderer benchmarks.

**Never** announce full requirement parity, full UX stability or 20.x certification without the explicit test evidence.
