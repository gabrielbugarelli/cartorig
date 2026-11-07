"""Contract tests for the hybrid Resolve 20/Fusion probe; never claim host coverage."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tools import cartorig_fusion_spike as probe


class FakeTool:
    def __init__(self, kind, name=None):
        self.kind = kind
        self.name = name or kind
        self.attrs = {"TOOLS_Name": self.name}
        self.inputs = {}
        self.keys = {}
        self.links = {}

    def SetAttrs(self, attrs):
        self.attrs.update(attrs)
        self.name = attrs["TOOLS_Name"]
        return True

    def GetAttrs(self):
        return self.attrs

    def SetInput(self, key, value, frame=None):
        if frame is None:
            self.inputs[key] = value
        else:
            self.keys.setdefault(key, {})[int(frame)] = value
        return True

    def GetInput(self, key, frame):
        options = self.keys.get(key, {})
        earlier = [time for time in options if time <= frame]
        if earlier:
            return options[max(earlier)]
        return self.inputs.get(key)

    def ConnectInput(self, socket, upstream):
        self.links[socket] = upstream
        return True

    def AddModifier(self, input_name, kind):
        return object()


class FakeComp:
    def __init__(self, with_media=True):
        self.tools = []
        if with_media:
            self.tools += [FakeTool("MediaIn", "MediaIn1"),
                           FakeTool("MediaOut", "MediaOut1")]
        self.undo_ended = False

    def FindTool(self, name):
        return next((x for x in self.tools if x.name == name), None)

    def FindToolByID(self, kind):
        return next((x for x in self.tools if x.kind == kind), None)

    def AddTool(self, kind, x, y):
        tool = FakeTool(kind)
        self.tools.append(tool)
        return tool

    def GetAttrs(self):
        return {"COMPN_GlobalStart": 0}

    def StartUndo(self, name):
        pass

    def EndUndo(self, success):
        self.undo_ended = bool(success)


class FakeClip:
    def __init__(self):
        self.comps = []

    def GetName(self):
        return probe.GENERATOR

    def GetFusionCompCount(self):
        return len(self.comps)

    def AddFusionComp(self):
        comp = FakeComp()
        self.comps.append(comp)
        return comp

    def GetFusionCompByIndex(self, index):
        return self.comps[index - 1]


class FakeTimeline:
    def __init__(self, name):
        self.name = name
        self.settings = {}
        self.clips = []

    def GetName(self):
        return self.name

    def SetSetting(self, key, value):
        self.settings[key] = value
        return True

    def InsertOFXGeneratorIntoTimeline(self, name):
        if name != probe.GENERATOR:
            return None
        clip = FakeClip()
        self.clips.append(clip)
        return clip

    def GetTrackCount(self, kind):
        return 1 if kind == "video" else 0

    def GetItemListInTrack(self, kind, number):
        return self.clips


class FakeProject:
    def __init__(self, name):
        self.name = name
        self.timelines = []

    def GetName(self):
        return self.name

    def GetMediaPool(self):
        return self

    def CreateEmptyTimeline(self, name):
        tl = FakeTimeline(name)
        self.timelines.append(tl)
        return tl

    def SetCurrentTimeline(self, timeline):
        return True

    def GetTimelineCount(self):
        return len(self.timelines)

    def GetTimelineByIndex(self, index):
        return self.timelines[index - 1]


class FakeManager:
    def __init__(self):
        self.projects = {}
        self.saves = 0

    def CreateProject(self, name):
        if name in self.projects:
            return None
        new = FakeProject(name)
        self.projects[name] = new
        return new

    def LoadProject(self, name):
        return self.projects.get(name)

    def SaveProject(self):
        self.saves += 1
        return True


class FakeResolve:
    def __init__(self):
        self.manager = FakeManager()
        self.version = [20, 2, 0, 3]

    def GetVersion(self):
        return self.version

    def GetVersionString(self):
        return "20.2.0.3"

    def GetProductName(self):
        return "DaVinci Resolve Studio"

    def GetProjectManager(self):
        return self.manager


class HybridProbeTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.bundle = self.root / "CartoRigNative.ofx"
        self.bundle.write_bytes(b"fake compiled module for simulated contracts")
        self.app = FakeResolve()
        self.project = "CartoRig_Fusion_Test_01"

    def test_inspect_is_read_only_and_does_not_claim_render(self):
        report = self.root / "inspect.json"
        result = probe.run_cli("inspect", report, self.project,
                               app=self.app, binary=self.bundle)
        self.assertEqual(result["status"], "HOST_CONNECTED_HYBRID_GATES_PENDING")
        self.assertEqual(self.app.manager.projects, {})
        self.assertFalse(result["full_cartorig_product_accepted"])
        self.assertFalse(json.loads(report.read_text())["real_host_viewer_or_deliver_verified"])

    def test_prepare_requires_explicit_project_switch_consent(self):
        with self.assertRaisesRegex(probe.ProbeError, "allow-switch-project"):
            probe.prepare(self.app, self.project, allow_project_switch=False)
        self.assertEqual(self.app.manager.projects, {})
        self.assertEqual(self.app.manager.saves, 0)

    def test_create_and_verify_two_independent_animated_objects(self):
        created = probe.prepare(self.app, self.project,
                                allow_project_switch=True)
        self.assertTrue(created["ofx_generator_inserted_on_edit"])
        self.assertTrue(created["fusion_graph_created"])
        self.assertFalse(created["persistence_verified"])
        self.assertEqual(self.app.manager.saves, 1)
        tl = self.app.manager.projects[self.project].timelines[0]
        self.assertEqual(tl.settings["timelineResolutionWidth"], "1920")
        comp = tl.clips[0].comps[0]
        bra = comp.FindTool(probe.NODES["bra_merge"])
        ven = comp.FindTool(probe.NODES["ven_merge"])
        self.assertIsNot(bra, ven)
        self.assertIs(ven.links["Background"], bra)
        self.assertIs(comp.FindTool("MediaOut1").links["Input"], ven)
        self.assertTrue(comp.undo_ended)
        validated = probe.verify(self.app, self.project)
        self.assertTrue(validated["independent_animation_persisted"])
        self.assertFalse(validated["geographic_anchoring_tested"])
        self.assertFalse(validated["real_viewer_or_deliver_tested"])

    def test_reject_existing_project_and_non_qa_names(self):
        probe.prepare(self.app, self.project, allow_project_switch=True)
        with self.assertRaisesRegex(probe.ProbeError, "already exists"):
            probe.prepare(self.app, self.project, allow_project_switch=True)
        with self.assertRaisesRegex(probe.ProbeError, "Only new"):
            probe.prepare(self.app, "MyProductionProject", allow_project_switch=True)
        self.assertEqual(self.app.manager.saves, 1)

    def test_corrupt_keyframes_or_missing_node_fail_closed(self):
        probe.prepare(self.app, self.project, allow_project_switch=True)
        comp = self.app.manager.projects[self.project].timelines[0].clips[0].comps[0]
        comp.FindTool(probe.NODES["ven_merge"]).keys["Blend"][24] = 1.0
        with self.assertRaisesRegex(probe.ProbeError, "not persisted"):
            probe.verify(self.app, self.project)
        comp.tools = [tool for tool in comp.tools
                      if tool.name != probe.NODES["bra"]]
        with self.assertRaises(probe.ProbeError):
            probe.verify(self.app, self.project)

    def test_missing_media_in_or_out_does_not_fabricate_working_graph(self):
        with self.assertRaisesRegex(probe.ProbeError, "MediaIn/MediaOut"):
            probe.add_independent_objects(FakeComp(with_media=False))

    def test_version_rejection_writes_blocked_report(self):
        self.app.version[0] = 21
        path = self.root / "report.json"
        with self.assertRaisesRegex(probe.ProbeError, "Resolve Studio 20"):
            probe.run_cli("inspect", path, self.project,
                          app=self.app, binary=self.bundle)
        record = json.loads(path.read_text())
        self.assertEqual(record["status"], "BLOCKED")
        self.assertIn("Resolve Studio 20", record["blocker"])
        self.assertFalse(record["full_cartorig_product_accepted"])

    def test_missing_binary_fails_preflight(self):
        with self.assertRaisesRegex(probe.ProbeError, "not found"):
            probe.preflight(self.app, self.root / "missing.ofx")


if __name__ == "__main__":
    unittest.main()
