# Fusion-first Resolve Studio 20 host acceptance

**All new-script gates: NOT RUN in the actual user's Resolve Studio 20.**
Existing Fusion/OFX acceptance on older code does not validate this script.
The graphics in this PoC are rectangles, not true geographic regions.

Prerequisite: Windows 11, DaVinci Resolve Studio 20, a disposable Fusion Composition inserted on the Edit timeline, ideally 30 seconds at 30 fps.

| ID | Test on actual Resolve | PASS criteria | Status |
|---|---|---|---|
| FFX-01 | Open Fusion Composition from the Edit page | Single clip, image returns to Edit | NOT RUN for new script |
| FFX-02 | Start UIManager script; interact with search/tree | Nonmodal editor remains usable | NOT RUN |
| FFX-03 | Select Brazil then Rio in tree | Flow selection AND Inspector change to matching node | NOT RUN |
| FFX-04 | Enable Show Only Selected Tool in Fusion Spline | Curves correspond to tree selection | NOT RUN |
| FFX-05 | Brazil red keys at 0/329, green at 330; Rio independent | Step/Hold and independent RGB curves | NOT RUN |
| FFX-06A | Key camera Transform.Size at 2 instants | Both rectangles scale in sync in same composite | NOT RUN |
| FFX-06B | Render actual geodetic camera, polygons, route | No geographic drift | OUT OF SCOPE: next POC |
| FFX-07 | Run script again, test undo and cancellation | No duplicate or user-node deletion | NOT RUN |
| FFX-08 | Save/close/reopen and check colors/keyframes | Fully retained without Qt open | NOT RUN |
| FFX-09 | Overlay over ordinary video | Alpha correct | NOT RUN |
| FFX-10 | Render 1440p and 4K | Visual and performance measurements | NOT RUN |
| FFX-11 | Work with network disabled | No network dependency | NOT RUN |
| FFX-12 | Trim/duplicate/move clip | Timebase and identities remain valid | NOT RUN |

**If FFX-02–06A fail:** fix integration, do not start the new geographic renderer.
**If they pass:** build and compare shared geo-camera/mask vs per-region OFX proof.
Capture UI window, Flow+Inspector, Spline curves, frames 0/329/330, and exact Fusion Console error when applicable.

The output must not be called 'fully tested' until Resolve host evidence exists.
