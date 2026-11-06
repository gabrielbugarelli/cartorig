"""Synthetic offline tests for the 33 Natural Earth supplemental GeoJSON layers."""
from pathlib import Path
import hashlib
import json
import sqlite3
import tempfile
import unittest

from tools.natural_earth import supplements

def fake_manifest():
    layers=[f"ne_10m_bathymetry_{letter}_{depth}" for letter,depth in
            zip("ABCDEFGHIJKL",[10000,9000,8000,7000,6000,5000,4000,3000,2000,1000,200,0])]
    for scale in ("10m","50m","110m"):
        layers.extend(f"ne_{scale}_graticules_{n}" for n in (1,5,10,15,20,30))
        layers.append(f"ne_{scale}_wgs84_bounding_box")
    return {"schema_version":1,"upstream_ref":"v5.1.2","count":33,
            "entries":[{"layer":n,"source_geojson_path":"geojson/"+n+".geojson",
                        "pinned_git_blob_sha1":"","bytes":0} for n in layers]}

class SupplementsTests(unittest.TestCase):
    def setUp(self):
        temporary=tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder=Path(temporary.name)
        self.sources=self.folder/"source"
        self.sources.mkdir()
        self.manifest=fake_manifest()
        self.out=self.folder/"supplement.gpkg"
        self.expected_features=0
        for row in self.manifest["entries"]:
            name=row["layer"]
            if "graticules" in name:
                geometry={"type":"MultiLineString","coordinates":[
                    [[-179,-80],[0,0],[179,80]]]}
            elif "bathymetry" in name:
                geometry={"type":"MultiPolygon","coordinates":[[
                  [[-10,-10],[10,-10],[10,10],[-10,10],[-10,-10]]]]}
            else:
                geometry={"type":"Polygon","coordinates":[[
                    [-180,-90],[180,-90],[180,90],[-180,90],[-180,-90]]]}
            data=json.dumps({"type":"FeatureCollection","features":[
                {"type":"Feature","geometry":geometry,"properties":{"label":name}},
                {"type":"Feature","geometry":geometry,"properties":{"label":name+" second"}}]},
                sort_keys=True).encode("utf-8")
            row["bytes"]=len(data)
            row["pinned_git_blob_sha1"]=supplements.git_blob_sha(data)
            (self.sources/(name+".geojson")).write_bytes(data)
            self.expected_features+=2
    def test_all_33_layers_imported_as_readable_gpkg(self):
        report=supplements.create_geopackage(self.manifest,self.sources,self.out)
        self.assertTrue(report["complete"])
        self.assertEqual(report["imported"],33)
        self.assertEqual(report["features"],66)
        db=sqlite3.connect(self.out)
        try:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone()[0],"ok")
            self.assertEqual(db.execute("SELECT COUNT(*) FROM gpkg_contents").fetchone()[0],33)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM provenance").fetchone()[0],33)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM gpkg_geometry_columns").fetchone()[0],33)
            for row in self.manifest["entries"]:
                layer=row["layer"]
                sample=db.execute(f'SELECT geom,attributes_json FROM "{layer}" LIMIT 1').fetchone()
                self.assertTrue(sample[0].startswith(b"GP\x00\x01"))
                self.assertEqual(int.from_bytes(sample[0][4:8],"little"),4326)
                self.assertEqual(sample[0][8],1)
                self.assertEqual(json.loads(sample[1])["label"],layer)
        finally:db.close()
    def test_tampering_aborts_without_writing_destination(self):
        bad=self.manifest["entries"][12]
        path=self.sources/(bad["layer"]+".geojson")
        path.write_bytes(path.read_bytes()+b"malicious")
        with self.assertRaises(ValueError):
            supplements.create_geopackage(self.manifest,self.sources,self.out)
        self.assertFalse(self.out.exists())
    def test_missing_file_aborts(self):
        path=self.sources/(self.manifest["entries"][0]["layer"]+".geojson")
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            supplements.create_geopackage(self.manifest,self.sources,self.out)
        self.assertFalse(self.out.exists())
    def test_polygon_holes_and_graticule_multiline(self):
        hole={"type":"Polygon","coordinates":[
            [[-60,-30],[-30,-30],[-30,0],[-60,0],[-60,-30]],
            [[-50,-20],[-40,-20],[-40,-10],[-50,-10],[-50,-20]]]}
        b,vertices=supplements.as_geopackage_blob(hole)
        self.assertEqual(b[8],1)
        self.assertEqual(len(vertices),10)
        self.assertGreater(len(b),120)
        multi={"type":"GeometryCollection","geometries":[
            {"type":"Point","coordinates":[-46.5,-23.5]},
            {"type":"LineString","coordinates":[[-80,-20],[-70,-15]]}]}
        self.assertEqual(len(supplements.as_geopackage_blob(multi)[1]),3)
    def test_non_finite_coordinates_rejected(self):
        with self.assertRaises(ValueError):
            supplements.as_geopackage_blob({"type":"Point","coordinates":[float("nan"),0]})
    def test_unpinned_manifest_is_rejected(self):
        self.manifest["upstream_ref"]="main"
        with self.assertRaises(ValueError):supplements.manifest_entries(self.manifest)

if __name__=="__main__":unittest.main()
