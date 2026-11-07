"""Static guardrails for the experimental Fusion/Qt proof, no Resolve installed."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "fusion" / "CartoRig Fusion-first POC.lua"


class SourceContract(unittest.TestCase):
    def test_script_and_installer_exist(self):
        self.assertTrue(SCRIPT.is_file())
        self.assertTrue((ROOT / "packaging" / "Install-PoC.cmd").is_file())

    def test_expected_proof_nodes_are_named(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for word in ["Brazil", "Rio", "Camera", "BaseMap", "RectangleMask", "MediaOut"]:
            self.assertIn(word, source)

    def test_the_script_does_not_import_legacy_modules_or_use_network(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in ["require(", "socket.", "http.request", "powershell", "os.execute(", "io.popen("]:
            self.assertNotIn(forbidden, source)

    def test_current_comp_and_undo_are_explicit(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for api in ["GetCurrentComp", "GetToolList", "SetData", "StartUndo", "EndUndo", "FlowView", "Select", "AddModifier", "SetInput", "UIDispatcher"]:
            self.assertIn(api, source)


if __name__ == "__main__":
    unittest.main()
