# CartoRig Native – first in-host test (Resolve Studio 20, 2026-11-06)

Evidence supplied by user: generator successfully installed/discovered in Edit; frame appears zoomed, red-toned and partially composited with underlying imagery. Overlay was not successfully applied in the reported gesture.

## Verified from source

- Generator and Filter contexts are distinct. A Filter is an effect on a clip; it is not a standalone timeline item. The filter's application to a regular video clip has not been tested yet.
- The plugin advertised tile support while ignoring OfxImageEffectPropRenderWindow. This could overwrite memory outside the host-requested region and race concurrent renders. Fixed on this branch.
- JSON camera and route progression vary per frame even with static OFX parameters, but the plugin did not set OfxImageEffectFrameVarying. Fixed using GetClipPreferences.
- Generator produced straight RGBA but did not declare output premultiplication; this could cause incorrect alpha interpretation. Fixed for generator; filter still requires explicit source-premultiplication negotiation and conversion.
- Multi-config Visual Studio emitted Win64/Release/CartoRigNative.ofx; installer expects Win64/CartoRigNative.ofx. Fixed per-config bundle output.

## Still unresolved / must investigate on actual Resolve machine

- Difference between screenshot's reddish colors and JSON's blue/dark palette. OpenFX specifies R,G,B,A packed byte order, so do not arbitrarily swap channels. Need diagnostic pure red/green/blue/alpha frames and compare against a native Resolve solid-color clip in the same color pipeline.
- Camera timeline timebase. OFX specification defines effect-local time; log actual kOfxPropTime, camera zoom and route progress on the user's Resolve 20 before applying any timeline-origin offset.
- Source-video fragments/background seen through generator. Retest with fixed RenderWindow and premultiplication; confirm active scene JSON has transparent=false and that the viewer cache is rebuilt.
- Filter applied to regular video and to Map generator, including source pixel depths and alpha conversion.
- Canvas/project dimensions, aspect ratio, render scale and tiled callbacks at 4K.

## Reproduction and acceptance

1. Install a newly produced CI artifact from this branch, replacing the old bundle **with Resolve closed**. The binary must be directly inside Contents/Win64.
2. Create a fresh test project in Resolve 20. Add Map generator on V1, with no other clips, at Viewer Fit. Use default scene.
3. Capture Inspector fields and screenshot at frame 0, 24, 120, 239. Capture result at full quality and reduced proxy quality.
4. Disable Use camera keyframes; set longitude=-62, latitude=-11, zoom=2.8, bearing=0. Confirm Brazil and Venezuela remain visible and stable. RouteProgress=-1 for scene, or 0/1 to test controlled reveal.
5. Put a standard video on V1. Apply Overlay FILTER directly to video (not onto empty track). Test using double-click with selected clip and dragging onto clip.
6. Repeat in 8-bit and 32-bit float color modes; check alpha over a native opaque color generator. Save/reopen and export test frames.
7. Keep gate status BLOCKED until screenshot/video from actual Resolve 20 verifies render; successful GitHub build cannot count as Resolve verification.

## References

- https://openfx.readthedocs.io/en/main/Reference/ofxImageEffectContexts.html
- https://openfx.readthedocs.io/en/main/Reference/ofxImageEffectActions.html
- https://openfx.readthedocs.io/en/main/Reference/ofxClipPreferences.html
- https://openfx.readthedocs.io/en/main/Reference/ofxImageClip.html
- https://openfx.readthedocs.io/en/main/Reference/ofxCoordSystem.html
