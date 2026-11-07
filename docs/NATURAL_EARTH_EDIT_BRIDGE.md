# Natural Earth country rendering — Resolve 20 Edit-first test

Status: **v0.4.0-dev experimental**. All UI labels in English; the plugin performs no HTTP/HTTPS requests. The complete vector *source inventory* has passed the 215/215 real-data audit, but the full Natural Earth raster pack and all layer renderers are **not** shipped.

## Data preparation — release developer machine only

1. Obtain the publisher's [Natural Earth all-vector GeoPackage ZIP](https://naciscdn.org/naturalearth/packages/natural_earth_vector.gpkg.zip). The verified source archive SHA256 (Nov 2026) is:
   `b9e2e7b3d5c2c59593f6eafc19be2ba87fb04788a90c57ccd6cf32a587b6ecc3`
2. Extract `natural_earth_vector.gpkg` to a permanent local data directory, e.g. `D:\\CartoRigData\\natural_earth_vector.gpkg`. This file alone covers 182 of the 215 source-vector layers but **contains all country layers required by the current renderer**.
3. To rebuild the 33 missing layers on a release machine, run:

```powershell
python -m tools.natural_earth.supplements `
  --manifest data/natural-earth/aggregate_geojson_supplements_v5.1.2.json `
  --sources-dir D:\CartoRigData\supplements-source `
  --out D:\CartoRigData\natural_earth_supplement.gpkg `
  --report D:\CartoRigData\supplements-report.json `
  --fetch-official
```

The `--fetch-official` switch is explicitly allowed **only on the producer's machine**. The user-facing Resolve runtime never executes Python or downloads map data. The supplemental GeoPackage is currently used for the vector completeness report and future non-country layers; it is not yet automatically composited in the Edit Viewer.

## In DaVinci Resolve Studio 20 (Edit)

1. Install the experimental v0.4 OpenFX bundle; close/restart Resolve after installation. For regression isolation, create a new timeline and insert a **new** `CartoRig Map (Edit)`.
2. In **Inspector → Advanced: import custom scenes**, set **Vector GeoPackage** to the local `natural_earth_vector.gpkg` file.
3. Set **Vector detail** to **Auto (zoom dependent)** or select 110m, 50m or 10m manually. Auto switches at camera zoom 3.5 and 7.0. The map remains static unless you create keyframes.
4. Adjust the existing camera controls. Territory ISO3 highlighting and route controls remain available from the current Inspector. Neither the Vector GeoPackage nor any data source can access the network.
5. To compare with the previous map or recover older behavior, clear **Vector GeoPackage**. The default bundled country GeoJSON is still used.

**Data-source priority:** embedded GeoJSON → explicit GeoJSON path → Natural Earth GeoPackage → bundled GeoJSON. This prevents overwriting user-authored scenes.

### Must be verified in the actual host

- Loading the GeoPackage in Resolve 20 without a missing-DLL error on Windows.
- Rendering with each vector scale, seeking, caching, zoom transitions, and saving/reopening project.
- CPU and RAM usage on the 10m dataset at 1440p and 4K, both Generator and Overlay.
- Highlighting independent countries and avoiding antimeridian seams while crossing the date line.
- Confirming v0.4.0-dev and source commit in **Installed plugin build**.

CI tests are **not a replacement** for these host checks. The full Geographic Region search UI and per-region colors remain pending.

## Published evidence

- Natural Earth full vector coverage 215/215: `tools/natural_earth/probe_vector_complete.py`, including 33 source-pinned supplemental GeoJSON datasets.
- Real country raster path: C++ `NaturalEarthCatalog::countryPolygons()` → `cartorig::Dataset` → existing CPU renderer at all three scales.
- Parallel Windows/Linux CMake, CTest, ASAN/UBSAN and OpenFX simulated host runs.
- The complete **Natural Earth** claim is intentionally blocked until every raster family and source variant is acquired, converted and checked.


## Experimental optional typed vector overlay (v0.4.0-dev, after 215-layer audit)

The **Advanced: import custom scenes** section now includes:

- **Vector GeoPackage:** the primary official aggregate GeoPackage for country base rendering.
- **Vector detail:** Auto / 110m / 50m / 10m, unchanged.
- **Additional vector layer (ne_...):** an exact SQLite table name (for example,
  `ne_10m_rivers_lake_centerlines`, `ne_10m_populated_places`, or
  `ne_10m_admin_1_states_provinces`). Blank disables the overlay entirely.
- **Additional layer GeoPackage (optional):** a separate path for the supplemental
  33-layer GeoPackage. Blank reads the additional layer from the primary GeoPackage.
  Using a separate path does not replace the country base.

The typed C++ reader supports GeoPackage Point/MultiPoint, LineString/MultiLineString
and Polygon/MultiPolygon including polygon holes. It validates source table identifiers
and EPSG:4326, reads strictly in read-only mode, bounds rows to 20,000 and total vertices
to 2,000,000, and fails explicitly rather than partially drawing an oversized table.
The renderer overlays polygons, antimeridian-unwrapped lines, and point markers onto
the existing map. It uses fixed diagnostic colors in this iteration; individual
styling, a dropdown/catalog picker, viewport streaming, raster sources and selection
by click are **not** implemented.

### Manual host acceptance for this experimental addition

1. Open a new CartoRig Map or Overlay in Resolve 20 Edit; verify blank
   **Additional vector layer** keeps the previous default output unchanged.
2. Supply the verified primary `natural_earth_vector.gpkg`; choose
   `ne_10m_rivers_lake_centerlines`, then inspect expected river strokes.
3. Change the selected layer to `ne_10m_populated_places`; verify point symbols.
   Try `ne_10m_admin_1_states_provinces` to inspect actual polygons.
4. Use the **Additional layer GeoPackage** path to choose a verified supplemental
   GeoPackage table while retaining the original country basemap.
5. Scrub/seek, zoom across the antimeridian, render 4K, save/reopen the project
   and compare frames. Test both Generator and Overlay against video.
6. Try a nonexistent layer or invalid file path; it must report failure rather
   than download or silently fabricate geographic data.

The offline synthetic C++ test checks rendering of all three geometry families and
rejection of injected SQL table-name text. This is **not** a substitute for host
acceptance or publisher-wide render certification. Do not treat the 215/215 source
audit as proof that every layer is drawable within the current 20k-feature budget.
