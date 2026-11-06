"""Natural Earth offline source audit, index and pack security regression tests."""
import hashlib
from pathlib import Path
import sqlite3
import tempfile
import unittest
import zipfile

from tools.natural_earth import inventory, verify_pack, build_catalog

class NaturalEarthTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def test_official_sources_and_urls(self):
        self.assertEqual(len(inventory.GROUPS),8)
        self.assertNotIn(("110m","raster"),inventory.GROUPS)
        page=inventory.category_page("110m","cultural")
        html='''<a href="http//www.naturalearthdata.com/download/110m/cultural/ne_110m_admin_0_countries.zip">Download countries</a>
                  (210 KB) version 5.1.1
                  <a href="https://evil.example/stolen.zip">Download foreign</a>'''
        resources,children=inventory.parse_page(html,page,"110m","cultural")
        self.assertEqual(len(resources),1)
        self.assertEqual(resources[0]["theme_version"],"5.1.1")
        self.assertEqual(resources[0]["status"],"DISCOVERED_UNVERIFIED")
        self.assertTrue(resources[0]["url"].startswith("https://www.naturalearthdata.com/download/"))
        self.assertFalse(children)

    def test_raster_category_child_pages(self):
        root=inventory.category_page("50m","raster")
        child=root+"50m-shaded-relief/"
        html=f'''<a href="{child}">Shaded Relief</a>
             <a href="https://naciscdn.org/naturalearth/50m/raster/NE.zip">Download small size</a>
             (23 MB) version 3.2.0'''
        links,children=inventory.parse_page(html,root,"50m","raster")
        self.assertEqual(children,[child])
        self.assertEqual(links[0]["theme_version"],"3.2.0")

    def test_failed_source_page_prevents_complete(self):
        def fake(url):
            if url.endswith("/downloads/10m-physical-vectors/"):raise TimeoutError("offline")
            return '<a href="https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip">Download countries</a> version 5.1.1'
        d=inventory.audit(fake)
        self.assertEqual(d["summary"]["pages_blocked"],1)
        self.assertFalse(d["summary"]["complete"])
        self.assertEqual(d["summary"]["resources_verified"],0)

    def test_integrity_fail_closed(self):
        path=self.root/"test.zip"
        with zipfile.ZipFile(path,"w") as z:z.writestr("ne_110m_admin_0_countries.shp",b"shape")
        record={"resource_id":"one","file":"test.zip","archive_bytes":path.stat().st_size,
                "sha256":verify_pack.sha256_file(path),"status":"VERIFIED"}
        manifest={"schema_version":1,"resources":[record]}
        self.assertTrue(verify_pack.verify_manifest(manifest,self.root)["complete"])
        record["status"]="DISCOVERED_UNVERIFIED"
        self.assertFalse(verify_pack.verify_manifest(manifest,self.root)["complete"])
        record["status"]="VERIFIED"
        path.write_bytes(b"tampered")
        self.assertFalse(verify_pack.verify_manifest(manifest,self.root)["complete"])
        with zipfile.ZipFile(path,"w") as z:z.writestr("../../escape.shp",b"BAD")
        with self.assertRaises(verify_pack.VerificationError):verify_pack.verify_zip(path)
        record["file"]="../escape.zip"
        self.assertFalse(verify_pack.verify_manifest(manifest,self.root)["complete"])

    def make_gpkg(self):
        source=self.root/"sample.gpkg"
        con=sqlite3.connect(source)
        con.executescript("""
          CREATE TABLE gpkg_contents(table_name TEXT,data_type TEXT);
          CREATE TABLE gpkg_geometry_columns(table_name TEXT,column_name TEXT,geometry_type_name TEXT);
          CREATE TABLE ne_10m_admin_0_countries(fid INTEGER PRIMARY KEY,
            name TEXT,name_en TEXT,name_pt TEXT,adm0_a3 TEXT,continent TEXT,geometry BLOB);
          INSERT INTO gpkg_contents VALUES('ne_10m_admin_0_countries','features');
          INSERT INTO gpkg_geometry_columns VALUES('ne_10m_admin_0_countries','geometry','MULTIPOLYGON');
          INSERT INTO ne_10m_admin_0_countries(name,name_en,name_pt,adm0_a3,continent)
            VALUES('Brazil','Brazil','Brasil','BRA','South America'),
                  ('Russia','Russia','Rússia','RUS','Europe');
          CREATE TABLE ne_10m_admin_1_states_provinces(fid INTEGER PRIMARY KEY,
            name TEXT,admin TEXT,geometry BLOB);
          INSERT INTO gpkg_contents VALUES('ne_10m_admin_1_states_provinces','features');
          INSERT INTO gpkg_geometry_columns VALUES('ne_10m_admin_1_states_provinces','geometry','POLYGON');
          INSERT INTO ne_10m_admin_1_states_provinces(name,admin)
            VALUES('São Paulo','Brazil'),('Texas','United States');
          CREATE TABLE ne_10m_populated_places(fid INTEGER PRIMARY KEY,
            name TEXT,adm0name TEXT,geometry BLOB);
          INSERT INTO gpkg_contents VALUES('ne_10m_populated_places','features');
          INSERT INTO gpkg_geometry_columns VALUES('ne_10m_populated_places','geometry','POINT');
          INSERT INTO ne_10m_populated_places(name,adm0name)
            VALUES('São Paulo','Brazil'),('Paris','France'),
                  ('Paris','United States of America');
          CREATE TABLE ne_10m_rivers_lake_centerlines(fid INTEGER PRIMARY KEY,name TEXT);
          INSERT INTO gpkg_contents VALUES('ne_10m_rivers_lake_centerlines','features');
          INSERT INTO ne_10m_rivers_lake_centerlines(name) VALUES('Amazon');
        """)
        con.commit();con.close()
        return source

    def test_geopackage_index_and_search(self):
        source=self.make_gpkg();index=self.root/"catalog.sqlite"
        stats=build_catalog.index_source(source,index)
        self.assertEqual(stats["all_layers"],4)
        self.assertEqual(stats["region_layers"],3)
        self.assertEqual(stats["regions_by_type"]["country"],2)
        result=lambda name,kind:build_catalog.search(index,name,kind)
        self.assertEqual(result("Brazil","country")[0]["feature_key"],
                         result("Brasil","country")[0]["feature_key"])
        self.assertEqual(result("BRA","country")[0]["feature_key"],
                         result("Brasil","country")[0]["feature_key"])
        self.assertEqual(result("São Paulo","state")[0]["geometry_type"],"POLYGON")
        self.assertEqual(result("Sao Paulo","city")[0]["geometry_type"],"POINT")
        self.assertEqual(result("Sao Paulo","city")[0]["parent_name"],"Brazil")
        self.assertEqual({x["parent_name"] for x in result("Paris","city")},
                         {"France","United States of America"})
        self.assertFalse(result("South America","continent")[0]["geometry_available"])
        self.assertEqual(result("Unknownville","city"),[])
        self.assertEqual(result('" OR *','city'),[])
        with self.assertRaises(ValueError):result("Paris","not_a_type")
        with sqlite3.connect(index) as con:
            self.assertEqual(con.execute("PRAGMA integrity_check").fetchone()[0],"ok")
            self.assertEqual(con.execute("SELECT value FROM metadata WHERE key='coverage'").fetchone()[0],
                             "PARTIAL_NOT_VALIDATED")
            self.assertEqual(con.execute("SELECT value FROM metadata WHERE key='source_sha256'").fetchone()[0],
                             hashlib.sha256(source.read_bytes()).hexdigest())
        self.assertEqual(build_catalog.index_source(source,index)["region_records"],stats["region_records"])

if __name__=="__main__":
    unittest.main()
