# DaVinci Resolve Studio 20 — manual E2E + usability acceptance

This protocol is **not executed in CI**; requires an actual Windows 11 x64 Resolve Studio 20.x installation. Always use a disposable project and timeline. Record exact Resolve build, GPU/driver, pixel aspect ratio, media FPS, UI scaling and Windows display resolution.

## Default scene requirement (0.3-dev)

- [ ] R20-00A. Insert a **new** CartoRig Map. Frames 0/96/239 identical with no manually authored keys; no Brazil–Venezuela auto-animation.
- [ ] R20-00B. Set Country 1 ISO3 and animate Highlight opacity, then enable/animate a manual route. All behavior must originate from the Inspector, not JSON editing.
- [ ] R20-00C. Inspector source SHA agrees with GitHub PR branch head, regardless of temporary PR merge commit.

## Install and discovery

- [ ] R20-01. Build Release x64; run installer with Resolve closed; verify directory and all resources.
- [ ] R20-02. Open Resolve Studio; verify both `CartoRig Map (Edit)` and `CartoRig Overlay (Edit)` load without startup error.
- [ ] R20-03. Find generator in Edit Effects Library, drag into disposable video timeline and inspect Viewer.
- [ ] R20-04. Apply overlay to existing video; verify video visibility, map compositing and opacity.
- [ ] R20-05. If generator unavailable, record library category and host logs, do **not** claim its support.

## Parameters and animation

- [ ] R20-06. Inspector shows scene/data file fields and camera parameters with no broken controls.
- [ ] R20-07. Disable Use Scene Camera; animate zoom and longitude via Edit Keyframe/Curve Editor; verify frame accuracy.
- [ ] R20-08. Animate route reveal 0→1 in 3 keyframes, edit Bézier velocity curve, verify no teleport.
- [ ] R20-09. Rewind, seek randomly, use reverse/speed ramp and trim clip; compare position and interpolation.
- [ ] R20-10. Duplicate generator clip, set different camera settings, verify instance separation.

## Robustness and visual correctness

- [ ] R20-11. Change to 3840×2160 at 24fps; check texture bounds and no seams/pixel bleed.
- [ ] R20-12. Render Deliver 8-bit and high-bit-depth project; check alpha over black, white and footage.
- [ ] R20-13. Enable Optimized Media / Render Cache, scrub and force re-render; compare before/after.
- [ ] R20-14. Save project, close Resolve, reopen; inspect identical parameters and frame render.
- [ ] R20-15. Move a scene JSON file; verify user-visible recoverable error rather than Resolve crash.
- [ ] R20-16. Load malicious/invalid/overlarge GeoJSON; verify safe failure and unchanged project.
- [ ] R20-17. Test negative rowBytes and split render windows if host exposes them.
- [ ] R20-18. Switch screen scale (100/125/150%) and dark themes; verify legible labels and control accessibility.
- [ ] R20-19. Stress 20 independent CartoRig clips with multiple random seeks and background render; monitor memory.
- [ ] R20-20. Capture 3 sample frames and source hash; compare against C++ standalone image with known color space.

## Test evidence format

For each test, record `id`, `PASS/FAIL/BLOCKED`, `Resolve exact build`, `Windows build`, `scene hash`, `plugin commit SHA`, `screenshot/video path`, `crash log`, `duration/observed memory`, `bug link`, and `reproduction steps`. Do not count an unrun manual check as passing.

Usability criteria: create a map from the sample, change camera, insert a route and render with no page Fusion visit. Record number of actions and blocked interactions; tester should not need to edit source files for routine target workflow in a production release.
