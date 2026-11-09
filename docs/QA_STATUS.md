# CartoRig rewrite — evidence status

**Engineering preview only.** A successful unit test suite is not product release approval.

| Scope | Automated tests | Windows Resolve Studio 20 | Product acceptance |
| --- | --- | --- | --- |
| Scene model, group/route edits, identity, styles | PASS locally | NOT RUN | OPEN |
| Scene UI authorial Rename / Hide-Show / Lock, owned node validation, failure rollback | PASS command + mock-Fusion tests | NOT RUN | OPEN |
| Offline GeoJSON, lazy point/polygon loading | PASS locally | NOT RUN | OPEN |
| Continent classification as source-derived composite index, referential integrity, no invented polygon | PASS Lua synthetic + Python converter + malformed index contracts | NOT RUN | OPEN |
| Projection, seam math, fit, polygon ring semantics | PASS locally | NOT RUN | OPEN |
| Fusion Scene metadata JSON roundtrip | PASS with mock | NOT RUN | OPEN |
| Fusion Scene UI + search, create Region/Marker/Label/Route | Lua syntax / host mock components | NOT RUN | OPEN |
| Region/Marker/Label/Route native tools | PASS mock host | NOT RUN | OPEN |
| Persistence-failure rollback without touching other nodes | PASS mock host | NOT RUN | OPEN |
| RGB/Opacity/Size/Draw/Camera native keys (supported channels) | PASS mock host | NOT RUN | OPEN |
| Camera Zoom-only preserving fixed geoanchor at keyed poses; manual Center collision prevention | PASS mock + mathematical contract | NOT RUN; between-key easing drift requires host QA | OPEN |
| Motion Pop In minimum duration (3 distinct keyframes) | PASS boundary unit contract | NOT RUN | OPEN |
| Experimental Fuse with Control/Motion Inspector pages, premultiplied alpha pass | PASS callback mock | NOT RUN | OPEN |
| Region authorial Fuse: color picker, object opacity, highlight and native color/opacity/highlight keys | PASS callback + graph mock incl. 2-island geometry and rollback | NOT RUN | OPEN |
| Base Map authorial Fuse: ocean-only background, Full Map / Transparent Overlay and Ocean Fade | PASS callback + graph mock incl. alpha 0 and fail-closed unsupported Land | NOT RUN | OPEN |
| All 16 Motion plan definitions | PASS unit plan contracts | NOT RUN | OPEN |
| All 16 preset execution in Inspector Control/Motion | **NOT IMPLEMENTED** | NOT RUN | OPEN |
| Real 10m data and geometry source inventory | Offline 7-dataset build + self-contained Windows preview artifact in Actions (SHA256 checked) | NOT RUN | OPEN |
| Production renderer: polygons with holes, antimeridian, 4K, alpha, screen-space symbols | **NOT IMPLEMENTED** | NOT RUN | OPEN |
| HOST-01…HOST-10 and QA-01…QA-60 | NOT RUN | NOT RUN | OPEN |

**Acceptance rule:** marks of `PASS` cover only the explicitly executed test contracts and do not imply user-visible behavior in the Resolve host. `BLOCKED`/`NOT RUN` are not success.

## 2026-11-09 — Fusion integration hardening (pending host confirmation)

| Gate | Local unit / host simulation | Resolve Studio 20 Windows | Release state |
| --- | --- | --- | --- |
| Preserve user-created graph when initializing CartoRig overlay | PASS `test_host_compositing.lua` | NOT RUN | OPEN |
| Restore original MediaOut wire after failure | PASS `test_host_compositing.lua` | NOT RUN | OPEN |
| Polygon outer+hole via Fusion mask chain `PaintMode=Subtract` | PASS simulated topology/rollback; pixel output NOT tested | NOT RUN | OPEN |
| Geographic Camera Fuse Control/Motion evaluation in requested frame | PASS `test_fuse_camera.lua`, 16:9 and 9:16 | NOT RUN | OPEN |
| Motion writer refuses manual Fusion keyframes before modifying any channels | PASS `test_motion_native_conflicts.lua` | NOT RUN | OPEN |
| In-host self diagnostic, only in empty disposable comp | PASS mock cleanup and 7 gate checks | NOT RUN | OPEN |
| Lua 5.1 compatibility | LuaJIT job added to CI; local `texlua` tests PASS | NOT RUN | OPEN |

**Known functional gaps unchanged:** no complete land/border renderer or high-resolution 10m dynamic cache; 16 presets are NOT fully bound to Inspector, Layer Fade beyond Ocean and Region Border Draw/Route Follower are unavailable; marker/label screen-pixel sizing under geographic zoom needs a new rendering layer; full antimeridian wrapping needs an in-host render implementation. HOST-01..HOST-10 and QA-01..QA-60 remain **NOT RUN**. The new host diagnostic only probes tool registration/serialization/animation; it does not substitute for pixel QA.

## 2026-11-09 — Native layer order and persistent object lookup

| Verification | Automated | Windows Resolve Studio 20 |
| --- | --- | --- |
| Move Up/Down actually rewire authored Merge chain without rewiring MediaOut/footage | PASS `test_native_draw_order.lua` | NOT RUN |
| Manual modification of the chain fails closed before modifying managed nodes | PASS `test_native_draw_order.lua` | NOT RUN |
| Rejected Fusion connection restores previous chain | PASS `test_native_draw_order.lua` | NOT RUN |
| Failed Scene JSON persistence restores previous connections and order | PASS `test_native_draw_order.lua` | NOT RUN |
| Rename camera/final composite in Node Editor then add another object | PASS `test_native_draw_order.lua` | NOT RUN |
| Stale name cannot cause selection of a different ObjectId | PASS `test_native_draw_order.lua` | NOT RUN |

**Not certified:** Actual `GetConnectedOutput`, disconnected sockets, Undo,
reordering/rendering and save/reopen in DaVinci Resolve Studio 20. CI cannot
substitute for those host gates.

## 2026-11-09 — Route spatial update without replacing native spline

| Verification | Automated | Windows Resolve Studio 20 |
| --- | --- | --- |
| Edit Route endpoints and waypoints in existing PolylineMask | PASS `test_native_draw_order.lua` | NOT RUN |
| Keep existing WriteLength keys and exact mask identity | PASS | NOT RUN |
| Reject unsupported antimeridian change before mutation | PASS | NOT RUN |
| Reject missing ability to snapshot native Polyline for rollback | Guard coded, host evidence pending | NOT RUN |
| Restore previous Polyline when Scene state persistence fails | PASS | NOT RUN |

**Required host follow-up:** Test native `GetInput('Polyline')`/`SetInput` round-trip
on PolygonMask with a keyframed WriteLength channel. No QA gate is marked DONE.

## 2026-11-09 — Native Delete, authorial Fuses and static Control writes

| Gate | Local automated result | Windows Resolve Studio 20 |
| --- | --- | --- |
| Delete middle/top object preserving Merge chain and third-party nodes | PASS `test_native_delete.lua` | NOT RUN |
| Reject deletion consumed by unrelated Fusion tool | PASS `test_native_delete.lua` | NOT RUN |
| Restore all connections after save/ConnectInput failure | PASS `test_native_delete.lua` | NOT RUN |
| Marker, Route and Label Control/Motion Fuses, RGBA premultiplication | PASS `test_fuse_authorial_objects.lua` | NOT RUN |
| Supported native style writes with rollback and spline conflicts | PASS `test_native_control.lua` | NOT RUN |
| Reject malformed persisted styles and locked ancestor group | PASS `test_scene_integrity.lua` | NOT RUN |

**No host certification:** Native registrations, pixel output, 4K performance, complete object controls, all 16 Motion presets, host Undo/Redo, random-seek, alpha/footage, QA-01..60 and HOST-01..10 still need execution on Resolve Studio 20 Windows.

## 2026-11-09 — Native Camera Focus / Fit Scene commands

| Contract | Automated | Windows Resolve Studio 20 |
| --- | --- | --- |
| Focus City changes longitude/latitude only and never creates a key | PASS `test_camera_focus_fit.lua` | NOT RUN |
| Fit Point uses explicit 4x reference zoom; Fit Polygon uses actual viewport aspect/padding | PASS | NOT RUN |
| Focus/Fit preserve user-selected Bearing and existing independent properties | PASS | NOT RUN |
| Existing Fusion camera spline prevents static Focus edits; other channels rolled back | PASS | NOT RUN |
| Rejected second-channel native input or failed Scene persistence restores full camera pose | PASS | NOT RUN |
| Resolution unavailable in host prevents Fit rather than guessing a frame size | PASS | NOT RUN |

**Host gate:** `Comp.FrameFormat.Width`/`Height` preferences and Fusion Fuse camera
positioning must be exercised on the actual Resolve 20 Windows host. Unit tests
confirm transactional integration contracts, not Viewer alignment or render quality.

## 2026-11-09 — Incremental authoring and Region Stroke integration

| Contract | Automation | Windows Resolve Studio 20 |
| --- | --- | --- |
| Nested group locks block structural route edits and descendant lock toggles | PASS `test_nested_group_lock.lua` | NOT RUN |
| Group Hide/Show changes effective child Fusion visibility without erasing child flags | PASS `test_group_visibility.lua` | NOT RUN |
| Native group visibility failures restore earlier Blend state and do not persist partial changes | PASS `test_group_visibility.lua` | NOT RUN |
| Create/Ungroup group objects from Scene authoring and reject writes on locked groups | PASS `test_group_authoring.lua` | NOT RUN |
| Reverse Curved Route geometry while preserving mask identity and Draw Progress keys | PASS `test_native_draw_order.lua` | NOT RUN |
| Manual Merge Blend keys prevent structural visibility overwrite | PASS `test_scene_commands.lua` | NOT RUN |
| Region Fuse composes separate Stroke RGBA over Fill RGBA | PASS `test_fuse_stroke.lua` | NOT RUN |
| Region outer/hole contour masks and per-object Stroke color/alpha/visibility tools | PASS `test_region_renderer.lua`, `test_native_control.lua` | NOT RUN |

**Open:** Stroke Width is not an authorial Fuse-driven pixel-constant channel;
Border Draw, full 10m base cartography, all 16 Inspector-executable Motion
presets, reprojected screen-size symbols, antimeridian and HOST/QA gates remain
unverified. No R1.0 completion claim is permitted from these mocks.
