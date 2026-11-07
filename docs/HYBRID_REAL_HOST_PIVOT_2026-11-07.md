# Hybrid Resolve 20 — real host evidence and architectural pivot (2026-11-07)

## What the user actually tested

Two independently user-installed Windows packages reached the real DaVinci Resolve Studio 20 host.

**First run:**
- Resolve opened a fresh QA project and a timeline.
- `Timeline.SetSetting("timelineResolutionWidth","1920")` failed; this was a test-harness error, not proof of a native architecture incompatibility.
- Fixed by using the existing project/timeline resolution.

**Second run:**
- `Timeline.InsertOFXGeneratorIntoTimeline("CartoRig Map (Edit)")` succeeded.
- The real map displayed in the Edit Viewer and the OFX Inspector offered native camera/keyframe controls.
- `TimelineItem.AddFusionComp()` returned failure on the **OpenFX Generator** timeline item.
- Consequently the two requested Text+ diagnostic objects were never built.
- The user's screenshot shows the native CartoRig world-map renderer; those visible keyframe controls are *OFX parameters*, not independently created Fusion objects.

## Architecture decision

**BLOCKED:** `OpenFX Generator timeline item -> AddFusionComp -> Fusion child graph` for the tested Resolve Studio 20 environment. Do not retry this design or mark its independent objects working.

**Next experiment:** invert containment:
```
Edit timeline
  -> native Fusion Composition clip
     -> Fusion Background
     -> native CartoRig Overlay OFX filter tool (Fusion RegID: ofx.com.cartorig.native.overlay)
     -> Merge(BRA Text+) -> Merge(VEN Text+) -> MediaOut
```

Fusion documentation supports compatible installed OpenFX filters as nodes; Resolve's scripting API advertises `InsertFusionCompositionIntoTimeline()`. However the exact **CartoRig Overlay** plugin registration and output require real host validation. This is an **unverified candidate**, not an accepted architecture.

## QA experience

The user should *only* need to download the prebuilt kit, double-click `Install-CartoRig.cmd`, restart Resolve and choose `Workspace > Scripts > Utility > CartoRig Hybrid Test`.

No Python or Natural Earth data-pack build should be imposed on the user. Every test creates a fresh QA project; never change production timelines. The new script must show `BLOCKED` and a red timeline marker if any step fails.

## Gates

| Gate | State |
| --- | --- |
| OFX Map generator loads and renders in Edit | **OBSERVED PASS** in screenshot |
| OFX Inspector camera/keyframe controls appear | **OBSERVED PASS** for visible controls; specific curve behavior not audited |
| Add Fusion directly to OFX Generator timeline item | **OBSERVED BLOCKED** in Resolve 20 |
| Insert separate Fusion Composition timeline item | **NOT TESTED** |
| Load CartoRig Overlay as node in Fusion | **NOT TESTED** |
| Render overlay + two Text+ with independent Blend curves | **NOT TESTED** |
| Confirm Viewer, save/reopen and Deliver | **NOT TESTED** |
| Geographic anchoring under animated CartoRig camera | **NOT IMPLEMENTED** |

If Fusion refuses loading the Overlay filter, stop and evaluate a Fusion-native source node or a genuine Fusion template with a supported image path. Do not silently claim the bridge works merely because the initial map renders on Edit.
