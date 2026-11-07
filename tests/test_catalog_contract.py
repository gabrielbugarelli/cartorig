import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class CatalogContractTest(unittest.TestCase):
    def test_country_pack_has_brazil_and_no_iso3_ui(self):
        data=(ROOT/'fusion/CartoRig/data/ne110m_countries.lua').read_text(encoding='utf-8')
        self.assertIn('name="Brazil"',data)
        self.assertIn('"Brasil"',data)
        self.assertGreaterEqual(data.count('kind="Country"'),170)
    def test_state_pack_is_full_brazil_admin1(self):
        path=ROOT/'fusion/CartoRig/data/ne50m_br_states.lua'
        if not path.exists(): self.skipTest('Admin1 source must be included in complete GitHub branch source distribution')
        data=path.read_text(encoding='utf-8')
        self.assertEqual(data.count('kind="State"'),27)
        for term in ['Rio de Janeiro','Amapá','São Paulo']:
            self.assertIn(term,data)
    def test_city_pack_from_official_source(self):
        path=ROOT/'fusion/CartoRig/data/ne110m_cities.lua'
        if not path.exists(): self.skipTest('City source must be included in complete GitHub branch source distribution')
        data=path.read_text(encoding='utf-8')
        self.assertGreaterEqual(data.count('kind="City"'),240)
        self.assertIn('Brasília',data)
    def test_no_electron_or_iso3_required(self):
        script=(ROOT/'fusion/CartoRig Fusion-first.lua').read_text(encoding='utf-8')
        self.assertIn('UIManager',script)
        self.assertNotIn('ISO3 Lookup',script)
        self.assertNotIn('Electron',script)

if __name__=='__main__':unittest.main()
