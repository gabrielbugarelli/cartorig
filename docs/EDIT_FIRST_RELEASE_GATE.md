# CartoRig Native Edit-first — integration and stability acceptance (Resolve Studio 20)

## v0.3 blank-map and user-directed animation changes

The new default generator loads `data/default-map.cartorig-native.json`: world camera (0/0, zoom 1.3), no keys, routes, markers or highlighted countries. The Brazil/Venezuela sample is **not bundled**; it remains a repository-only optional fixture. The Inspector uses native camera controls by default, with imported JSON camera keys explicitly opt-in.

The user can select two ISO3 territories, keyframe highlight opacity, enable a manual route with native keyframe-able geographic endpoints and reveal, and override RGB map colors. Regression tests include the neutral map at frames 0/96/239 and simulated-host interaction. See [practical guide](EDIT_FIRST_MANUAL_WORKFLOW.md).

The SHA in the Inspector must correspond to the **source PR head** after this version, even when CI builds a temporary PR merge commit. Existing explicitly imported/embedded scenes are not erased on upgrade. Testing a fresh generator is necessary to verify changed defaults.

**All these new UI controls need Resolve Studio 20 acceptance; the compiled C++ model and simulated OpenFX host are not substitutes for user testing.**


## Scope and evidence

This development phase targets the five items requested after the first in-host map stabilisation:

1. Correct premultiplied and unpremultiplied RGBA composition
2. Functional Overlay *Filter* on existing video (not a standalone clip)
3. Native Edit keyframe-able camera and route controls, scene time offset and reverse/hold
4. Portable project persistence of embedded scene JSON and optional embedded GeoJSON
5. Regression, concurrent seek/tile/1440p/4K tests, safe Windows upgrades and project-reopen acceptance

**Implemented in code and automated tests** does not mean **passed in DaVinci Resolve Studio 20**. The original map generator and seam fix were user-validated on Resolve 20 on 2026-11-06. This *new* phase, including Overlay, alpha, embedded-string host UX and project persistence, still requires the host acceptance checks below. CI uses a simulated OpenFX host; it does not run Resolve or the Deliver page.

## Architecture and data contracts

- `cartorig::Surface` carries its own `premultiplied` association. The renderer performs source-over blending correctly for both association modes and for RGBA8/RGBA Float32.
- `copySurface(source, output)` preserves existing video, converts association/depth if necessary, handles negative row strides and a cropped `RenderWindow`, and avoids clearing a strictly identical in-place buffer.
- Generator output and Filter output request **premultiplied** output. The Filter also requests RGBA source/output components. The host-reported association on actual images overrides the request if the host provides it.
- The Filter copies source footage, makes ocean transparent, then paints land, highlights, borders, markers and routes with global opacity. Filter default opacity is 0.7; Generator default is 1.0. At opacity 0, the Filter must be a pixel-identical pass-through.
- The plain C++ map renderer does **not** require PNG export or access to Fusion nodes for evaluation.
- `EmbeddedSceneJSON` and `EmbeddedCatalogJSON` are persistent OpenFX multiline text parameters; if non-empty, each takes precedence over `SceneFile`/`CatalogFile`. Scene JSON is capped at 2 MiB and GeoJSON at 16 MiB. If both inline and external are blank, the bundled neutral scene and country dataset are used. Host project serialization of multiline data is specified by OFX, but **Resolve 20 support must be tested in a saved/reopened project**.
- `UseSceneCamera=false` by default; set it to true explicitly to evaluate imported JSON camera keys. Animate the OFX Longitude, Latitude, Zoom and Bearing controls in the Edit Curve Editor. `RouteProgress=-1` uses JSON route timing; values 0–1 use native OFX keyframes. `SceneTimeOffset` and `SceneTimeScale` transform the evaluated scene frame: `(hostFrame-offset)*scale`, so 0 freezes and negative values reverse. Inspector camera parameters remain sampled at host time.
- Existing projects: explicitly imported/embedded scenes remain intact; the new bundled default intentionally changes from an animated demonstration to a static neutral map. Other parameters retain prior behavior where feasible (`SceneTimeOffset=0`, `SceneTimeScale=1`, blank embedded assets). The OpenFX plugin ID is unchanged; the version is advanced to 0.2-dev. Built-in country dataset is still distributed alongside the plugin.
- The Inspector shows `Installed plugin build`, making it easier to distinguish stale OFX binaries.

## Automated tests and CI gates

| Test | Required behavior |
|---|---|
| `cartorig_core_suite` | Geometry, dateline, route, RGBA8/float finite and deterministic |
| `cartorig_alpha_overlay_composition` | Straight/premult RGB over, source conversion, negative stride, global opacity 0 and partial tiles |
| `cartorig_ofx_pixel_layout` | Reject unsupported component/pixel depth layouts; narrow Resolve 20 Float4 compatibility |
| `cartorig_ofx_simulated_host` | Actually loads the binary, creates Generator and Filter, inspects clip preferences, renders embedded scene, simulates persistence and keyframes, overlays mock video and preserves input |
| `cartorig_stability_random_seek_tiles_1440p` | Deterministic arbitrary seeks, reverse/hold retiming, 3×3 tiles equal full frame, parallel render calls and 2560×1440 |
| `cartorig_ofx_abi` | Loads binary and verifies exported OpenFX descriptors |
| CI preview | Creates reference frames 0/96/239 plus 1440p and 3840×2160 4K |
| Sanitizers | ASan and UBSan on Linux for all compiled core and simulated-host tests |
| Windows install | PowerShell AST parse and `-WhatIf`, valid `Contents/Win64/CartoRigNative.ofx` layout |

Do not interpret timing on a GitHub runner as a guaranteed frame-rate target. CPU renderer, memory and caching are separately assessed before production.

## Resolve 20 manual host acceptance (pending)

Use a **disposable project**; write down exact Resolve 20.x build, Windows build, GPU/driver, frame rate, resolution, plugin SHA (Inspector label) and any render-cache setting.

1. **Install:** Close Resolve, extract `CartoRigNative-Windows`; elevated PowerShell run `./Install-CartoRigNative.ps1 -Upgrade -Confirm:$false`. Restart Resolve, confirm `CartoRig Map (Edit)` and `CartoRig Overlay (Edit)` in OpenFX.
2. **Generator regression:** Add Map to V1 on an empty timeline, return to `Normal map`. Test frames 0, 96, 239 and looping playback; verify no horizontal stripes. Test diagnostic RGB bars and go back to Normal.
3. **Source overlay:** Place a normal video clip on V1. **Select that clip and apply `CartoRig Overlay (Edit)` as an OpenFX Filter** using Effects Library double-click or drag onto the clip, not onto an empty track. Verify real footage appears through transparent ocean. Test `Cartography opacity` 0, 0.5 and 1. Check opacity 0 is visually indistinguishable from the original clip.
4. **Alpha:** Put an opaque color/footage on V1 and a Map Generator with a custom scene whose `style.transparent=true` on V2. Check ocean transparent, highlight alpha edges clean (no bright/dark fringe). Repeat over black, white and a moving video; test 8-bit and float project modes where accessible.
5. **Camera/Curve Editor:** Turn off `Use camera keyframes from scene`. Animate Longitude, Latitude, Zoom, Bearing with Edit-page keyframe buttons, edit Bézier handles using the native Curve Editor and confirm intermediate values at frames 0, 40, 90 and 120.
6. **Routes:** Set `Route reveal` to 0, keyframe to 1 then back to 0. Edit its native curve. Restore `-1` for JSON route timing. Confirm no coordinate jumps during playback, reverse, trimming and retiming of the clip.
7. **Scene-time controls:** Change `Scene time scale` from 1 to -1 and 0 (reverse/hold); use positive offset to shift when route appears. Seek in random order and return to the same frame; verify identical output.
8. **Persistence:** Paste a *small* custom scene into `Embedded scene JSON (portable)`, set an external `Scene .json` path to something deliberately unrelated, and verify embedded scene takes precedence. Do likewise for a small custom FeatureCollection in `Embedded GeoJSON`. Save project, close Resolve, reopen, verify strings/controls and output identical. Duplicate the clip and change the duplicate only. Move the project to a second workstation with plugin installed; no external asset should be required for the embedded test.
9. **Offline data fallback:** Clear both embedded fields and both external paths; verify the static neutral map appears with no automatic camera/route animation. An explicitly imported older scene still loads, but the sample is no longer the default.
10. **Export:** Test 1920×1080 and 2560×1440 in Deliver to a supported codec, inspect frames 0/96/239, compare Viewer appearance. Repeat 3840×2160 with playback/cache. Check output alpha only with a codec/workflow that actually preserves an alpha channel.
11. **Cache:** Play, seek, duplicate Map and Overlay clips, save/reopen, enable/disable Render Cache, change scene-time parameters. Confirm frame changes are not incorrectly cached and separate clip instances do not leak state.
12. **Load:** Duplicate/animate at least 20 independent map clips, random-seek for 10 minutes at 1080p, then export 4K sample. Monitor VRAM/RAM, GPU/CPU, crashes and hang. Record quantitative results, not merely PASS.
13. **Failure modes:** Invalid JSON, missing external file, unsupported image depth, extremely short video, source with nontrivial alpha, custom GeoJSON with antimeridian polygon. Expected: recoverable effect failure, not Resolve crash.

Mark each host test **PASS / FAIL / BLOCKED / NOT RUN** with image/video/log evidence. All manual checks are **NOT RUN** until verified in Resolve.

## Important limitations remaining

- No custom on-Viewer geographic picking/handles, advanced typography, XYZ tiles, 3D globe/terrain, full dynamic object Inspector or all 465 legacy features in this phase.
- Multi-line parameter host support and project serialization can only be certified inside Resolve.
- The Filter is an OpenFX effect applied to an existing clip; no standalone `Overlay` media item will appear on an empty timeline.
- Standalone 4K render and host-simulated export are not a real Resolve Deliver render. No automatic E2E on installed Resolve or screen-driven usability automation was performed in CI.
- CPU render performance and alpha under Resolve color-management require real-host measurements. Keep PR as draft until approved.
