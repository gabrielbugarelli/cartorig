# CartoRig 1.0 — v0.1 release gate (draft)

Status: development preview. Neither a completed 1.0 nor a certified
DaVinci Resolve Studio 20 release. The v0.1 UX specification is the
source of product scope; v0.3 features belong to future 2.0 work.

## Architecture actually implemented in this branch

- C++ OpenFX native renderer retained.
- Single user-facing Workspace > Scripts > Utility > CartoRig - Editor.
- Fusion UIManager window: explicit scene chooser, typed offline search,
  object list, graphical fill/stroke color pickers and optional HEX.
- C++ Natural Earth catalog querying backed by installed SQLite/GeoPackage,
  and country-only bundled starter data when the pack is missing.
- Independent per-region fill, stroke, visibility and retained animation keys.
- Camera Focus (static) versus explicit Animate camera spline.
- Graphic route from chosen endpoints, optional arrowhead, explicit Reveal.
- In-place route edits preserve RouteProgress animation tracks.
- Independent georeferenced Label and Marker objects.
- Object rename, basic duplicate, reorder, hide/show, delete.
- Transparent-ocean choice for map overlay on video.
- No automatic Venezuela/Brazil animation and no user-facing ISO3.

## UX v0.1 — 15 scenario traceability

| Flow | Implementation | Remaining certification |
| --- | --- | --- |
| UX-FLOW-01: blank Edit scene | Fusion-first create | New unified GUI host |
| UX-FLOW-02: find Brazil | Name search/Add/Focus | Polygon Fit missing |
| UX-FLOW-03: highlight Rio State | Natural Earth Admin-1 persistent RGBA | GeoPackage shipped and host |
| UX-FLOW-04: country + state order | Independent layers and reorder | Save/reopen and real pixels |
| UX-FLOW-05: camera to São Paulo City | Point Focus/Animate | Curves on host |
| UX-FLOW-06: Brasília–Amapá arrow | Explicit area endpoint/route/reveal | Host rendering/keys |
| UX-FLOW-07: label destination | Independent no-pin geographic Label | Typography/offset incomplete |
| UX-FLOW-08: preset preserves overrides | Base/region independent styles | Preset selector incomplete |
| UX-FLOW-09: edit route in place | Update geometry, retain Reveal keys | Host Undo test |
| UX-FLOW-10: ambiguous names | Typed search/context, accent FTS | Full data-pack QA |
| UX-FLOW-11: transparent overlay | Alpha mode and native OFX | Real video/alpha test |
| UX-FLOW-12: save and Deliver | Native Fusion+OFX path | New editor project roundtrip |
| UX-FLOW-13: missing city polygon | Fail closed, city point only | Host UI message |
| UX-FLOW-14: offline | Local-only runtime, no HTTP | State/city pack install |
| UX-FLOW-15: duplicate scene/clip | Object duplication + scene chooser | Clip-copy isolation not certified |

All 15 flows remain release blockers until the real Resolve host confirms
their required behavior. Unit tests are not host certification.

## Explicit blockers to stable CartoRig 1.0

1. The official full Natural Earth Admin-1 and populated-places dataset
   is not bundled in this small Windows preview; a separate installed
   offline data pack is required.
2. Native Resolve 20 GUI event routing, clip selection, OpenFX-Fusion
   camera expressions, Editor launch and host Undo/Redo need workstation QA.
3. Object keyframe/editor parity, Label typography and screen-scale,
   polygon/route Fit, route waypoints and precise spatial Viewer handles
   are incomplete and must not be marketed as complete.
4. Clip copy isolation, save/reopen and Deliver 1440p/4K pixel/alpha
   parity need a real host test before release certification.
5. User approval of the final UX is separate from code merging.

## Host acceptance checklist

Use a disposable Resolve Studio 20 project. Install Windows preview with
Resolve closed; reopen > Edit > Workspace > Scripts > Utility > CartoRig -
Editor. The editor must contain exactly one common authoring workflow.

A. Create two independent scenes. Search Brazil by name. No ISO3 input.
B. Install the official NE offline pack. Search Rio de Janeiro STATE,
   add polygon with red Fill and gold Stroke; then add Brazil country
   with a different style. Reorder without mutating geometries or camera.
C. Search São Paulo CITY; Focus must not create keys. Animate must create
   editable native curves at the requested frames.
D. Search Brasília CITY and Amapá STATE; choose explicit Amapá endpoint;
   route arrowhead and reveal must respond separately. Edit the curve
   without deleting prior RouteProgress keys.
E. Add a Label to destination, pan/zoom and check geographic attachment.
F. Enable transparent oceans over footage; inspect actual alpha and source.
G. Duplicate the CartoRig clip; mutate copy; verify original unchanged.
H. Save/close/reopen; compare objects, colors and animation.
I. Deliver 1440p and 4K; compare output with Edit Viewer.
J. Disconnect internet and repeat search/render with installed data.

Only a successful end-to-end host test plus the certified minimum offline
dataset can permit a 1.0 stable tag. Do not merge a preview as stable.
