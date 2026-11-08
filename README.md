# CartoRig — Fusion rewrite (new codebase)

A completely new implementation of CartoRig based on `CR-PS-2.0` as the **working product specification**. No legacy CartoRig implementation code, graph, UI or installer has been copied into this branch.

## Implemented in this commit

- Independent canonical scene object model, persistent IDs, origin metadata and style values.
- Typed `Region`, `Marker`, `Label` and `Route` creation with explicit WGS84 endpoints. A City without a polygon cannot be converted into an invented administrative Region.
- Scene CRUD: rename, duplicate, delete with dependent-object protection, independent style overrides, lock, selection and draw-order changes.
- Motion planning engine with an initial registry of **16 named presets** from `CR-PS-2.0`. It validates frame bounds, affected channels and existing-channel conflicts, and produces explicit keyframe plans without modifying unrelated channels.
- Lua regression tests for product invariants and the Brazil instantaneous color-change case (frame 330 at 30 fps).

## Not yet implemented

- UIManager Scene, Control/Motion Inspector Fuse, geospatial renderer, Natural Earth data bundle, working host adapter, installer and real DaVinci Resolve Studio 20 tests.
- The presets are **planning contracts**, not yet installed as Fusion keyframes. Do not present them as functional effects.

The next integration target is a single vertical slice: initialize a Fusion Composition, create a real Region from an offline polygon, select it from Scene, expose its Fill/Opacity in the Fusion Inspector and write a real Fusion spline that is editable in Spline. This requires host validation.

## Run tests

From repository root:

```sh
texlua tests/test_scene.lua .
texlua tests/test_motion.lua .
```

## Product design boundaries

- Fusion-first, not Edit-first.
- `Scene` is structural UIManager authoring; `Control`/`Motion` belong to Fusion Inspector; Spline remains Fusion-native.
- No auto-generated editorial objects, keyframes, or routes.
- No internet runtime dependency; future geographical data originate only from specified offline Natural Earth packages.
- All source in this branch is written anew; prior implementation history is not treated as a template.

**Status:** source foundation, **not** a functional Resolve plugin or production release. License selection remains with the project owner; the repository should not be called open-source licensed until a compatible license is adopted.
