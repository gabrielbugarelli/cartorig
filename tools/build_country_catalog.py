"""Reproducible, build-time Natural Earth geometry conversion; not required by users.

Usage: python tools/build_country_catalog.py /path/to/ne_110m_admin_0_countries.geojson output.lua
This module is NEW code and includes no GIS code from previous CartoRig versions.
"""
import argparse, json, math, unicodedata
from pathlib import Path
from shapely.geometry import shape, box
from shapely.ops import unary_union


def lua_string(s):
    return json.dumps(str(s), ensure_ascii=False).replace('\\u', '\\u')

def rings(geometry, tolerance=.10):
    if geometry is None or geometry.is_empty: return []
    if not geometry.is_valid: geometry=geometry.buffer(0)
    geometry=geometry.simplify(tolerance, preserve_topology=True)
    geoms= [geometry] if geometry.geom_type=='Polygon' else list(geometry.geoms) if geometry.geom_type=='MultiPolygon' else []
    polygons=[]
    for poly in geoms:
        ext=list(poly.exterior.coords)
        if len(ext)>3:
            polygons.append([[(round(x,5),round(y,5)) for x,y in ext[:-1]]])
            for hole in poly.interiors:
                pts=list(hole.coords)[:-1]
                if len(pts)>2: polygons[-1].append([(round(x,5),round(y,5)) for x,y in pts])
    return polygons

def lua_point(p):return '{' + ','.join(f'{v:.5f}' for v in p) + '}'
def lua_geometry(polys):return '{' + ','.join('{' + ','.join('{' + ','.join(lua_point(p) for p in ring) + '}' for ring in poly) + '}' for poly in polys) + '}'

def build(data):
    out=['-- Generated from Natural Earth public-domain source; do not edit by hand.', 'return {']
    country_geoms=[]
    continents={}
    for f in sorted(data['features'],key=lambda f:str(f['properties'].get('NAME_EN') or f['properties'].get('name') or f['properties'].get('NAME'))):
        p=f['properties']; name=p.get('NAME_EN') or p.get('name') or p.get('NAME')
        if not name:continue
        iso=p.get('ADM0_A3') or p.get('iso_a3') or p.get('ISO_A3') or p.get('SOV_A3') or ''
        if iso=='-99': iso=p.get('ADM0_A3') or 'UNK'
        geo=shape(f['geometry']);polys=rings(geo)
        if not polys:continue
        country_geoms.append(geo)
        continent=p.get('CONTINENT') or p.get('continent')
        if continent in {'Africa','Antarctica','Asia','Europe','North America','Oceania','South America'}:
            continents.setdefault(continent,[]).append(geo)
        aliases=list(dict.fromkeys(filter(None,[p.get('NAME_PT'),p.get('NAME_LONG'),p.get('name'),p.get('NAME'),p.get('ADMIN')])))
        if iso=='BRA': aliases.insert(0,'Brasil')
        anchor=geo.representative_point()
        out.append('{id=' + lua_string('ne110:'+str(iso)+':'+str(name)) + ',kind="Country",name='+lua_string(name)+',parent="World",code='+lua_string(iso)+',aliases={' + ','.join(lua_string(x) for x in aliases[:8]) + '},lon='+str(round(anchor.x,5))+',lat='+str(round(anchor.y,5))+',polygons='+lua_geometry(polys)+'},')
    # Continent objects are explicitly derived from Natural Earth country attribution.
    # Transcontinental country grouping follows the publisher's recorded continent attribute.
    for continent,parts in sorted(continents.items()):
        geom=unary_union(parts)
        anchor=geom.representative_point()
        out.append('{id='+lua_string('ne110:continent:'+continent)+',kind="Continent",name='+lua_string(continent)+',parent="World",lon='+str(round(anchor.x,5))+',lat='+str(round(anchor.y,5))+',polygons='+lua_geometry(rings(geom,.2))+'},')
    land=unary_union(country_geoms)
    landp=rings(land,.2)
    out.append('{id="ne110:world-land",kind="Internal",name="World land",parent="World",polygons='+lua_geometry(landp)+'},')
    out.append('}')
    return '\n'.join(out)+'\n',len(country_geoms),len(landp)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('geojson');ap.add_argument('output');args=ap.parse_args()
    text,count,land=build(json.loads(Path(args.geojson).read_text(encoding='utf-8')))
    Path(args.output).write_text(text,encoding='utf-8');print('countries=',count,'land polygons=',land,'bytes=',len(text.encode()))
