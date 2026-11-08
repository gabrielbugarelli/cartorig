# CartoRig — Fusion rewrite (engineering preview)

Fresh source code aligned to `CR-PS-2.0`: `Scene` owns structure in UIManager; the Fusion host owns keyframes and render evaluation. This is a **pre-release prototype** and is **not host-certified** on DaVinci Resolve Studio 20.

## Implemented and covered by automated contract tests

- Canonical Scene: typed objects, stable IDs, styles, CRUD, group and follower reference validation, draw order, locks, copy/snapshot.
- Safe Scene authoring orchestration: initialize, add Region, Marker, Label or Route, persist back into Fusion Composition metadata, and remove only the newly-created CartoRig nodes when an operation fails before commit.
- Offline GeoJSON search/index: country/state/city distinction, Unicode/aliases, on-demand point and polygon geometry loading. A City with point geometry does not become an invented municipal polygon.
- Native Fusion authoring adapter: Background/Transform/MediaOut base **preview**, Region via PolylineMask, Marker via EllipseMask, Label via TextPlus, Route via PolylineMask, each with a separate user-facing tool and a shared downstream Transform.
- Native motion-key writer for currently backed channels: Region color/opacity, Marker opacity/size, Label opacity, Route opacity/Draw Progress, Camera Zoom and synchronized Center/Zoom. The 16-preset **plan catalogue** is separately unit-tested. Presets requiring region stroke/highlight, follower, and multiple base layers fail safely until the corresponding renderer and Inspector integration exist; no fictitious success.
- Offline route sampling, curved paths, geographic camera-fit math, antimeridian math and topology predicates independent of Fusion.
- Fusion UIManager Scene bootstrap supports initialization, typed search/filter, adding Regions, Markers, Labels, choosing explicit Route endpoints, creating Routes and selecting a node in the Fusion Inspector.
- No network or external process is required for playback of *already-created native Fusion nodes*; the Scene window is not the render engine.

## Explicit preview limitations

1. **The full `Control`/`Motion` pages in the Fusion Inspector are NOT implemented.** Native tool inputs are editable but do not represent the final object-specific Inspector design. The Scene window does **not** create an extra animation timeline.
2. **Renderer is NOT production-complete.** Base Map currently starts with a flat Background preview; native Region masks do not support polygons with interior holes, high-fragmentation geometry or seam-crossing boundaries. Such input fails with a diagnostic instead of rendering inaccurately. Lines that cross the antimeridian are rejected until a proper geometry-splitting renderer is installed.
3. **Screen-space marker/label/route widths are not preserved under the downstream Transform's zoom.** This is a known limitation of the interim graph; final geoanchor and compositing needs a projection-aware render layer.
4. **Not all 16 presets execute.** The 16 planner definitions exist; only channels with native tool bindings are written, with host behavior subject to validation. No claim of Step interpolation, shape masks or full Spline compatibility on Resolve 20 is made until a real host run.
5. Current bundled data are a **Natural Earth Admin-0 1:110m preview**. The official build workflow can produce a separate 10m archive; it must be installed and tested before claiming the R1.0 catalogue.
6. Existing comp with arbitrary user-owned graph is intentionally not modified by the preview initializer: use an empty Fusion Composition. Preserve-user-graph handling remains open.
7. All Windows UI Manager and Fusion tool behavior requires testing on a real Resolve Studio 20 installation. Mock-host tests and green GitHub Actions do not satisfy the spec's QA-01…QA-60 or HOST-01…HOST-10.

## Tests

```sh
for test in tests/test_*.lua; do lua5.4 "$test" . || exit 1; done
python -m unittest discover -s tests -p 'test_*.py'
```

`.github/workflows/ci.yml` runs Lua 5.4 syntax, all Lua contract tests and preview dataset hash/integrity checks. Source is explicitly classified as engineering preview, with separate host evidence status in `docs/QA_STATUS.md`.

## Windows integration (experimental)

1. Download the **entire branch**; close DaVinci Resolve.
2. Run `packaging/Install-CartoRig.cmd` from the extracted branch root.
3. Restart Resolve 20 Studio, insert a fresh Fusion Composition on a **disposable project** and open the Fusion page.
4. Run `CartoRig Scene` from Fusion Scripts. Click `Initialize Map Scene`.
5. Search for a country (for example Brazil), select `Country`, click `Add as Region`. For a city point, use `Add Marker` or `Add Label`. To make a Route, choose two explicit City points with `Route From` / `Route To`, then `Create Route`.
6. Click an object in Scene to select its corresponding native tool in the Node Editor/Inspector. Fusion native controls can be inspected and manually animated; the complete contextual `Control / Motion` pages are future implementation work.
7. Errors: inspect `%TEMP%\CartoRig_Rewrite_v2.log` or Resolve's Console.

This code does not inherit prior CartoRig implementation branches. The v2.0 specification remains the product contract, not a claim of implemented features.
