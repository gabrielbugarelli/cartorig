# CartoRig — Fusion-first greenfield proof

This branch is a **clean working tree created from scratch**. It intentionally contains no legacy CartoRig application code, assets, build system, or installer. It retains `main` as a Git parent only because this GitHub connector cannot create parentless commits; there is **no runtime reuse** of old files.

**Goal:** test UIManager object selection -> Fusion FlowView/Inspector/Spline, independent region color animation, and one shared camera transform. Edit contains the Fusion Composition clip. This is a **technical proof only**, with abstract rectangles; not yet a cartographic renderer or final UX.

Run by placing the included Lua script under the Resolve per-user `Fusion/Scripts/Comp` folder. Use a disposable 30s/30fps Fusion Composition, select Brazil, record color keyframes at frames 0/329/330, check node-specific Spline curves, key camera Size, then save/reopen/Deliver.

See docs for verification and BLOCKED/NOT RUN gates. No actual Resolve Studio 20 host tests have been conducted on this new code. The greenfield code license is not yet selected by the product owner.
