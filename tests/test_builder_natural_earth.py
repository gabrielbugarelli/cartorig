"""Build pipeline regressions using entirely synthetic Shapefiles, no internet required."""
import importlib.util
import io
import pathlib
import tempfile
import unittest
import zipfile

import shapefile

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'tools' / 'build_natural_earth.py'
spec = importlib.util.spec_from_file_location('cartorig_ne_builder', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class NaturalEarthBuildTests(unittest.TestCase):
    def test_geojson_conversion_and_index(self):
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp)
            base=path/'ne_fake_admin_0_countries'
            with shapefile.Writer(str(base), shapeType=shapefile.POLYGON) as writer:
                writer.field('NAME','C',size=60)
                writer.field('NE_ID','N',size=10)
                writer.poly([[[-54,-30],[-54,4],[-30,4],[-30,-30],[-54,-30]]])
                writer.record('Brazil',101)
            stream=io.BytesIO()
            with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as zipf:
                for suffix in ('.shp','.shx','.dbf'):
                    f=base.with_suffix(suffix)
                    zipf.write(f,f.name)
            doc=module.convert_zip(stream.getvalue(),base.name)
            self.assertEqual(len(doc['features']),1)
            self.assertIn(doc['features'][0]['geometry']['type'],('Polygon','MultiPolygon'))
            item=module.search_metadata(doc['features'][0],'admin0',0,'test-sha256')
            self.assertEqual(item['kind'],'Country')
            self.assertIn('Brasil',item['aliases'])
            self.assertIn('natural-earth:admin0',item['id'])

    def test_wrong_shapefile_name_is_rejected(self):
        with zipfile.ZipFile(io.BytesIO(), 'w') as z:
            pass
        buffer=io.BytesIO()
        with zipfile.ZipFile(buffer,'w') as z:z.writestr('unexpected.txt','x')
        with self.assertRaises(ValueError):
            module.convert_zip(buffer.getvalue(),'ne_missing')

if __name__ == '__main__':unittest.main()
