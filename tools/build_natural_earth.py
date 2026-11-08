"""Build pinned-source Natural Earth GeoJSON runtime assets on CI/build host.

Requires pyshp only during build; the installed CartoRig runs offline with no Python.
The project does NOT request automatic runtime downloads.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import urllib.request
import zipfile
from pathlib import Path

DATASETS = {
    "admin0": ("10m_cultural", "ne_10m_admin_0_countries"),
    "admin1": ("10m_cultural", "ne_10m_admin_1_states_provinces"),
    "cities": ("10m_cultural", "ne_10m_populated_places"),
    "land": ("10m_physical", "ne_10m_land"),
    "coastline": ("10m_physical", "ne_10m_coastline"),
    "lakes": ("10m_physical", "ne_10m_lakes"),
    "boundaries": ("10m_cultural", "ne_10m_admin_0_boundary_lines_land"),
}

def convert_zip(content: bytes, stem: str) -> dict:
    """Read Shapefile directly from ZIP with pyshp; reject malformed or missing parts."""
    import shapefile
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        assert archive.testzip() is None, "corrupt Natural Earth ZIP"
        def match(ext):
            names = [name for name in archive.namelist() if name.lower().endswith(ext) and Path(name).stem == stem]
            if len(names) != 1:
                raise ValueError(f"expected one {stem}{ext} in dataset ZIP")
            return archive.read(names[0])
        shx, shp, dbf = match('.shx'), match('.shp'), match('.dbf')
    reader = shapefile.Reader(shp=io.BytesIO(shp), shx=io.BytesIO(shx), dbf=io.BytesIO(dbf), encoding='utf-8')
    fields = [fld[0] for fld in reader.fields[1:]]
    features = []
    for n, entry in enumerate(reader.iterShapeRecords()):
        props = {name: value for name, value in zip(fields, entry.record)}
        for key, value in list(props.items()):
            if not isinstance(value, (str, int, float, bool, type(None))):
                props[key] = str(value)
        geometry = entry.shape.__geo_interface__
        if geometry.get('type') not in {'Point', 'Polygon', 'MultiPolygon', 'LineString', 'MultiLineString'}:
            raise ValueError(f"unsupported Natural Earth geometry {geometry.get('type')} in {stem} at {n}")
        features.append({'type': 'Feature', 'properties': props, 'geometry': geometry})
    if not features:
        raise ValueError(f"empty Natural Earth feature set {stem}")
    return {'type': 'FeatureCollection', 'name': stem, 'features': features}

def build(out: Path, selected, pins: dict[str, str]) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    manifest = {'bundle': 'natural-earth-10m', 'release_type': 'data-pack', 'online_runtime': False, 'datasets': []}
    for name in selected:
        group, stem = DATASETS[name]
        url = f'https://naturalearth.s3.amazonaws.com/{group}/{stem}.zip'
        with urllib.request.urlopen(url, timeout=90) as resp:
            zipped = resp.read(200 * 1024 * 1024 + 1)
        if len(zipped) > 200 * 1024 * 1024:
            raise ValueError(f'archive exceeds 200 MiB: {stem}')
        digest = hashlib.sha256(zipped).hexdigest()
        if pins.get(name) and pins[name] != digest:
            raise ValueError(f'SHA256 mismatch for {stem}, expected {pins[name]}, got {digest}')
        feature_collection = convert_zip(zipped, stem)
        filename = f'{stem}.geojson'
        content = json.dumps(feature_collection, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode('utf-8')
        (out / filename).write_bytes(content)
        manifest['datasets'].append({'id': name, 'filename': filename, 'scale': '10m',
                                     'feature_count': len(feature_collection['features']),
                                     'source': url, 'source_zip_sha256': digest,
                                     'output_sha256': hashlib.sha256(content).hexdigest(),
                                     'license': 'Natural Earth public domain'})
        print(f'{stem}: {len(feature_collection["features"])} features / {len(content):,} bytes', flush=True)
    (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    return manifest

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('dist/natural-earth-10m'))
    parser.add_argument('--dataset', action='append', choices=sorted(DATASETS))
    parser.add_argument('--pins-json', type=Path, help='Optional approved SHA256 map, checked before conversion')
    args = parser.parse_args()
    pins = json.loads(args.pins_json.read_text(encoding='utf-8')) if args.pins_json else {}
    build(args.output, args.dataset or list(DATASETS), pins)
