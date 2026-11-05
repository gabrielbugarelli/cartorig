# Requirements traceability — v0.1.0

The original CartoRig master requirements list `CR-RF-0001..CR-RF-0465`, 42 animation `KF/CAM/GEO/ROUTE/MG` features, `MAP-001..020`, `ADV-001..016`, `ADV-101..108`, and 129 tests. **They are not all implemented.** This file records the current code capabilities and the semantic replacement of Electron UI requirements by native Resolve controls.

- Original GUI: Electron window, HTML map, separate timeline, focus workspace, resizable preview, custom Graph Editor, local IPC, browser QA. These exact implementation requirements are **superseded** by Edit-first OpenFX; their **user outcomes** remain on the backlog unless covered by native host UI.
- Core P0 implemented: offline data, ISO3 highlights, camera projections, keyframe evaluation, geographic markers, simple Bézier routes, native CPU raster, output scene JSON, bundled sample, OpenFX registration and basic OFX parameters.
- Core P0 still open: stable project-portable scene persistence, complete editable country/route object hierarchy, a full geographic Inspector, runtime host capability detection and E2E Resolve validation.
- Animation features: camera multi-key interpolation and route reveal exist in the core; native OFX numerical values are marked animatable; complete KF-04 professional curve editing is **delegated to Edit for OFX-exposed params** and not claimed for hidden JSON tracks. Multi-object keyframing, expressions, retiming, advanced controllers are pending.
- MAP-001/003/004/005/006/008/009/017/020: **partial** standalone/core implementations; native integration tests pending. MAP-002/007/010/011/012/013/014/015/016/018/019: **partial or pending**, none accepted as complete product P0.
- ADV-001: GeoJSON subset Polygon/MultiPolygon supported for offline dataset; Point and LineString imports pending. ADV-002..ADV-016 and ADV-101..ADV-108: pending, apart from foundational calculations and camera.
- Tests: new C++ tests exercise narrow core behaviors, not all 129 original acceptance scenarios. The old 129-case CSV stays a source of intended behavior, not passing evidence in this project.

An [exhaustive machine-readable requirements matrix](REQUIREMENTS_MATRIX.csv) is generated from the original documents archived in [reference/](reference/) using `python tools/traceability.py`. It explicitly records native evidence and backlog state for all 551 unique IDs; the original 129 test scenarios are preserved separately. CI fails on mismatched source IDs or a stale matrix. The legacy implementation flags are never treated as Native acceptance.
