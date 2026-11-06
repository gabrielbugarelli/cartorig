#!/usr/bin/env python3
"""Build a read-only, portable, OFFLINE Natural Earth geographic search catalog.

Inputs: a locally obtained, trusted Natural Earth all-vectors GeoPackage.
Output: a separate SQLite FTS5/RTree index; the original GeoPackage remains
untouched and must ship with the data pack. Geometry is never fabricated.
Build tool has NO network calls and requires only Python standard library.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import tempfile
from urllib.parse import quote
import unicodedata

REGION_TYPES = ("continent", "country", "state", "city")
SCALE_PRIORITY = {"10m": 0, "50m": 1, "110m": 2}
NAMES = ("name", "name_en", "name_pt", "name_long", "nameascii", "name_alt",
         "formal_en", "formal_fr", "brk_name", "admin", "name_sort")
CODES = ("adm0_a3", "iso_a3", "sov_a3", "postal")
NAME_PATTERN = re.compile(r"^(name(?:_[a-z]{2,4})?|nameascii|name_long|name_alt|formal_en|formal_fr|brk_name|admin)$",re.I)
TOKEN = re.compile(r"[^\W_]+",re.UNICODE)

def quote_sql(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'

def source_connection(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise FileNotFoundError(path)
    con = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    if not con.execute("SELECT 1 FROM sqlite_master WHERE name='gpkg_contents'").fetchone():
        con.close()
        raise ValueError("source is not a GeoPackage with gpkg_contents")
    return con

def category(table: str) -> str | None:
    name = table.lower()
    if "admin_0_countries" in name and not any(x in name for x in
        ("_lakes", "_pov", "scale_rank", "_points", "_lines", "_outline")):
        # A POV-specific country layer is still cataloged, but does not
        # override the de-facto default search result automatically.
        return "country"
    if "admin_1_states_provinces" in name and not any(x in name for x in
        ("_lines", "_scale_rank", "_lakes")):
        return "state"
    if "populated_places" in name and not name.endswith("_simple"):
        return "city"
    return None

def scale_for(table: str) -> str | None:
    for scale in ("10m", "50m", "110m"):
        if table.lower().startswith("ne_" + scale + "_"):
            return scale
    return None

def aliases(row: sqlite3.Row, typ: str) -> list[tuple[str,str]]:
    result: list[tuple[str,str]] = []
    seen = set()
    for key in row.keys():
        low = key.lower()
        if NAME_PATTERN.match(low) or (typ == "country" and low in CODES):
            value = row[key]
            if not isinstance(value, str):
                continue
            value = " ".join(value.strip().split())
            folded = unicodedata.normalize("NFKC",value).casefold()
            if not value or folded in seen:
                continue
            seen.add(folded)
            language = low[5:] if low.startswith("name_") and len(low)==7 else ""
            result.append((value,language))
    return result

def display(row: sqlite3.Row, typ: str) -> str:
    fields = {name.lower():name for name in row.keys()}
    for key in ("name_en","name","name_long","nameascii","admin"):
        if key in fields and isinstance(row[fields[key]],str) and row[fields[key]].strip():
            return row[fields[key]].strip()
    return "(unnamed)"

def parent_name(row: sqlite3.Row, typ: str) -> str:
    fields = {name.lower():name for name in row.keys()}
    keys = ("adm0name","admin","geonunit","sov0name") if typ in ("state","city") else ("continent",)
    for key in keys:
        if key in fields and isinstance(row[fields[key]],str) and row[fields[key]].strip():
            return row[fields[key]].strip()
    return ""

def index_source(source: Path, output: Path) -> dict:
    """Atomic creation; do not leave a partially-built DB on failure."""
    if not source.is_file():
        raise FileNotFoundError(source)
    output.parent.mkdir(parents=True,exist_ok=True)
    temp = output.with_name(output.name + ".tmp")
    temp.unlink(missing_ok=True)
    inp = source_connection(source)
    dst = sqlite3.connect(temp)
    summary = {"input":source.name,"all_layers":0,"region_layers":0,"region_records":0,
               "names":0,"regions_by_type":{},"complete":False}
    try:
        dst.executescript("""
            PRAGMA journal_mode=DELETE;
            PRAGMA synchronous=FULL;
            CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE layers(
                table_name TEXT PRIMARY KEY, theme TEXT, scale TEXT,
                geometry_type TEXT, feature_count INTEGER NOT NULL, indexed_regions INTEGER NOT NULL
            );
            CREATE TABLE regions(
                region_id INTEGER PRIMARY KEY, feature_key TEXT UNIQUE NOT NULL,
                kind TEXT NOT NULL, display_name TEXT NOT NULL, parent_name TEXT,
                geometry_type TEXT NOT NULL, source_layer TEXT NOT NULL,
                source_rowid INTEGER NOT NULL, scale TEXT NOT NULL
            );
            CREATE VIRTUAL TABLE search_fts USING fts5(
                alias, region_id UNINDEXED,
                tokenize='unicode61 remove_diacritics 2'
            );
            CREATE VIRTUAL TABLE region_bounds USING rtree(
                region_id, minx, maxx, miny, maxy
            );
            CREATE INDEX region_type_name ON regions(kind,display_name);
            CREATE INDEX region_source ON regions(source_layer,source_rowid);
        """)
        content = inp.execute("""
            SELECT table_name,data_type FROM gpkg_contents
            WHERE data_type='features' ORDER BY table_name
        """).fetchall()
        geom_map = {r["table_name"]:(r["column_name"],r["geometry_type_name"])
                    for r in inp.execute("SELECT table_name,column_name,geometry_type_name FROM gpkg_geometry_columns")}
        contins = set()
        for entry in content:
            table = entry["table_name"]
            typ = category(table)
            scale = scale_for(table) or "unknown"
            theme = "cultural" if typ in ("country","state","city") or "admin" in table else "physical"
            geom_column,geom_type=geom_map.get(table,("", "UNKNOWN"))
            rowcount=inp.execute("SELECT COUNT(*) FROM "+quote_sql(table)).fetchone()[0]
            indexed=0
            if typ is not None:
                fields=[x[1] for x in inp.execute("PRAGMA table_info("+quote_sql(table)+")")]
                # Only geographic features with real published names are searchable.
                query="SELECT rowid AS __cr_rowid__, * FROM "+quote_sql(table)
                rtree_name=f"rtree_{table}_{geom_column}"
                has_rtree=bool(geom_column and inp.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                    (rtree_name,)).fetchone())
                tree_sql=("SELECT minx,maxx,miny,maxy FROM "+quote_sql(rtree_name)+
                          " WHERE id=?") if has_rtree else None
                cursor=inp.execute(query)
                for row in cursor:
                    rid=dst.execute("""
                      INSERT INTO regions(feature_key,kind,display_name,parent_name,geometry_type,
                                          source_layer,source_rowid,scale)
                      VALUES(?,?,?,?,?,?,?,?)
                    """,(f"{table}:{row['__cr_rowid__']}",typ,display(row,typ),
                         parent_name(row,typ),geom_type,table,row["__cr_rowid__"],scale)).lastrowid
                    names=aliases(row,typ)
                    for text,lang in names:
                        dst.execute("INSERT INTO search_fts(alias,region_id) VALUES(?,?)",(text,rid))
                    if tree_sql:
                        b=inp.execute(tree_sql,(row["__cr_rowid__"],)).fetchone()
                        if b and all(isinstance(x,(int,float)) for x in b):
                            dst.execute("INSERT INTO region_bounds VALUES(?,?,?,?,?)",(rid,*b))
                    if typ=="country":
                        fieldkeys={k.lower():k for k in row.keys()}
                        if "continent" in fieldkeys:
                            c=row[fieldkeys["continent"]]
                            if isinstance(c,str) and c.strip():
                                contins.add(c.strip())
                    indexed+=1
                    summary["names"]+=len(names)
                summary["region_layers"]+=1
                summary["region_records"]+=indexed
                summary["regions_by_type"][typ]=summary["regions_by_type"].get(typ,0)+indexed
            dst.execute("INSERT INTO layers VALUES(?,?,?,?,?,?)",
                        (table,theme,scale,geom_type,rowcount,indexed))
            summary["all_layers"]+=1
        for continent in sorted(contins):
            rid=dst.execute("""INSERT INTO regions(
                feature_key,kind,display_name,parent_name,geometry_type,
                source_layer,source_rowid,scale
            ) VALUES(?,?,?,?,?,?,?,?)""",(
                "derived:continent:"+continent,"continent",continent,"",
                "DERIVED_GROUP_ONLY","ne_admin0_continent",0,"derived")).lastrowid
            dst.execute("INSERT INTO search_fts(alias,region_id) VALUES(?,?)",(continent,rid))
            summary["regions_by_type"]["continent"]=summary["regions_by_type"].get("continent",0)+1
            summary["region_records"]+=1
            summary["names"]+=1
        with source.open("rb") as fp:
            sha=hashlib.file_digest(fp,"sha256").hexdigest()
        for key,value in {
            "schema_version":"1","source_filename":source.name,
            "source_sha256":sha,"source_format":"GeoPackage",
            "coverage":"PARTIAL_NOT_VALIDATED",
            "network_requirement":"NONE",
        }.items():
            dst.execute("INSERT INTO metadata VALUES(?,?)",(key,value))
        dst.commit()
        check=dst.execute("PRAGMA integrity_check").fetchone()[0]
        if check!="ok":
            raise RuntimeError("index failed SQLite integrity_check: "+str(check))
        if summary["all_layers"]==0 or summary["region_records"]==0:
            raise ValueError("source has no indexed geographic regions")
        dst.close();inp.close()
        temp.replace(output)
        return summary
    except Exception:
        dst.close();inp.close();temp.unlink(missing_ok=True)
        raise

def search(database: Path, query: str, kind: str, limit=20) -> list[dict]:
    if kind not in REGION_TYPES:
        raise ValueError("unknown geography type")
    if len(query)>120 or not 1<=limit<=50:
        raise ValueError("search request exceeds limits")
    tokens=TOKEN.findall(query)
    if not tokens or len(tokens)>8:
        return []
    # All tokens are escaped and bound; raw user FTS expressions are forbidden.
    term=" AND ".join('"' + t.replace('"','') + '"*' for t in tokens)
    uri=database.resolve().as_uri()+"?mode=ro"
    con=sqlite3.connect(uri,uri=True)
    con.row_factory=sqlite3.Row
    try:
        con.execute("PRAGMA query_only=ON")
        rows=con.execute("""
          SELECT r.feature_key,r.kind,r.display_name,r.parent_name,
                 r.geometry_type,r.source_layer,r.source_rowid,r.scale,
                 bm25(search_fts) AS relevance
          FROM search_fts JOIN regions r ON r.region_id=CAST(search_fts.region_id AS INTEGER)
          WHERE search_fts MATCH ? AND r.kind=?
          ORDER BY relevance ASC,
            CASE r.scale WHEN '10m' THEN 0 WHEN '50m' THEN 1
                         WHEN '110m' THEN 2 ELSE 3 END ASC, r.display_name ASC
          LIMIT 400
        """,(term,kind)).fetchall()
        seen=set()
        out=[]
        for r in rows:
            key=(r["kind"],r["display_name"].casefold(),r["parent_name"].casefold())
            if key in seen:continue
            seen.add(key)
            entry=dict(r)
            entry["geometry_available"]=r["geometry_type"]!="DERIVED_GROUP_ONLY"
            entry.pop("relevance",None)
            out.append(entry)
            if len(out)>=limit:break
        return out
    finally: con.close()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    sub=ap.add_subparsers(dest="command",required=True)
    create=sub.add_parser("build");create.add_argument("--gpkg",type=Path,required=True)
    create.add_argument("--out",type=Path,required=True)
    find=sub.add_parser("search");find.add_argument("--db",type=Path,required=True)
    find.add_argument("--type",choices=REGION_TYPES,required=True)
    find.add_argument("--query",required=True)
    args=ap.parse_args()
    if args.command=="build":
        print(json.dumps(index_source(args.gpkg,args.out),indent=2))
    else:
        print(json.dumps(search(args.db,args.query,args.type),indent=2,ensure_ascii=False))

if __name__=="__main__":
    main()
