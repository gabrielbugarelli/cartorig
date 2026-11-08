# CartoRig rewrite — evidence status

**Engineering preview only.** A successful unit test suite is not product release approval.

| Scope | Automated tests | Windows Resolve Studio 20 | Product acceptance |
| --- | --- | --- | --- |
| Scene model, group/route edits, identity, styles | PASS locally | NOT RUN | OPEN |
| Offline GeoJSON, lazy point/polygon loading | PASS locally | NOT RUN | OPEN |
| Projection, seam math, fit, polygon ring semantics | PASS locally | NOT RUN | OPEN |
| Fusion Scene metadata JSON roundtrip | PASS with mock | NOT RUN | OPEN |
| Fusion Scene UI + search, create Region/Marker/Label/Route | Lua syntax / host mock components | NOT RUN | OPEN |
| Region/Marker/Label/Route native tools | PASS mock host | NOT RUN | OPEN |
| Persistence-failure rollback without touching other nodes | PASS mock host | NOT RUN | OPEN |
| RGB/Opacity/Size/Draw/Camera native keys (supported channels) | PASS mock host | NOT RUN | OPEN |
| Experimental Fuse with Control/Motion Inspector pages, premultiplied alpha pass | PASS callback mock | NOT RUN | OPEN |
| All 16 Motion plan definitions | PASS unit plan contracts | NOT RUN | OPEN |
| All 16 preset execution in Inspector Control/Motion | **NOT IMPLEMENTED** | NOT RUN | OPEN |
| Real 10m data and geometry source inventory | Offline 7-dataset build + self-contained Windows preview artifact in Actions (SHA256 checked) | NOT RUN | OPEN |
| Production renderer: polygons with holes, antimeridian, 4K, alpha, screen-space symbols | **NOT IMPLEMENTED** | NOT RUN | OPEN |
| HOST-01…HOST-10 and QA-01…QA-60 | NOT RUN | NOT RUN | OPEN |

**Acceptance rule:** marks of `PASS` cover only the explicitly executed test contracts and do not imply user-visible behavior in the Resolve host. `BLOCKED`/`NOT RUN` are not success.
