# Natural Earth offline source inventory (phase 0)

This directory contains the **verified source layer list** from the official Natural Earth vector source repository, release `v5.1.2` pinned at commit/tree `f1890d9f152c896d250a77557a5751a93d494776`.

The `vector_layers_v5.1.2.json` file covers **215 shape layers**, across 10m / 50m / 110m cultural and physical collections. It records upstream Git blob identities and that all layers are **EXPECTED_NOT_INSTALLED**. It does **not** include raster variants or verify published ZIPs. The eight official source pages, raster subpages, download links and theme versions must be enumerated by `tools/natural_earth/inventory.py` in the release builder.

**Never call this dataset a 100% Natural Earth data pack until the archive verification and coverage gates pass.** Raster assets are significant in size and must be shipped in a separate offline data pack, not placed into the OFX DLL.

Natural Earth data is in the public domain: https://www.naturalearthdata.com/about/terms-of-use/ .
