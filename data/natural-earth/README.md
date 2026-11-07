# Natural Earth offline source inventory (phase 0)

This directory contains the **verified source layer list** from the official Natural Earth vector source repository, release `v5.1.2` pinned at commit/tree `f1890d9f152c896d250a77557a5751a93d494776`.

The `vector_layers_v5.1.2.json` file covers **215 shape layers**, across 10m / 50m / 110m cultural and physical collections. It records upstream Git blob identities and that all layers are **EXPECTED_NOT_INSTALLED**. It does **not** include raster variants or verify published ZIPs. The eight official source pages, raster subpages, download links and theme versions must be enumerated by `tools/natural_earth/inventory.py` in the release builder.

**Never call this dataset a 100% Natural Earth data pack until the archive verification and coverage gates pass.** Raster assets are significant in size and must be shipped in a separate offline data pack, not placed into the OFX DLL.

Natural Earth data is in the public domain: https://www.naturalearthdata.com/about/terms-of-use/ .

## Audited raster source discovery — 52 ZIP variants

The real official-source scan
(https://github.com/gabrielbugarelli/cartorig/actions/runs/42336954400)
verified 24 accessible source/category pages and identified 52 unique
raster ZIP links, 38 at 10m and 14 at 50m. The identity of those 52
publisher URLs/versions is pinned by
`raster_discovery_v2026-11-07.lock.json`. No raster archive itself has been
downloaded or certified by this discovery lock; the content SHA lock below is
an independent release gate.

## Publisher raster SHA256 lock — release gate

`data/natural-earth/raster_sources.lock.json` is intentionally absent until
all 52 official raster archives have been acquired and SHA256-verified by the
release workstation. Generate it with `python -m tools.natural_earth.source_lock`
from the actual publisher inventory and acquisition manifest, inspect the
SHA256 values, and commit the reviewed result. `release_pipeline.py` now
rejects a Complete pack build if the lock is absent or disagrees with the
publisher archive SHA256 values. This avoids publishing fictional source
integrity claims based solely on locally generated download summaries.
