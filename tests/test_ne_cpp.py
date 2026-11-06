"""End-to-end offline test: synthetic GeoPackage -> SQLite index -> C++ runtime."""
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

exe=Path(sys.argv[1])
root=Path(sys.argv[2])
sys.path.insert(0,str(root))
from tools.natural_earth.build_catalog import index_source

with tempfile.TemporaryDirectory() as directory:
    target=Path(directory)
    gpkg=target/"ne-test.gpkg"
    with sqlite3.connect(gpkg) as db:
        db.executescript("""
        CREATE TABLE gpkg_contents(table_name TEXT,data_type TEXT);
        CREATE TABLE gpkg_geometry_columns(table_name TEXT,column_name TEXT,geometry_type_name TEXT);
        CREATE TABLE ne_10m_admin_0_countries(fid INTEGER PRIMARY KEY,name TEXT,
            name_pt TEXT,adm0_a3 TEXT,continent TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_admin_0_countries','features');
        INSERT INTO gpkg_geometry_columns VALUES('ne_10m_admin_0_countries','geometry','MULTIPOLYGON');
        INSERT INTO ne_10m_admin_0_countries(name,name_pt,adm0_a3,continent)
          VALUES('Brazil','Brasil','BRA','South America');
        CREATE TABLE ne_10m_admin_1_states_provinces(fid INTEGER PRIMARY KEY,name TEXT,
          admin TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_admin_1_states_provinces','features');
        INSERT INTO gpkg_geometry_columns VALUES('ne_10m_admin_1_states_provinces','geometry','POLYGON');
        INSERT INTO ne_10m_admin_1_states_provinces(name,admin)
          VALUES('São Paulo','Brazil');
        CREATE TABLE ne_10m_populated_places(fid INTEGER PRIMARY KEY,name TEXT,
          adm0name TEXT,geometry BLOB);
        INSERT INTO gpkg_contents VALUES('ne_10m_populated_places','features');
        INSERT INTO gpkg_geometry_columns VALUES('ne_10m_populated_places','geometry','POINT');
        INSERT INTO ne_10m_populated_places(name,adm0name)
          VALUES('São Paulo','Brazil');
        """)
    catalog=target/"catalog.sqlite"
    result=index_source(gpkg,catalog)
    assert result["region_records"]==4,result
    def query(kind,text,success=True):
        p=subprocess.run([str(exe),str(catalog),kind,text],
             capture_output=True,text=True,encoding="utf-8",timeout=20)
        assert (p.returncode==0)==success,(kind,text,p.returncode,p.stdout,p.stderr)
        return p.stdout
    assert "Brazil" in query("country","Brasil")
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
