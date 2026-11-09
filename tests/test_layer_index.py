"""Offline base layer index contract tests with synthetic WGS84 geometry."""
import sys
from pathlib import Path
import tempfile, unittest, json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from layer_index import write_layer_index
class BaseLayerIndexTests(unittest.TestCase):
    def test_land_polygon_is_indexed_and_seekable_without_loading_entire_geojson(self):
        ring=[[-60,-20],[-40,-20],[-40,0],[-60,0],[-60,-20]]
        hole=[[-52,-10],[-48,-10],[-48,-8],[-52,-8],[-52,-10]]
        f={"type":"Feature","properties":{"NAME":"sample"},"geometry":{"type":"Polygon","coordinates":[ring,hole]}}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            row=write_layer_index(root,"land",[f,f],"pinned-sha")
            index=json.loads((root/row["filename"]).read_text(encoding="utf-8"))
            self.assertEqual(index["schema"],"cartorig.offline.layers/1")
            self.assertEqual(len(index["features"]),2)
            self.assertEqual(index["features"][0]["bbox"],[-60.0,-20.0,-40.0,0.0])
            self.assertEqual(index["features"][0]["featureOffset"],0)
            self.assertEqual(index["features"][1]["featureOffset"],index["features"][0]["featureBytes"])
            with (root/row["data_file"]).open("rb") as stream:
                stream.seek(index["features"][1]["featureOffset"])
                restored=json.loads(stream.read(index["features"][1]["featureBytes"]))
            self.assertEqual(restored["geometry"]["coordinates"][1],hole)
            self.assertEqual(row["feature_count"],2)
    def test_antimeridian_is_flagged_and_invalid_input_rejected(self):
        line={"type":"Feature","properties":{},"geometry":{
          "type":"LineString","coordinates":[[179,10],[-179,12]]}}
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);data=write_layer_index(root,"coastline",[line],"version")
            idx=json.loads((root/data["filename"]).read_text())
            self.assertTrue(idx["features"][0]["crossesAntimeridian"])
            line["geometry"]["coordinates"][0][0]=999
            with self.assertRaises(ValueError):write_layer_index(root,"coastline",[line],"version")
            with self.assertRaises(ValueError):write_layer_index(root,"roads",[line],"version")
            with self.assertRaises(ValueError):write_layer_index(root,"land",[line],"version")
if __name__=="__main__":unittest.main()
