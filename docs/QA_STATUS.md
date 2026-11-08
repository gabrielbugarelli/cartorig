# CartoRig rewrite — evidence register

This is **not a release approval**. The unit-test suite and GitHub Actions verify mathematical, model, and mock-host contracts, **not** actual DaVinci Resolve Studio 20 functionality.

| Area | Local contract tests | Real Windows Resolve 20 | Product acceptance |
| --- | --- | --- | --- |
| Scene model / objects / style | PASS (local) | NOT RUN | OPEN |
| Geo: projection, antimeridian, fit, polygon holes | PASS (local) | NOT RUN | OPEN |
| Geo catalog: name/type lookup | PASS (fixtures) | NOT RUN | OPEN |
| Scene JSON persistence | PASS (mock) | NOT RUN | OPEN |
| Motion 16-preset plan definitions | PASS (unit) | NOT RUN | OPEN |
| Native keyframe writing in Fusion | PASS (mock for RGB only) | NOT RUN | OPEN |
| Region PolygonMask native loader | PASS (mock) | NOT RUN | OPEN |
| Fusion UIManager Scene bootstrap | Source written; syntax tested | NOT RUN | OPEN |
| Inspector Control / Motion pages | NOT IMPLEMENTED | NOT RUN | OPEN |
| 10m offline Natural Earth data (7 families) | Initial build PASS in GitHub Actions; indexed revision under test | NOT RUN | OPEN |
| Geometry topology / 4K renderer / alpha / export | NOT IMPLEMENTED | NOT RUN | OPEN |
| QA-01 to QA-60, HOST-01 to HOST-10 | NOT RUN | NOT RUN | OPEN |

**Never label QA as 100% of the product from green GitHub Actions.** A green workflow means only that its declared checks passed. Production requires Windows Resolve 20 host evidence and accepted visual QA.
