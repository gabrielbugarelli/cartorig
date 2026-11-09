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

def search_metadata(feature: dict, dataset_id: str, item_index: int, dataset_version: str) -> dict | None:
    """Create a small search record without embedding a megabyte-scale polygon."""
    p = feature.get('properties') or {}
    geo = feature.get('geometry') or {}
    kind = {'admin0':'Country','admin1':'State','cities':'City'}.get(dataset_id)
    if kind is None:
        return None
    def text(*names):
        for name in names:
            value = p.get(name)
            if value is not None and str(value).strip() and str(value) != '-99':
                return str(value).strip()
        return None
    name = text('NAME','name','NAME_EN','NAME_LONG','ADMIN')
    if not name:
        return None
    country = text('ADMIN','ADM0NAME','SOV0NAME','SOVEREIGNT')
    state = text('ADM1NAME','name_adm1')
    parent = 'World' if kind=='Country' else country or 'Unknown'
    if kind=='City' and state:
        parent = state + ', ' + parent
    coords = geo.get('coordinates')
    point = None
    if geo.get('type')=='Point' and isinstance(coords,(list,tuple)) and len(coords)>=2:
        point = {'lon':coords[0],'lat':coords[1]}
    else:
        lon,lat=p.get('LABEL_X'),p.get('LABEL_Y')
        if isinstance(lon,(float,int)) and isinstance(lat,(float,int)):
            point={'lon':lon,'lat':lat}
    aliases = list(dict.fromkeys(str(v) for v in [name,p.get('NAMEASCII'),p.get('NAME_EN'),p.get('NAME_LONG'),p.get('NAME_ALT')] if isinstance(v,str) and v))
    if name=='Brazil' and 'Brasil' not in aliases:
        aliases.append('Brasil')
    return {'id':f'natural-earth:{dataset_id}:{text("NE_ID","ne_id") or item_index}',
            'kind':kind,'name':name,'parent':parent,'aliases':aliases,
            'geometryType':geo.get('type'),'point':point,
            'continent':text('CONTINENT','continent'),
            'source':{'dataset':dataset_id,'version':dataset_version,'scale':'10m'}}

def continent_records(searchable: list[dict], dataset_version: str) -> list[dict]:
    """Composite country groupings only, never invented continent geometry."""
    continents = {}
    for feature in searchable:
        if feature['kind'] == 'Country' and feature.get('continent'):
            continents.setdefault(feature['continent'], []).append(feature['id'])
    return [
        {'id':'natural-earth:continent:'+''.join(c for c in name.lower() if c.isascii() and c.isalnum()),
         'name':name,'kind':'Continent','parent':'World','aliases':[name],
         'geometryType':'Composite','memberIds':sorted(members),
         'source':{'dataset':'admin0-continent-composite','version':dataset_version,'scale':'10m'}}
        for name,members in sorted(continents.items())
    ]

def build(out: Path, selected, pins: dict[str, str]) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    manifest = {'bundle': 'natural-earth-10m', 'release_type': 'data-pack', 'online_runtime': False, 'datasets': []}
    searchable = []
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
        if name in ('admin0','admin1','cities'):
            geo_linefile = out / f'features_{name}.jsonl'
            with geo_linefile.open('wb') as stream:
                for index, feature in enumerate(feature_collection['features']):
                    encoded = (json.dumps(feature, ensure_ascii=False, separators=(',',':'),allow_nan=False)+'\n').encode('utf-8')
                    offset=stream.tell()
                    stream.write(encoded)
                    metadata=search_metadata(feature,name,index,digest)
                    if metadata:
                        metadata['featureFile']=geo_linefile.name
                        metadata['featureOffset']=offset
                        metadata['featureBytes']=len(encoded)
                        searchable.append(metadata)
            manifest.setdefault('index_files', []).append({'filename':geo_linefile.name,'sha256':hashlib.sha256(geo_linefile.read_bytes()).hexdigest()})
        manifest['datasets'].append({'id': name, 'filename': filename, 'scale': '10m',
                                     'feature_count': len(feature_collection['features']),
                                     'source': url, 'source_zip_sha256': digest,
                                     'output_sha256': hashlib.sha256(content).hexdigest(),
                                     'license': 'Natural Earth public domain'})
        print(f'{stem}: {len(feature_collection["features"])} features / {len(content):,} bytes', flush=True)
    searchable.extend(continent_records(searchable, manifest['bundle']))
    index_file=out / 'catalog_index.json'
    index_raw=json.dumps({'schema':'cartorig.offline.catalog/1','bundle':'natural-earth-10m','locations':searchable},
                         ensure_ascii=False,separators=(',',':'),allow_nan=False).encode('utf-8')
    index_file.write_bytes(index_raw)
    manifest['catalog_index']={'filename':index_file.name,'sha256':hashlib.sha256(index_raw).hexdigest(),
                               'location_count':len(searchable)}
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
