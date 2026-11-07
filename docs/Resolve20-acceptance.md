# Resolve Studio 20 — real-host acceptance (NOT YET EXECUTED)

Run in a scratch project and scratch timeline. Record Resolve exact build, Windows build, GPU/driver and source commit. Do not promote the alpha from CI alone.

| ID | Workflow | Exact observation required |
|---|---|---|
| HOST-00 | Run script in new Fusion Composition | Editor opens without rendering map; Create Map triggers scene creation; failures visible in status and `%TEMP%` log |
| HOST-00B | Polygon mask native setting parser | Check bmd.readstring and PolylineMask LoadSettings in Resolve Studio 20, without global Polyline; inspect mask geometry | 
| HOST-01 | Create 30s Fusion Composition; invoke CartoRig | Basemap renders; single clip visible in Edit; no crash |
| HOST-02 | Search `Brasil` | Country result without ISO3 input; no network |
| HOST-03 | Search `Rio de Janeiro` | `State` and `City` clearly distinct; State polygon correct |
| HOST-04 | Add Brazil; add Rio state | Two separately selectable Background nodes and masks, same map transform |
| HOST-05 | Key Brazil red @ 0/329, green @ 330 | Correct native Spline keys, no change in Rio, step/hold visible |
| HOST-06 | Key state opacity | Native spline in selected State node, independence verified |
| HOST-07 | Focus São Paulo City | Correct geographic position, without selecting State polygon |
| HOST-08 | Camera key poses at 0/90 | Land, region, markers, route remain aligned all frames |
| HOST-09 | Route Brasília → Amapá State | Requires explicit representative point confirmation, displays arrow |
| HOST-10 | Key route reveal 0→100 | Correct line trim and head behavior in intermediate frames |
| HOST-11 | Reopen editor after closing | No duplicate objects; selection and styles persist |
| HOST-12 | Save project, close Resolve, reopen | Same nodes / keyframes / clip image; no external companion process |
| HOST-13 | Deliver video 1440p and 4K | Compare selected frames with Fusion Viewer; no unexpected alpha/hue differences |
| HOST-14 | Host Undo + duplicate clip | No foreign nodes affected; duplications do not mutate original |
| HOST-15 | Scene error paths (missing data, holes) | Error explains limitation; no silent incorrect geometry |

**Pass policy:** Only capture from a real Studio 20 installation can convert `PENDING` to `PASS`. A Lua mock test is not host certification.