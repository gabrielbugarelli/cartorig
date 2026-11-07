"""Offline packaging/contract checks for the CartoRig Edit-first MVP authoring kit.

They establish catalog and shipped-code consistency, NOT live Resolve host
support for Fusion input expressions or independent OpenFX keyframes.
"""
from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packaging" / "easy-test"
CORE = PACKAGE / "CartoRigSupport" / "core.lua"


class EditFirstAuthoringContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = json.loads((ROOT / "data" / "countries.geojson").read_text(encoding="utf-8"))
        cls.lua = (PACKAGE / "CartoRigSupport" / "countries.lua").read_text(encoding="utf-8")
        cls.core = CORE.read_text(encoding="utf-8")
        cls.ofx = (ROOT / "src" / "ofx_plugin.cpp").read_text(encoding="utf-8")

    def test_catalog_covers_exact_offline_country_dataset(self):
        native = {x["properties"]["iso3"]: x["properties"]["name"]
                  for x in self.source["features"]
                  if x.get("geometry", {}).get("type") in ("Polygon", "MultiPolygon")}
        index = dict(re.findall(r'\{code="([A-Z]{3})", name="([^"]+)"', self.lua))
        self.assertGreaterEqual(len(index), 170)
        self.assertEqual(index, native)
        self.assertEqual(len(set(index)), len(index))
        self.assertNotIn("http://", self.lua)
        self.assertNotIn("https://", self.lua)

    def test_country_search_and_region_state_uses_geo_iso3(self):
        self.assertIn('["brasil"]="BRA"', self.core)
        self.assertIn('["venezuela"]="VEN"', self.core)
        self.assertIn('setInput(tool,"CountryA",match.code)', self.core)
        self.assertIn('setInput(new,"ObjectLayerOnly",1)', self.core)
        self.assertIn('syncCamera(new,base)', self.core)
        self.assertIn('setInput(tool,"CustomMapColors",1)', self.core)

    def test_native_object_layer_contract_is_wired(self):
        self.assertIn('defineNativeToggle(ps,"ObjectLayerOnly"', self.ofx)
        self.assertIn('{"ObjectLayerOnly",&i->objectLayerOnly}', self.ofx)
        self.assertIn('view.objectsOnly=i->overlay', self.ofx)
        self.assertIn('if(!view.objectsOnly)', (ROOT / "src" / "raster.cpp").read_text())

    def test_route_style_controls_exist_and_are_bound(self):
        for name in ("NativeRouteRed", "NativeRouteGreen", "NativeRouteBlue"):
            self.assertIn('"' + name + '"', self.ofx)
            self.assertIn('"' + name + '"', self.core)
        self.assertIn('controls.routeColor=', self.ofx)
        self.assertIn('route.color=n.routeColor;', (ROOT/"src/native_controls.cpp").read_text())

    def test_scripts_are_present_and_installed(self):
        installer = (PACKAGE / "Install-CartoRig.ps1").read_text(encoding="utf-8")
        for operation in ("Create Map", "Add Country", "Add Route", "Set Camera"):
            script = PACKAGE / f"CartoRig - {operation}.lua"
            self.assertTrue(script.is_file(), str(script))
            self.assertIn("CartoRig - " + operation + ".lua", installer)
            self.assertIn("core.run(", script.read_text())
        for support in ("core.lua", "countries.lua"):
            self.assertTrue((PACKAGE / "CartoRigSupport" / support).is_file())
            self.assertIn(support, installer)
        self.assertIn("Get-FileHash", installer)

    def test_commands_use_current_project_instead_of_creating_a_qa_project(self):
        self.assertIn("GetCurrentProject", self.core)
        self.assertIn("GetCurrentTimeline", self.core)
        self.assertIn("InsertFusionCompositionIntoTimeline", self.core)
        self.assertNotIn("CreateProject(", self.core)
        self.assertNotIn("Invoke-WebRequest", self.core)
        self.assertNotIn("HttpClient", self.core)

    def test_camera_link_is_required_to_preserve_georeference(self):
        self.assertIn("SetExpression", self.core)
        self.assertIn("GetExpression", self.core)
        self.assertIn("object not inserted", self.core)
        self.assertIn("CR_Map_Base.", self.core)


if __name__ == "__main__":
    unittest.main()
