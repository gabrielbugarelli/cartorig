# CartoRig — Fusion rewrite (engineering preview)

Fresh source code aligned to `CR-PS-2.0`: `Scene` owns structure in UIManager; the Fusion host owns keyframes and render evaluation. This is a **pre-release prototype** and is **not host-certified** on DaVinci Resolve Studio 20.

## Implemented and covered by automated contract tests

- Canonical Scene: typed objects, stable IDs, styles, CRUD, group and follower reference validation, draw order, locks, copy/snapshot. The UIManager preview now connects Rename, Hide/Show and Lock/Unlock commands for authorial objects to persisted Scene metadata. Hide/Show updates only the owned object composite Blend and reverts on metadata failure; it does not erase native keyframes.
- Safe Scene authoring orchestration: manifest-pinned source protection, initialize, add Region, Marker, Label or Route, persist back into Fusion Composition metadata, and remove only the newly-created CartoRig nodes when an operation fails before commit.
- Offline GeoJSON search/index: country/state/city distinction, Unicode/aliases, on-demand point and polygon geometry loading. Natural Earth country continent attributes are indexed as explicit **composite search results**, not fabricated administrative continent polygons; member-country IDs remain auditable. A City with point geometry does not become an invented municipal polygon.
- Native Fusion authoring adapter: white Background + CartoRigBase Fuse/Transform/MediaOut **preview**, Region via native PolygonMask matte + CartoRigRegion Fuse, Marker via EllipseMask, Label via TextPlus, Route via PolylineMask, each with a separate user-facing tool and a shared downstream Transform.
- Native motion-key writer for currently backed channels: Region color/opacity/highlight, Base Map ocean layer opacity, Marker opacity/size, Label opacity, Route opacity/Draw Progress, Camera Zoom and synchronized Center/Zoom. Zoom-only Camera keys now pair native Size/Center poses to retain the WGS84 focal point at the keyed frames and block overwrites of an already-animated manual Center. The 16-preset **plan catalogue** is separately unit-tested. Presets requiring region stroke/highlight, follower, and multiple base layers fail safely until the corresponding renderer and Inspector integration exist; no fictitious success.
- Offline route sampling, curved paths, geographic camera-fit math, antimeridian math and topology predicates independent of Fusion.
- Fusion UIManager Scene bootstrap supports initialization, typed search/filter, adding Regions, Markers, Labels, choosing explicit Route endpoints, creating Routes and selecting a node in the Fusion Inspector.
- No network or external process is required for playback of *already-created native Fusion nodes*; the Scene window is not the render engine.

## Authorial Region and Base Map Fuses (Fusion host gate)

`fuses/CartoRigRegion.fuse` is now inserted into every newly created Region in the
engineer's preview graph. Each Region's opaque/transparent **white geographic
matte** (including separate outer island polygons) feeds one authorial
`CartoRigRegion` node. Its `Control` Inspector page exposes a grouped Fill
color picker, Object Opacity, Highlight Color and Highlight Strength. A `Motion`
page presents **cloned inputs referring to the same native numeric channels**
for Opacity and Highlight. The Fuse applies color/opacity/highlight using
premultiplied RGBA: no UIManager color cache is used when evaluating frames.

The host writer now maps native Region `FillRed/Green/Blue`, `ObjectOpacity`
and `HighlightStrength`; tested presets include Color Transition, Fade and
Highlight Pulse. The metadata and graph builder assign one authorial tool
per Region and still fail safely for geographic holes/antimeridian or other
unsupported geometry. **This is not a full cartographic renderer:** Stroke,
Border Draw, rings with holes and high-resolution topology remain open.

`fuses/CartoRigBase.fuse` is the **ocean-only** initial base preview with
`Control` inputs for `Full Map` / `Transparent Overlay`, Ocean Fill, Base
Opacity and Ocean Layer Opacity. Switching overlay makes the background
RGBA fully transparent without deleting layer metadata or authorial objects;
the Ocean Layer Fade can use native Fusion splines. **Land and Borders are
not yet rendered by this Fuse** and their presets still fail closed.

Both new Fuses are installed by the preview Windows installer. A missing
`CartoRigRegion` or `CartoRigBase` tool aborts creation and rolls back
newly-created CartoRig nodes rather than rendering an inaccurate substitute.
Their `Create()` and `Process()` callbacks and graph integration have automated
mock tests; rendering, CloneInput and Spline behavior in Windows Resolve Studio
20 remain explicitly unverified.

## Experimental Inspector controls (Fuse host gate)

`fuses/CartoRigOpacity.fuse` is a new, functional pass-through image-processing Fuse with **Control** and **Motion** Inspector pages. `Control → Object Opacity` and `Motion → Fade Factor` are separate native numeric inputs; their product multiplies premultiplied RGBA in `Process(req)`. Both channels are intended to be manually keyframeable in the native Spline Editor. This is a **host-gated prototype**, not the completed object-specific Inspector or a catalog preset launcher. It is installed in the per-user Fusion Fuses folder by the preview installer, and can be tested as `CartoRig Opacity (Experimental)` on a copy of a Fusion composition. The test harness mocks the Fuse SDK callbacks; **actual loading/rendering/keyframing in Resolve 20 is NOT YET VERIFIED**.

## Explicit preview limitations

1. **The full object-specific `Control`/`Motion` pages in the Fusion Inspector are NOT implemented.** Region and Base Map have partial native Fuse pages; Route, Marker, Label and Camera still need complete pages. Native tool inputs are editable but do not represent the final object-specific Inspector design. The Scene window does **not** create an extra animation timeline.
2. **Renderer is NOT production-complete.** Base Map currently starts with a flat Background preview; native Region masks do not support polygons with interior holes, high-fragmentation geometry or seam-crossing boundaries. Such input fails with a diagnostic instead of rendering inaccurately. Lines that cross the antimeridian are rejected until a proper geometry-splitting renderer is installed.
3. **Screen-space marker/label/route widths are not preserved under the downstream Transform's zoom.** This is a known limitation of the interim graph; final geoanchor and compositing needs a projection-aware render layer.
4. **Not all 16 presets execute.** The 16 planner definitions exist; only channels with native tool bindings are written, with host behavior subject to validation. No claim of Step interpolation, shape masks or full Spline compatibility on Resolve 20 is made until a real host run.
5. A saved scene records a fingerprint of its installed Natural Earth dataset; if the installed data change, CartoRig blocks source-dependent edits instead of silently replacing geometries. Current bundled data are a **Natural Earth Admin-0 1:110m preview**. The official build workflow produces a separate 10m data archive and a **single offline Windows preview bundle** containing editor code, Fuse, installer and the seven 10m datasets, with SHA-256 validation. This is still not a certified R1.0 catalogue or GUI installer.
6. Existing comp with arbitrary user-owned graph is intentionally not modified by the preview initializer: use an empty Fusion Composition. Preserve-user-graph handling remains open.
7. All Windows UI Manager and Fusion tool behavior requires testing on a real Resolve Studio 20 installation. Mock-host tests and green GitHub Actions do not satisfy the spec's QA-01…QA-60 or HOST-01…HOST-10.

## Tests

```sh
for test in tests/test_*.lua; do lua5.4 "$test" . || exit 1; done
python -m unittest discover -s tests -p 'test_*.py'
```

`.github/workflows/ci.yml` runs Lua 5.4 syntax, all Lua contract tests and preview dataset hash/integrity checks. Source is explicitly classified as engineering preview, with separate host evidence status in `docs/QA_STATUS.md`.

## Offline Windows preview bundle from GitHub Actions

Run `.github/workflows/build-natural-earth.yml` on the rewrite branch (or retrieve the latest successful PR run) and download `CartoRig-Fusion-Preview-Windows-With-NaturalEarth-10m`. It includes `packaging/Install-CartoRig.cmd`, `fusion`, `fuses`, `src` and all installed datasets under `data`. The **entire** bundle is usable without additional download at editor runtime; SHA256 is checked at packaging time. Always extract the entire artifact before running the installer. The data pack workflow may take substantial CI time due to the official Natural Earth downloads.

## Windows integration (experimental)

1. Download the **entire branch**; close DaVinci Resolve.
2. Run `packaging/Install-CartoRig.cmd` from the extracted branch root.
3. Restart Resolve 20 Studio, insert a fresh Fusion Composition on a **disposable project** and open the Fusion page.
4. Run `CartoRig Scene` from Fusion Scripts. Click `Initialize Map Scene`.
5. Search for a country (for example Brazil), select `Country`, click `Add as Region`. For a city point, use `Add Marker` or `Add Label`. To make a Route, choose two explicit City points with `Route From` / `Route To`, then `Create Route`.
6. Click an object in Scene to select its corresponding native tool in the Node Editor/Inspector. Use Rename, Hide/Show or Lock/Unlock from Scene on user-created objects; these commands preserve object IDs and animation. Fusion native controls can be inspected and manually animated; the complete contextual `Control / Motion` pages are future implementation work.
7. Errors: inspect `%TEMP%\CartoRig_Rewrite_v2.log` or Resolve's Console.

This code does not inherit prior CartoRig implementation branches. The v2.0 specification remains the product contract, not a claim of implemented features.
