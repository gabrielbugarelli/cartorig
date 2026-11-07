# CartoRig Edit-first authoring MVP — implementation and acceptance
**Date:** 2026-11-07
**Branch:** feat/cartorig-edit-first-mvp
**Product state:** developer preview. Not a full CartoRig 1.0 release.

## Why this architecture
On real DaVinci Resolve Studio 20:
- the OpenFX Generator rendered on Edit, but `TimelineItem.AddFusionComp()` rejected attachment to that OFX Generator;
- a native **Fusion Composition** inserted on Edit **successfully hosted** a CartoRig Overlay OpenFX node and independent Text+/Merge nodes;
- the user manually animated, saved, reopened, replayed, and exported a basic CartoRig map without a failure.

Therefore the product keeps **Fusion Composition → CartoRig native OpenFX Overlay → Fusion MediaOut** as the render container and avoids the rejected reverse ownership architecture.

## Implemented
**Native C++**
- `ObjectLayerOnly` = false by default; legacy Overlay behavior preserved.
- When enabled on an Overlay filter, the C++ renderer copies its incoming pixels and paints *only user-selected country highlights, routes and markers*, not the base land. Unused optional raster and vector base-layer passes are skipped.
- `HighlightR/G/B`, `HighlightStrength` plus existing ISO3 inputs produce independent per-territory layer styles.
- `NativeRouteRed/Green/Blue`, `RouteProgress`, curve and width permit independent route styles/animation.

**Resolve Edit authoring scripts (English UI)**
- `CartoRig - Create Map`: inserts a Fusion Composition on the current timeline with bundled offline map, neutral static camera, colored ocean background and a persistent map-layer output node.
- `CartoRig - Add Country`: resolves a country name or ISO3 locally, picks a color, creates one OFX layer and requests a reveal animation.
- `CartoRig - Add Route`: resolves source/destination countries, creates an independently styled OFX route layer and requests draw-progress keyframes. Origin/destination use **approximate polygon-bbox centers**, not capitals.
- `CartoRig - Set Camera`: sets or animates the base camera toward an approximate country focus using Resolve's Fusion spline mechanism.
- Every country/route layer **requires** Fusion camera expressions connected to `CR_Map_Base`. If the host does not expose these OpenFX expressions, object insertion fails explicitly rather than placing an unanchored layer.
- After the command, the user saves, scrubs and exports using Resolve itself; there is no extra CartoRig timeline and no runtime network call.

**Distribution**
- `Install-CartoRig.cmd`: Windows double-click → UAC → verified precompiled OFX & Lua commands in Resolve's system Scripts/Utility folder.
- Country index built from `data/countries.geojson` (173 features). Does **not** require the full Natural Earth 51-source experimental pack.
- Existing `CartoRig Hybrid Test` remains in the kit for development diagnostics.
- GitHub Actions Windows runner produces `CartoRig-Edit-First-Preview-Windows` artifact, with one-day retention and no permanent artifact requirement.

## Quality gates and evidence
| Gate | Evidence or state |
|---|---|
| Native objects-only C++ painting preserves source | Native C++ regression assertions / CI |
| Independent country colors and route RGB | C++ regression assertions / CI |
| Catalog 173 IDs matches bundled GeoJSON | Python contract tests / CI |
| Lua source parses | `luac5.4 -p` on Linux CI |
| 4-operation Lua authoring flow | Mock Fusion Lua test on CI (NOT a Resolve host test) |
| User's original POC Fusion-first architecture | Real Resolve screenshots and basic save/reopen/export report |
| NEW authoring commands operate on real Resolve 20 | **NOT YET TESTED** |
| Nested OFX input expressions read back and track camera | **NOT YET TESTED** |
| Multiple overlays persist & survive Deliver in 4K | **NOT YET TESTED** |
| Complete Natural Earth 215-layer/52-raster integration | **NOT IMPLEMENTED** in this MVP |
| Geographically anchored professional label system | **NOT IMPLEMENTED** |
| Docked GEOlayers-like editing panel | **NOT IMPLEMENTED** |

## Minimum real-host acceptance (priority order)
1. Open Resolve Studio 20 with an existing project and timeline; run `CartoRig - Create Map`. Confirm inserted Fusion Composition renders a neutral geographic map.
2. Put playhead over that map clip; run `CartoRig - Add Country`, type Brazil, choose Gold; then add Venezuela in Red. Confirm two different colors persist. One action may block if camera expression API does not support OpenFX inputs; collect the error, do not claim success.
3. Add route Brazil → Venezuela. Confirm independent route progress and start/end approximate centers.
4. Set camera target to Brazil and animate. Both country overlays and route must follow camera for every frame. If any object drifts, **fail** product acceptance.
5. Close, reopen, and Deliver export. Check the actual rendered pixels and report any desynchronization.
6. Profile at 1440p and 4K and test overlap compositing/alpha.

## Performance / fallback decisions
Avoid reintroducing a user-installed Python or Natural Earth build. If stacking many OFX overlays is too expensive, consolidate low-priority static country layers into one C++ map pass while preserving independently animated protagonist objects as OFX layers. Keep public user workflows Edit-first; manual Fusion node editing remains optional for advanced editors.

## Risks intentionally open
- Resolve 20 may expose OpenFX camera inputs under host-specific names; the UI library checks simple expression binding but the real host remains the authority.
- User-initiated operations rely on `comp:AskUser`, which must be evaluated interactively in Resolve Studio 20.
- The `GetCurrentVideoItem()` API may resolve the playhead item differently depending on the selected Edit track. Do not silently edit an arbitrary other item; the script requires a named CartoRig composition.
- Unsupported host actions and partial graph mutations must be tested. Built-in Fusion Undo is used around modifications, but failed actions could leave an incomplete new clip.
- Multiple stacked filters incur image copies; no production 4K FPS figure is asserted.
