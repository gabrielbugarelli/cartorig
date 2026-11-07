# Natural Earth Offline Backend — engineering status and reproducibility

**Target:** CartoRig Native OpenFX, DaVinci Resolve Studio 20, Windows x64.  
**Product UI:** English only. Geographic names may have international aliases.  
**Installed-product network policy:** strictly offline; no geocoding, map tile APIs, login, update checks, HTTP or telemetry in the OpenFX runtime.

## Measured evidence (November 6, 2026)

| Metric | Verified evidence |
| --- | --- |
| Natural Earth official vector source release | `v5.1.2`, pinned tree `f1890d9f152c896d250a77557a5751a93d494776` |
| Official vector source layers | **215** separate `.shp` layer files from the official release tree |
| Breakdown | 10m cultural 84; 10m physical 50; 50m cultural 26; 50m physical 23; 110m cultural 14; 110m physical 18 |
| Official website pages audited | **24** — 8 category pages plus 16 raster family pages |
| Direct download/archive links discovered | **269** URLs (may include aggregate archives, variants and supplemental assets) |
| Raster download variants discovered | **52** links, from 7 families at 10m and 9 families at 50m |
| Website pages blocked during first audit | 0 |
| Source archive ZIPs verified by SHA256 | **0** at first inventory (real 110m smoke test is a separate CI verification) |
| Full GeoPackage installed and indexed | **No** |
| Full raster data pack verified | **No** |
| Natural Earth Complete certified | **No** |

**Important:** These are two independent catalogs: 215 official *source vector layers* and 269 *publisher download links*. A publisher ZIP may contain multiple layers; some links are aggregate packages or alternate releases. They must not be added together or interpreted as a total number of unique dataset themes.

## Real-data vector certification and Edit-first render bridge (Nov 6)

**Completed:** the pinned Natural Earth `v5.1.2` source set contains **215 distinct vector layers**. The publisher's aggregate GeoPackage yields **182** of those layers. The complementary **33** official GeoJSON datasets were downloaded, verified against upstream Git blob identities, converted to a separate standards-compatible GeoPackage, and validated as **8,116 real geographic features**. A combined offline coverage gate passed with **215 / 215** source-vector layers.

**Real rendering evidence:** the native C++ adapter read the publisher's aggregate GeoPackage and painted 177 country features / 288 polygons at 110m, 242 / 1,620 at 50m, and 258 / 4,274 at 10m. All three scale render tests passed using the existing raster core.

The OpenFX Generator/Filter now expose an opt-in **Vector GeoPackage** file parameter and a **Vector detail** selection under Advanced. Embedded GeoJSON and explicit custom GeoJSON retain precedence, and blank values still load the previously validated bundled world map.

**Unfinished:** The cataloged physical/cultural layers beyond country polygons, the complete raster repository, a no-network data pack installer and the Geographic Region search UI remain work in progress. Do not confuse *complete vector source coverage* with *complete Natural Earth feature parity*.

[Edit/Resolve 20 manual testing procedure](NATURAL_EARTH_EDIT_BRIDGE.md).

## Code implemented in this branch

- `data/natural-earth/vector_layers_v5.1.2.json`: pinned and auditable upstream layer list with per-layer Git blob identities. These are **not** archive SHA256 values.
- `tools/natural_earth/inventory.py`: explicit release-engineering collector for 8 official category pages and their raster family children. Tracks versions and broken URLs; never silently pretends a missing resource is installed.
- `tools/natural_earth/materialize.py`: source archive materialization. By default it **does not use the network** and reports `NOT_INSTALLED`. Only `--allow-network` enables downloads on the packaging machine. Output is a SHA256-per-archive manifest.
- `tools/natural_earth/verify_pack.py`: offline SHA256, bytes, ZIP CRC, path-traversal and decompression-bomb checks. Incomplete or unverified data fails.
- `tools/natural_earth/build_catalog.py`: converts a **local Natural Earth GeoPackage** to a separate read-only SQLite FTS5/R*Tree index. Indexes all original table names, with searchable country, state/province, city and derived continent records; retains each feature's original table/row reference.
- `tools/natural_earth/coverage.py`: fail-closed report comparing 215 vector layers to actual indexed layers, 8 official categories, 16 raster family pages, all archived sources, and validated raster derivatives.
- `src/natural_earth_catalog.cpp`: native C++ read-only SQLite lookup, using Windows WinSQLite3 from System32 and system SQLite on Linux. Unicode-safe Windows CLI. No network functions.
- `tests/test_natural_earth*.py`, `tests/test_ne_cpp.py`: offline test GeoPackages and simulated search; native C++ host adapter exercised with unicode and type disambiguation.
- Separate GitHub Actions workflow: pinned source assertion, Python 3.11/3.12 offline tests, live source-page audit and a small real-data ZIP smoke; **no giant data download in routine CI**.

### Current limitation

These components form the **backend foundation**. The OpenFX Generator still renders its previously validated country GeoJSON. The newly indexed GeoPackage is **not yet wired to the cartographic renderer or Geographic Region Inspector**. This separation is deliberate: it avoids regressing the antimeridian rendering fix and prevents a partial dataset from masquerading as the new complete backend.

## Reproduce the source audit

Requires internet **only on a release packaging machine**, not on the customer's computer:

```bash
python tools/natural_earth/inventory.py --output build/natural-earth/official_sources.json
python -m tools.natural_earth.smoke
```

The source inventory is a discovery report. It is **not** evidence that the archives are installed.

To assemble the raw archive store (a large download; operator must provision adequate storage and bandwidth):

```bash
python -m tools.natural_earth.materialize \
  --inventory build/natural-earth/official_sources.json \
  --data-dir build/natural-earth/data \
  --allow-network
```

By default `materialize` runs without network and exits as incomplete until every source archive is present and verified. All asset acquisition should be pinned to a frozen manifest before any production release.

## Create the local search index

First obtain the official all-vector GeoPackage archive listed by Natural Earth (approximately 436 MB compressed; measured disk requirements will differ):

`https://naciscdn.org/naturalearth/packages/natural_earth_vector.gpkg.zip`

Extract `natural_earth_vector.gpkg` on the packaging machine, then run:

```bash
python -m tools.natural_earth.build_catalog build \
  --gpkg /data/natural_earth_vector.gpkg \
  --out /data/catalog.sqlite

python -m tools.natural_earth.build_catalog search \
  --db /data/catalog.sqlite --type country --query Brasil

python -m tools.natural_earth.build_catalog search \
  --db /data/catalog.sqlite --type state --query "Sao Paulo"

python -m tools.natural_earth.build_catalog search \
  --db /data/catalog.sqlite --type city --query "Paris"
```

The C++ executable `cartorig_ne_lookup` makes the same searches without Python at runtime:

```text
cartorig_ne_lookup /data/catalog.sqlite country Brasil
cartorig_ne_lookup /data/catalog.sqlite city "São Paulo"
```

### Run the completeness gate

```bash
python -m tools.natural_earth.coverage \
  --vector-pin data/natural-earth/vector_layers_v5.1.2.json \
  --catalog /data/catalog.sqlite \
  --sources build/natural-earth/official_sources.json \
  --archives build/natural-earth/data/source-archives.json \
  --raster-derivatives /data/validated-raster-assets.json \
  --output build/natural-earth/coverage-report.json
```

The gate intentionally **fails** until every archived source and raster derivative is verified, and every expected vector layer is represented. Country name search alone cannot pass that gate.

## Next engineering gates (not complete)

1. Extract the real complete vector GeoPackage and measure actual layer coverage, parse failures, features and geometry schemas; compare every layer to the 215 pinned source layers.
2. Map named regions to actual geometries at 10m / 50m / 110m, then implement the C++ typed Point/Line/Polygon renderer, LOD and antimeridian stress tests.
3. Implement raster preparation (GeoTIFF overviews/tiles, 52 discovered variants, memory budgets, transparent composition) and record all per-source hashes.
4. Build the Offline Natural Earth Data Pack installer with atomic install/rollback and a persistent pack ID; no runtime network access.
5. Integrate the C++ SQLite search into the Edit-first Geographic Region UI, with independent region styles and animations. The OpenFX host's ability to update dropdown choices dynamically still requires Resolve 20 validation.
6. Run offline network-denial and export tests in Resolve 20; promote to `Natural Earth Complete` only if the coverage gate passes without exceptions.

## Provenance

- https://www.naturalearthdata.com/downloads/
- https://www.naturalearthdata.com/about/terms-of-use/
- https://github.com/nvkelso/natural-earth-vector/releases/tag/v5.1.2
- https://www.sqlite.org/fts5.html
- https://www.sqlite.org/rtree.html

Natural Earth content is public domain. CartoRig's implementation code remains under this repository's license. It is useful to credit: *Made with Natural Earth*.
