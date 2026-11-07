#!/usr/bin/env python3
"""Rebuild the 33 missing Natural Earth 5.1.2 vector layers offline.

Only the explicitly requested --fetch-official operation makes HTTPS requests,
on a release-building machine. Every file must match the pinned upstream Git
blob SHA1 AND size. Generated GeoPackage stores original GeoJSON attributes in
attributes_json and EPSG:4326 OGC WKB geometry in standard GeoPackage BLOBs.
The OpenFX runtime never imports this module and never accesses the network.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import struct
import urllib.parse
import urllib.request

BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/"
MAX_FILE = 20_000_000
MAX_SOURCE_TOTAL = 200_000_000
LAYER_RE = re.compile(r"^ne_(?:10|50|110)m_[A-Za-z0-9_]+$")
TYPES = {"Point":1,"LineString":2,"Polygon":3,"MultiPoint":4,
         "MultiLineString":5,"MultiPolygon":6,"GeometryCollection":7}
WGS84 = ('GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",'
         '6378137,298.257223563]],PRIMEM["Greenwich",0],'
         'UNIT["degree",0.0174532925199433]]')

def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

def manifest_entries(manifest: dict) -> list[dict]:
    if manifest.get("schema_version")!=1 or manifest.get("upstream_ref")!="v5.1.2":
        raise ValueError("invalid or unpinned Natural Earth supplemental manifest")
    entries=manifest.get("entries",[])
    if len(entries)!=33 or manifest.get("count")!=33:
        raise ValueError("missing supplemental Natural Earth layer definitions")
    names=set()
    for row in entries:
        name=row.get("layer","")
        path=row.get("source_geojson_path","")
        digest=row.get("pinned_git_blob_sha1","")
        if (not LAYER_RE.fullmatch(name) or path!="geojson/"+name+".geojson"
                or not re.fullmatch(r"[0-9a-f]{40}",digest)
                or not 0<row.get("bytes",0)<=MAX_FILE or name in names):
            raise ValueError("invalid or duplicate supplemental layer entry: "+name)
        names.add(name)
    return entries

def fetch_official(entries: list[dict],directory: Path) -> None:
    """Intentional acquisition-only operation, never part of plugin runtime."""
    directory.mkdir(parents=True,exist_ok=True)
    for row in entries:
        destination=directory/(row["layer"]+".geojson")
        if destination.is_file():
            data=destination.read_bytes()
            if len(data)==row["bytes"] and git_blob_sha(data)==row["pinned_git_blob_sha1"]:
                continue
        address=BASE+urllib.parse.quote(row["source_geojson_path"],safe="/")
        request=urllib.request.Request(address,headers={"User-Agent":"CartoRigNaturalEarthBuild/0.2"})
        with urllib.request.urlopen(request,timeout=90) as response:
            if urllib.parse.urlsplit(response.url).hostname!="raw.githubusercontent.com":
                raise ValueError("official asset redirect left pinned GitHub host")
            data=response.read(MAX_FILE+1)
        verify_source(row,data)
        tmp=destination.with_suffix(".geojson.part")
        try:
            tmp.write_bytes(data)
            tmp.replace(destination)
        finally:tmp.unlink(missing_ok=True)

def verify_source(row: dict,data: bytes) -> str:
    if len(data)!=row["bytes"] or len(data)>MAX_FILE:
        raise ValueError("Natural Earth layer size differs from pinned upstream")
    if git_blob_sha(data)!=row["pinned_git_blob_sha1"]:
        raise ValueError("Natural Earth Git blob checksum mismatch: "+row["layer"])
    return hashlib.sha256(data).hexdigest()

def coords(point:list|tuple) -> tuple[float,float]:
    if not isinstance(point,(list,tuple)) or len(point)<2:
        raise ValueError("invalid GeoJSON coordinate")
    lon,lat=point[:2]
    if not isinstance(lon,(float,int)) or not isinstance(lat,(float,int)):
        raise ValueError("non-numeric GeoJSON coordinate")
    lon,lat=float(lon),float(lat)
    if not(math.isfinite(lon) and math.isfinite(lat)) or abs(lon)>540 or abs(lat)>90:
        raise ValueError("invalid geographic coordinate values")
    return lon,lat

def wkb(geometry: dict) -> tuple[bytes,list[tuple[float,float]]]:
    """Little-endian OGC WKB, same seven geometry types as C++ decoder."""
    if not isinstance(geometry,dict):
        raise ValueError("null geometry unsupported in supplemental layers")
    typ=geometry.get("type")
    if typ not in TYPES:
        raise ValueError("unsupported GeoJSON geometry: "+str(typ))
    header=b"\x01"+struct.pack("<I",TYPES[typ])
    points:list[tuple[float,float]]=[]
    def single(p):
        xy=coords(p)
        points.append(xy)
        return struct.pack("<dd",*xy)
    def line(values):
        if not isinstance(values,list):
            raise ValueError("invalid GeoJSON LineString")
        return struct.pack("<I",len(values))+b"".join(single(p) for p in values)
    def polygon(values):
        if not isinstance(values,list):
            raise ValueError("invalid GeoJSON Polygon")
        rings=[]
        for raw in values:
            if len(raw)<4 or coords(raw[0])!=coords(raw[-1]):
                raise ValueError("GeoJSON Polygon ring is not closed")
            rings.append(line(raw))
        return struct.pack("<I",len(rings))+b"".join(rings)
    value=geometry.get("coordinates")
    if typ=="Point":body=single(value)
    elif typ=="LineString":body=line(value)
    elif typ=="Polygon":body=polygon(value)
    else:
        if typ=="GeometryCollection":
            items=geometry.get("geometries")
            if not isinstance(items,list):raise ValueError("missing geometries")
        else:
            if not isinstance(value,list):raise ValueError("invalid multipart geometry")
            child={"MultiPoint":"Point","MultiLineString":"LineString",
                   "MultiPolygon":"Polygon"}[typ]
            items=[{"type":child,"coordinates":part} for part in value]
        encoded=[]
        for part in items:
            binary,child_points=wkb(part)
            encoded.append(binary)
            points.extend(child_points)
        body=struct.pack("<I",len(encoded))+b"".join(encoded)
    return header+body,points

def as_geopackage_blob(geometry: dict) -> tuple[bytes,list[tuple[float,float]]]:
    binary,vertices=wkb(geometry)
    return b"GP\x00\x01"+struct.pack("<i",4326)+binary,vertices

def create_geopackage(manifest:dict,directory:Path,output:Path) -> dict:
    entries=manifest_entries(manifest)
    total=0
    checked=[]
    for row in entries:
        file=directory/(row["layer"]+".geojson")
        if not file.is_file():
            raise FileNotFoundError("Natural Earth supplement missing: "+str(file))
        data=file.read_bytes()
        total+=len(data)
        if total>MAX_SOURCE_TOTAL:raise ValueError("supplement source exceeds global limit")
        sha=verify_source(row,data)
        checked.append((row,data,sha))
    output.parent.mkdir(parents=True,exist_ok=True)
    tmp=output.with_name(output.name+".tmp")
    tmp.unlink(missing_ok=True)
    con=sqlite3.connect(tmp)
    report={"source_release":"v5.1.2","expected":33,"imported":0,"features":0,
            "source_bytes":total,"sources":[],"complete":False}
    try:
        con.executescript("""
          PRAGMA journal_mode=DELETE;
          PRAGMA synchronous=FULL;
          CREATE TABLE gpkg_spatial_ref_sys(
            srs_name TEXT NOT NULL,srs_id INTEGER NOT NULL PRIMARY KEY,
            organization TEXT NOT NULL,organization_coordsys_id INTEGER NOT NULL,
            definition TEXT NOT NULL,description TEXT);
          CREATE TABLE gpkg_contents(
            table_name TEXT NOT NULL PRIMARY KEY,data_type TEXT NOT NULL,
            identifier TEXT UNIQUE,description TEXT DEFAULT '',
            last_change TEXT NOT NULL DEFAULT '2026-11-06T00:00:00.000Z',
            min_x DOUBLE,min_y DOUBLE,max_x DOUBLE,max_y DOUBLE,srs_id INTEGER);
          CREATE TABLE gpkg_geometry_columns(
            table_name TEXT NOT NULL,column_name TEXT NOT NULL,
            geometry_type_name TEXT NOT NULL,srs_id INTEGER NOT NULL,
            z TINYINT NOT NULL,m TINYINT NOT NULL,
            PRIMARY KEY(table_name,column_name));
          CREATE TABLE provenance(
            table_name TEXT PRIMARY KEY,upstream_path TEXT NOT NULL,
            upstream_git_blob_sha1 TEXT NOT NULL,sha256 TEXT NOT NULL,
            feature_count INTEGER NOT NULL);
        """)
        con.execute("INSERT INTO gpkg_spatial_ref_sys VALUES(?,?,?,?,?,?)",
                    ("WGS 84 geodetic",4326,"EPSG",4326,WGS84,"Natural Earth WGS84"))
        for row,data,sha in checked:
            layer=row["layer"]
            doc=json.loads(data.decode("utf-8"))
            if not isinstance(doc,dict) or doc.get("type")!="FeatureCollection":
                raise ValueError("source layer is not a GeoJSON FeatureCollection: "+layer)
            features=doc.get("features")
            if not isinstance(features,list):
                raise ValueError("invalid GeoJSON features: "+layer)
            geoms=[]
            bbox=[math.inf,math.inf,-math.inf,-math.inf]
            for f in features:
                if not isinstance(f,dict) or f.get("type")!="Feature":
                    raise ValueError("non-Feature record in source layer")
                properties=f.get("properties")
                if not isinstance(properties,dict):properties={}
                blob,vertices=as_geopackage_blob(f.get("geometry"))
                for x,y in vertices:
                    bbox=[min(bbox[0],x),min(bbox[1],y),
                          max(bbox[2],x),max(bbox[3],y)]
                geom_type=f["geometry"]["type"].upper()
                geoms.append((geom_type,blob,json.dumps(properties,ensure_ascii=False,
                                                        sort_keys=True,separators=(",",":"))))
            # GeoPackage layer declared to the single type if uniform;
            # GEOMETRY is valid when an upstream layer is mixed.
            kinds={entry[0] for entry in geoms}
            gtype=next(iter(kinds)) if len(kinds)==1 else "GEOMETRY"
            # All layer/table identifiers have already passed a strict regex.
            con.execute(f'CREATE TABLE "{layer}"('
                        "fid INTEGER PRIMARY KEY,geom BLOB NOT NULL,"
                        "attributes_json TEXT NOT NULL)")
            con.executemany(f'INSERT INTO "{layer}"(geom,attributes_json) VALUES(?,?)',
                            [(geom,attrs) for _,geom,attrs in geoms])
            bounds=bbox if math.isfinite(bbox[0]) else [None,None,None,None]
            con.execute("INSERT INTO gpkg_contents(table_name,data_type,identifier,"
                        "description,min_x,min_y,max_x,max_y,srs_id)"
                        " VALUES(?,?,?,?,?,?,?,?,?)",
                        (layer,"features",layer,"Official Natural Earth v5.1.2 supplemental layer",
                         *bounds,4326))
            con.execute("INSERT INTO gpkg_geometry_columns VALUES(?,?,?,?,?,?)",
                        (layer,"geom",gtype,4326,0,0))
            con.execute("INSERT INTO provenance VALUES(?,?,?,?,?)",
                        (layer,row["source_geojson_path"],row["pinned_git_blob_sha1"],
                         sha,len(geoms)))
            report["sources"].append({"layer":layer,"features":len(geoms),
                "git_blob_sha1":row["pinned_git_blob_sha1"],"sha256":sha})
            report["imported"]+=1
            report["features"]+=len(geoms)
        con.commit()
        if con.execute("PRAGMA integrity_check").fetchone()[0]!="ok":
            raise RuntimeError("supplemental GeoPackage integrity check failed")
        report["complete"]=report["imported"]==33
        con.close()
        tmp.replace(output)
        return report
    except Exception:
        con.close()
        tmp.unlink(missing_ok=True)
        raise

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest",type=Path,required=True)
    p.add_argument("--sources-dir",type=Path,required=True)
    p.add_argument("--out",type=Path,required=True)
    p.add_argument("--report",type=Path,required=True)
    p.add_argument("--fetch-official",action="store_true",
                   help="Explicitly allow producer-only HTTPS to raw.githubusercontent.com")
    a=p.parse_args()
    manifest=json.loads(a.manifest.read_text(encoding="utf-8"))
    entries=manifest_entries(manifest)
    if a.fetch_official:fetch_official(entries,a.sources_dir)
    report=create_geopackage(manifest,a.sources_dir,a.out)
    a.report.parent.mkdir(parents=True,exist_ok=True)
    a.report.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"complete":report["complete"],"layers":report["imported"],
                      "features":report["features"]},indent=2))

if __name__=="__main__":main()
