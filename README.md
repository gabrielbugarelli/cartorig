# CartoRig — Fusion rewrite (engineering preview)

New codebase aligned to `CR-PS-2.0`: Fusion is the authoring host, `Scene` is a UIManager window, native Fusion Inspector and Spline own property animation. **No legacy CartoRig implementation code is included.** Natural Earth data assets are public domain, not legacy application code.

## Current functionality

- Scene model: typed objects, stable IDs, independent styles, CRUD, groups, route editing, locks, draw order, follower dependency checks, safe snapshot/revert.
- Motion **planning** for all 16 proposed presets with independent channel conflicts, frame bounds, instant color changes and deterministic keyframe plans. These plans are not all wired to the Fusion Inspector yet.
- Offline GeoJSON catalog and a lazy-loading indexed 10m data format with search, administrative polygon/point distinction, alias and accent matching, plus equirectangular camera, antimeridian splitting, route samples, polygon hole semantics and Fit calculations.
- Scene persistence using non-executable JSON via Fusion Composition metadata.
- Fusion adapter (experimental): create Background/Camera, create a Region with native polygon mask, bind RGB keys to BezierSpline, select object in FlowView. Needs real Resolve Studio 20 host test.
- Script entry `fusion/CartoRig Scene.lua` with Scene window (initialize, search, Add Region, reveal selected object). This is a limited preview, **not** the full UI.
- Windows preview installer and uninstall script; does not change older plugin branches.

## Data limitations

The included GeoJSON is an **178-feature Natural Earth Admin-0 1:110m preview**. It is not a complete 10m pack. Official Natural Earth 10m Admin-0/Admin-1/populated places/land/coast/lakes/boundary data are converted by the separate `build-natural-earth.yml` workflow. Its initial seven-family build passed in GitHub Actions; a new indexed/lazy-loading revision has its own tests and requires a fresh workflow pass. The full data pack is a build artifact, not included in this small repository source snapshot. To make it available to the preview installer, place the downloaded artifact contents in `dist/natural-earth-10m/` before installation. User runtime never fetches data. No municipal boundary is fabricated from a city point.

## Local tests

```sh
for test in tests/test_*.lua; do texlua "$test" . || exit 1; done
```

The automated workflow installs Lua 5.4 and additionally parses every source Lua file, validates GeoJSON SHA256 and executes all test files. See `docs/QA_STATUS.md` for precise evidence limits.

## Windows integration preview

1. Extract the full source tree and close DaVinci Resolve.
2. Run `packaging/Install-CartoRig.cmd` from that extracted tree.
3. Restart DaVinci Resolve Studio 20, put a Fusion Composition in a test project, open Fusion.
4. Run `CartoRig Scene` under Scripts. Click **Initialize Map Scene** in an empty Fusion Composition.
5. Search a country such as Brazil, select the country and click **Add as Region**; select it in Scene and click **Reveal in Fusion**.
6. On error, consult `%TEMP%\CartoRig_Rewrite_v2.log` and the Resolve Console. Do not use this preview on an irreplaceable project.

**No guarantee of working native polygon parsing or correct image output is claimed until Resolve host testing.** The scene window is independent from rendering, but its interaction with Resolve has not been verified.

## Missing product requirements

The complete Control/Motion Inspector UX, all 16 *executing* presets, full-resolution geography, city/marker/label/route host tools, style overrides in the Inspector, safe arbitrary host node coexistence, 4K renderer optimizations, GUI installer, migrations, and QA-01…QA-60 are not yet complete.

## Specification governance

The v2 document is the immutable functional reference for this rewrite, not a performance claim. No arbitrary UX change will be silently introduced to accommodate implementation shortcuts. This repository branch is pre-release engineering work.
