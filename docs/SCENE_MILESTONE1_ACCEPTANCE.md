# CartoRig — Scene milestone 1 acceptance ledger

Contract: CR-PS-2.0 ``2.1–2.6, 11–12, 15–16.
Scope: SC-001–SC-005; associated QA-01, 05, 17–20, 26, 34, 51,
52, 59 and 60. Branch: `release/1.0-rc1-fusion-rewrite`.

A green GitHub Actions run is **NOT** a real DaVinci Resolve Studio 20
host acceptance.

| Contract | Code path | Simulated automated proof | Required Resolve proof |
|---|---|---|---|
| SC-001 initialize/recognize comp | `scene.lua` state/initialize/snapshot | `test_scene.lua`, `test_scene_ui.lua` | Create and reopen blank Fusion comp with neutral Base Map+Camera, Undo/Redo |
| SC-002 typed offline search | `scene.lua` search, norm, fingerprint | `test_scene.lua` and data CI | Brasil/Brazil, São Paulo, Rio State vs City, no-network data |
| SC-003 CRUD/global z/multiselect/Lock/Undo | `scene.lua` batch,duplicate,move; Scene Tree UI | `test_scene.lua`, `test_scene_tree.lua`, `test_scene_ui.lua` | Independent curves, Viewer order, real Undo and persistence |
| SC-004 Group organizing | `scene.lua` groupMany/ungroup, `scene_tree.lua` | `test_scene.lua`, `test_scene_tree.lua` | Group/hide/ungroup three regions without changing IDs or keyframes |
| SC-005 Node Editor/Inspector selection | `scene.lua` selectedInHost, UI event Comp_Activate_Tool | `test_scene_ui.lua` | Two-way selection and native Inspector tabs in Resolve |
| WRONG_CONTEXT and NO_COMP | `scene.lua` active composition and UI fail-closed | `test_scene_ui.lua` | Switch compositions with Scene open; no edits to old clip |
| SCENE_BROKEN diagnostics | persistent ObjectRegistry, state/inspect | `test_scene.lua` | Delete node manually, reopen, detect exact missing ID |
| Recover Copy | guarded `recoverCopy` and UI confirm | `test_scene.lua` | Host NewComp/CopySettings/Paste capability, original untouched |
| Singleton and cleanup | one Scene window, AddNotify/RemoveNotify, 470×655 tabs | `test_scene_ui.lua` 20 cycles plus error path | 20 real open-close cycles; RAM/VRAM and crash monitoring |

## Implemented software tests

CI executes Windows/Ubuntu builds, OpenFX suite mocks, C++ tests,
AddressSanitizer/UBSan, publisher-data build and Windows installer
package validation. Scene tests include:
- `tests/test_scene.lua` — backend state, undo, foreign deletion, recovery,
  grouping, stable ID and independent duplication.
- `tests/test_scene_tree.lua` — typed hierarchy, global z, protected IDs.
- `tests/test_scene_ui.lua` — run authored UI script in simulated UIManager,
  Tree activation, F2, Delete/Escape confirmation, event subscriptions,
  context switch, NO_COMP, contextual tab, singleton and 20 GUI cycles.
- `tests/test_install_preflight.ps1` — real PowerShell 5.1 validity,
  tamper, missing files and forced-online rejection.

## Remaining host-dependent evidence

The tests above do **not** prove that the Windows Resolve 20 UIManager,
native Inspector, Spline, Undo/Redo, project Save/Reopen and Deliver
behave as expected. Real resource growth after 20 cycles is likewise
unmeasured. Grouped simultaneous native Inspector `Mixed` presentation
must be verified inside the host.

`SCENE_DIRTY`, `LOCKED`, `BUSY` and `HOST_ERROR` require additional
host-oriented state-machine checks; UI guards and diagnostic messages
are implemented but not exhaustive host proof. Recover Copy must safely
refuse if host APIs for independent native settings cloning are absent;
it must never modify the damaged source.

No claim of 100% QA or HOST-01–HOST-10 can be made from CI alone.
No merge to main or stable package is authorized by this milestone.
