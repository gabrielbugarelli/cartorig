# CartoRig — Fusion-first greenfield 0.2.1 (startup hotfix / functional authoring alpha)

> This is newly written source. It is **not** a port of the earlier CartoRig codebase. This is an implementable **Fusion-native editor**, not an OpenFX Generator or a standalone Electron application.
>
> **Host status:** automated Lua mock tests executed; real DaVinci Resolve Studio 20 validation **not yet performed on the user's workstation**. It is not a certified production plugin or a complete Natural Earth distribution.

## What actually works in the source implementation

- Create or reopen a **managed Fusion Composition** rendered in a single Edit-page clip; never overwrite an arbitrary unrelated comp.
- Generate an offline 2D world base from Natural Earth 110m vector polygons, with separate **Land** and **Ocean** Fill colors.
- Search **177 named countries**, **27 Brazilian states** (Natural Earth 50m Admin1), and **243 populated-place points** (Natural Earth 110m). Search is case/accent insensitive; `Brasil` and `Brazil` both resolve to Brazil. `Rio de Janeiro` matches a State and City, each with a distinct type.
- Add independent **Region** objects with authentic polygon geometry; apply fill RGB and alpha by the **same controls** used by the basemap.
- Add **georeferenced markers** from named city points.
- Create **straight geographic arrows** between named point endpoints; `Amapá — State` requires **explicit confirmation** that the source-provided representative point is the desired destination (not secretly Macapá).
- Key color and opacity of each object independently using **Fusion BezierSpline modifiers** on native Background inputs. The selected object is also selected in Fusion's FlowView.
- Set and key one shared camera Transform for all cartographic layers. Camera and objects use the same global equirectangular projection and downstream transform.
- Create route reveal keyframes using native PolylineMask `WriteLength` and arrowhead `Blend`.
- Reopen a managed scene and list objects from metadata saved **inside the Fusion composition**; do not depend on Qt window state for project persistence.
- Install with a `.cmd` click; normal editing and rendering do not need Python, internet, or a separate application.

## Startup hotfix v0.2.1 (why clicking the menu previously appeared to do nothing)

The older v0.2 entry point called `graph.ensure()` **before showing any window**. That routine creates many Natural Earth Fusion masks and merges. Errors, unsupported mask constructors, and large initialization workloads could therefore prevent the window from ever appearing. The earlier unit tests tested `graph.ensure()` but **never tested actual menu startup**.

v0.2.1 changes the flow:

1. Click **CartoRig Fusion-first** in Fusion: the editor opens first, without creating any nodes.
2. Click **Create Map in this Fusion Composition** explicitly. If map creation fails, the error is shown in the window and written to `%TEMP%\CartoRig_FusionFirst_startup.log`.
3. If the editor still does not appear, run `packaging\Diagnose-CartoRig.cmd` and check `Workspace > Console` in Resolve. A startup trace is logged even if UIManager cannot initialize (provided the entry script runs).
4. If **no startup log** is produced, the launched script may be an old copy, a different scripts folder may be taking precedence, or Resolve did not run the entry point. Inspect `Scripts/Comp` in the installed directory reported by the installer.

This hotfix does **not** certify the Natural Earth mask creation in the real Resolve 20 host; it makes that operation explicit and diagnosable.

## Installation / use (Windows, DaVinci Resolve Studio 20)

1. Download **all files on this branch** (Code → Download ZIP), not a single Lua script. Unzip.
2. Close Resolve and run `packaging/Install-CartoRig.cmd`; it copies the new sources and data into the user Fusion Scripts/Comp directory.
3. Restart Resolve. Insert a **new empty Fusion Composition** into the Edit timeline. Select it and switch to Fusion.
4. Launch `CartoRig Fusion-first` from Fusion Scripts. The editor should open **before any map is built**. Click **Create Map in this Fusion Composition**. The initial vector basemap uses many native mask nodes and may be slow on first creation; errors are displayed in the editor and logged.
5. In **Find location**, search `Brasil`, select `Brazil — Country` and click **+ Region**. The **Objects** panel will show it; select it to select the matching native Fusion Background node.
6. Edit `Fill #` and `Opacity %` using Apply for static values; click **Key @ Playhead** when animating. To change Brazil instantaneously at 30fps: key red at frame 0, key red at 329, key green at 330; or apply Step/Hold interpolation in the **Fusion Spline editor**.
7. Search `Rio de Janeiro`, select **State — Brazil** rather than City and add the polygon. States have independent Fill controls.
8. Search `São Paulo`, select **City**, enter a camera zoom (e.g., 4), click **Focus Camera**, or key a camera pose at playhead. The camera Transform is downstream of all object layers.
9. To draw an arrow, search `Brasília — City` → **From selected location**, search `Amapá — State` → **To selected location** → **Use state representative point** → **+ Route**. Select route object and key 0% / 100% reveal at your chosen playhead positions.
10. Close the window when desired, return to Edit, trim/copy the clip and export with Deliver. The scene and animation are managed by Fusion nodes; the script is for authoring, not runtime rendering.

## Architecture

```text
Edit timeline (1 Fusion Composition clip)
    Fusion:  [Ocean Background]
             + [Land Background] × [Natural Earth Polygon Masks]
             + [Region Background] × [independent Polygon Masks]
             + [Marker Background] × [Ellipse Masks]
             + [Route Background] × [Polyline+Arrowhead Masks]
             → [Shared Transform Camera] → MediaOut → Edit/Deliver
                ^
                |
    CartoRig Lua Qt/UIManager (Find / Objects / Fill / Opacity / Route / Camera)
```

**No second timeline.** The only animated controls are native Fusion inputs/splines; the editor chooses which owned node to inspect, preserving independence. All geography is referenced to a single equirectangular full-world coordinate system before the shared Transform.

## Important honest limitations of the first functional alpha

1. **Not verified on the actual Resolve 20 installation.** `Polyline` input construction, UIManager signal variations, performance, and `WriteLength` behavior require Windows host QA. Unit tests use a substitute Lua host with the same interface contract, not the licensed Resolve application.
2. **No complete Natural Earth.** Countries are 110m, Brazilian states 50m, city points 110m. The much larger raster and full 10m/50m vector families from the earlier research are *not* part of this version. The 110m source is cartographically generalized and not appropriate for city-boundary precision.
3. **Regions containing holes** are rejected with an explicit error rather than filling the holes incorrectly. This is a functionality gap to resolve before production. MultiPolygon outer islands are generated as separate native masks when under the safety budget.
4. **World base performance** is unoptimized: many polygon masks and merges on the first create. A compiled C++ native renderer remains a later optimization subject to actual benchmarks. This source contains no copied legacy OpenFX renderer.
5. **Camera is equirectangular 2D**, not Mercator / globo / 3D. It uses one downstream 2D Transform, so it can zoom and pan but not implement all geographic camera functions of GEOlayers.
6. **Straight routes** do not follow roads. Antimeridian crossing needs a dedicated treatment; current version rejects cross-dateline routes.
7. **Polygons are not freely editable by clicking territory directly in Viewer**; UI selection happens in the Qt tree, then selects Fusion nodes. The mask geometry is represented by Fusion's native polyline tools.
8. **No live Edit Inspector control publication** by design: animations live on the Fusion page. Edit contains the final Fusion Composition clip.
9. Source license: project owner must approve a permissive OSI license prior to public production release. Natural Earth datasets are public domain.

## Quality and non-destructive contracts

- No network required at runtime, no Electron, no mandatory toolchain for the end user.
- All feature ID / source/type metadata saved on managed Fusion nodes.
- An existing comp is never silently destroyed; a new scene refuses non-empty comp with foreign nodes.
- A scene version mismatch or missing camera/layer fails clearly rather than overwriting.
- No demo animation is automatically created.
- Native Fusion properties are the sole source of truth for animation; CartoRig does not simulate a second keyframe store.
- Tests: run `lua5.4 tests/test_runtime.lua .` (or `texlua tests/test_runtime.lua .`) and `python -m unittest discover -s tests -p 'test_*.py'`.

## Explicit owner-approved scope

Fusion-first is approved. This new implementation follows that direction without adding the previous UI's rejected ISO3 picker, menu fragmentation, or preset Brazil↔Venezuela animation. The implementation is an early working codebase, **not a claim that all previously requested features are now complete**.