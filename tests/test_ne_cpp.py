"""End-to-end offline test: synthetic GeoPackage -> SQLite index -> C++ runtime."""
from pathlib import Path
import sqlite3
import struct
import subprocess
import sys
import tempfile

exe=Path(sys.argv[1])
root=Path(sys.argv[2])
preview=Path(sys.argv[3])
sys.path.insert(0,str(root))
from tools.natural_earth.build_catalog import index_source

with tempfile.TemporaryDirectory() as directory:
    target=Path(directory)
    gpkg=target/"ne-test.gpkg"
    with sqlite3.connect(gpkg) as db:
        db.executescript("""
        CREATE TABLE gpkg_contents(table_name TEXT,data_type TEXT);
        CREATE TABLE gpkg_geometry_columns(table_name TEXT,column_name TEXT,geometry_type_name TEXT,srs_id INTEGER);
        CREATE TABLE ne_10m_admin_0_countries(fid INTEGER PRIMARY KEY,name TEXT,
            name_pt TEXT,adm0_a3 TEXT,continent TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_admin_0_countries','features');
        INSERT INTO gpkg_geometry_columns VALUES('ne_10m_admin_0_countries','geometry','MULTIPOLYGON',4326);
        INSERT INTO ne_10m_admin_0_countries(name,name_pt,adm0_a3,continent)
          VALUES('Brazil','Brasil','BRA','South America');
        CREATE TABLE ne_10m_admin_1_states_provinces(fid INTEGER PRIMARY KEY,name TEXT,
          admin TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_admin_1_states_provinces','features');
        INSERT INTO gpkg_geometry_columns VALUES('ne_10m_admin_1_states_provinces','geometry','POLYGON',4326);
        INSERT INTO ne_10m_admin_1_states_provinces(name,admin)
          VALUES('São Paulo','Brazil');
        CREATE TABLE ne_10m_populated_places(fid INTEGER PRIMARY KEY,name TEXT,
          adm0name TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_populated_places','features');
        INSERT INTO gpkg_geometry_columns VALUES('ne_10m_populated_places','geometry','POINT',4326);
        INSERT INTO ne_10m_populated_places(name,adm0name)
          VALUES('São Paulo','Brazil');
        CREATE TABLE ne_10m_rivers_lake_centerlines(fid INTEGER PRIMARY KEY,
          name TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_rivers_lake_centerlines','features');
        INSERT INTO gpkg_geometry_columns VALUES(
          'ne_10m_rivers_lake_centerlines','geometry','LINESTRING',4326);
        INSERT INTO ne_10m_rivers_lake_centerlines(name) VALUES('Test River');
        """)
    def gp(wkb):
        return b"GP" + bytes([0,1]) + struct.pack("<I",4326) + wkb
    def p(x,y):
        return struct.pack("<dd",x,y)
    def polygon():
        pts=[(-50,-20),(-40,-20),(-40,-10),(-50,-10),(-50,-20)]
        return gp(b"\x01"+struct.pack("<III",3,1,len(pts))+
                  b"".join(p(x,y) for x,y in pts))
    def point(x,y):
        return gp(b"\x01"+struct.pack("<I",1)+p(x,y))
    def line(coords):
        return gp(b"\x01"+struct.pack("<II",2,len(coords))+
                  b"".join(p(x,y) for x,y in coords))
    local=sqlite3.connect(gpkg)
    local.execute("UPDATE ne_10m_admin_0_countries SET geometry=? WHERE adm0_a3='BRA'",
                  (polygon(),))
    local.execute("UPDATE ne_10m_admin_1_states_provinces SET geometry=? WHERE name='São Paulo'",
                  (polygon(),))
    local.execute("UPDATE ne_10m_populated_places SET geometry=? WHERE name='São Paulo'",
                  (point(-46.633,-23.55),))
    local.execute("UPDATE ne_10m_rivers_lake_centerlines SET geometry=?",
                  (line([(-49,-19),(-45,-15),(-41,-12)]),))
    local.commit()
    local.close()
    # Python SQLite connection context manager commits but does NOT close.
    # Windows keeps the GeoPackage locked until an explicit close.
    db.close()
    catalog=target/"catalog.sqlite"
    result=index_source(gpkg,catalog)
    assert result["region_records"]==4,result
    def query(kind,text,success=True):
        p=subprocess.run([str(exe),str(catalog),kind,text],
             capture_output=True,text=True,encoding="utf-8",timeout=20)
        assert (p.returncode==0)==success,(kind,text,p.returncode,p.stdout,p.stderr)
        return p.stdout
    # Verify the C++ data path actually paints pixels from geographic WKB.
    painted=subprocess.run([str(preview),str(gpkg),"10m"],
                           capture_output=True,text=True,encoding="utf-8",timeout=20)
    assert painted.returncode==0,(painted.stdout,painted.stderr)
    assert "countries=1" in painted.stdout and "polygons=1" in painted.stdout,painted.stdout
    # Real Pixel render over the unchanged countries map; verify all three
    # GeoPackage geometry families and reject unsafe SQL identifiers.
    for table in ("ne_10m_populated_places",
                  "ne_10m_rivers_lake_centerlines",
                  "ne_10m_admin_1_states_provinces"):
        overlay=subprocess.run([str(preview),str(gpkg),"10m",table],
             capture_output=True,text=True,encoding="utf-8",timeout=20)
        assert overlay.returncode==0,(table,overlay.stdout,overlay.stderr)
        assert "overlay_features=1" in overlay.stdout,overlay.stdout
        assert overlay.stdout!=painted.stdout,"overlay must change rendered pixels"
    unsafe=subprocess.run([str(preview),str(gpkg),"10m",
                           "ne_10m_populated_places;DROP TABLE gpkg_contents"],
         capture_output=True,text=True,encoding="utf-8",timeout=20)
    assert unsafe.returncode!=0,"untrusted layer name must be rejected"
    # A sqlite3 connection context manager commits but does NOT close the DB
    # on Windows; leaving this open blocks TemporaryDirectory cleanup.
    check_db=sqlite3.connect(gpkg)
    try:
        assert check_db.execute("SELECT COUNT(*) FROM gpkg_contents").fetchone()[0]==4
    finally:
        check_db.close()
    assert "Brazil" in query("country","Brasil")
    r=subprocess.run([str(exe),str(catalog),"country","Brasil",str(gpkg)],
                     capture_output=True,text=True,encoding="utf-8",timeout=20)
    assert r.returncode==0 and "POLYGONS=1" in r.stdout,(r.stdout,r.stderr)
    r=subprocess.run([str(exe),str(catalog),"city","São Paulo",str(gpkg)],
                     capture_output=True,text=True,encoding="utf-8",timeout=20)
    assert r.returncode==0 and "POINTS=1" in r.stdout,(r.stdout,r.stderr)

    assert "Brazil" in query("country","BRA")
    assert "São Paulo" in query("state","Sao Paulo")
    assert "\tPOINT\t" in query("city","São Paulo")
    assert "South America" in query("continent","South")
    assert query("city","Imaginary City")==""  # no geocoding or fabricated results
    query("invalid","Brazil",False)
    p=subprocess.run([str(exe),str(target/"missing.sqlite"),"country","Brazil"],
                     capture_output=True,text=True,timeout=20)
    assert p.returncode!=0,"missing pack must fail, not create an empty DB"
    assert not (target/"missing.sqlite").exists(),"runtime cannot create DB files"
    print("PASS: C++ native search is offline, read-only and respects GeoPackage region types")
