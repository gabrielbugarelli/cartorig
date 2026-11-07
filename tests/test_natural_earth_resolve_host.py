"""Actual DaVinci Resolve host QA uses the public API; never manufactures a pass."""
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest
from unittest.mock import patch

from tools import resolve_host_acceptance as qa

class Clip:
    def GetName(self):return "CartoRig Map (Edit)"

class Timeline:
    def __init__(self,name):
        self.name=name
        self.settings={}
    def GetName(self):return self.name
    def SetSetting(self,key,value):
        self.settings[key]=value
        return True
    def InsertOFXGeneratorIntoTimeline(self,name):
        return Clip() if name=="CartoRig Map (Edit)" else None
    def GetTrackCount(self,key):return 1 if key=="video" else 0
    def GetItemListInTrack(self,key,index):return [Clip()]

class Project:
    def __init__(self,name):
        self.name=name
        self.timelines=[]
        self.render_settings=[]
        self.jobs={}
    def GetName(self):return self.name
    def GetMediaPool(self):return self
    def CreateEmptyTimeline(self,name):
        timeline=Timeline(name)
        self.timelines.append(timeline)
        return timeline
    def SetCurrentTimeline(self,tl):return True
    def GetTimelineCount(self):return len(self.timelines)
    def GetTimelineByIndex(self,i):return self.timelines[i-1]
    def SetCurrentRenderFormatAndCodec(self,fmt,codec):
        return fmt=="mp4" and codec=="H264"
    def SetRenderSettings(self,settings):
        self.render_settings.append(settings)
        return True
    def AddRenderJob(self):
        name="job-"+str(len(self.jobs)+1)
        self.jobs[name]=self.render_settings[-1]
        return name
    def StartRendering(self,ids):
        for job in ids:
            settings=self.jobs[job]
            path=Path(settings["TargetDir"])/(settings["CustomName"]+".mp4")
            path.write_bytes(b"mock-rendered-video-by-host"*100)
        return True
    def IsRenderingInProgress(self):return False
    def GetRenderJobStatus(self,i):return {"JobStatus":"Complete"}
    def StopRendering(self):pass

class Manager:
    def __init__(self):
        self.created={}
    def CreateProject(self,name):
        if name in self.created:return None
        project=Project(name)
        self.created[name]=project
        return project
    def LoadProject(self,name):return self.created.get(name)
    def SaveProject(self):return True

class FakeResolve:
    def __init__(self):
        self.manager=Manager()
        self.version=[20,2,0,3]
        self.product="DaVinci Resolve Studio"
    def GetVersion(self):return self.version
    def GetVersionString(self):return "20.2.0.3"
    def GetProductName(self):return self.product
    def GetProjectManager(self):return self.manager
    def OpenPage(self,page):return page=="deliver"

class HostQATests(unittest.TestCase):
    def setUp(self):
        temp=TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root=Path(temp.name)
        self.app=FakeResolve()
        self.bundle=self.root/"CartoRigNative.ofx"
        self.bundle.write_bytes(b"compiled-windows-ofx-test-mock")
        self.pack=self.root/"pack"
        self.pack.mkdir()
    def test_live_host_preflight_checks_real_version_and_verified_pack(self):
        proof={"pack_id":"f"*64,"complete":False,
               "raster_sources":51,"vector_sources":215}
        with patch.object(qa,"verify_release",return_value=proof):
            status=qa.inspect(self.app,bundle=self.bundle,pack=self.pack)
        self.assertEqual(status["status"],"LIVE_RESOLVE_20_CONNECTED_OFFLINE_PACK_VERIFIED")
        self.assertFalse(status["source_raster_selected_in_inspector"])
        self.assertFalse(status["overlay_alpha_tested"])
        self.assertFalse(status["complete_natural_earth_release"])
        self.app.version[0]=21
        with patch.object(qa,"verify_release",return_value=proof):
            with self.assertRaisesRegex(qa.HostQAError,"20"):
                qa.inspect(self.app,bundle=self.bundle,pack=self.pack)
    def test_unverified_or_fake_full_pack_cannot_be_accepted(self):
        cases=[
            {"pack_id":"0"*64,"complete":True,"raster_sources":52,
             "vector_sources":215},
            {"pack_id":"0"*64,"complete":False,"raster_sources":50,
             "vector_sources":215},
            {"pack_id":"0"*64,"complete":False,"raster_sources":51,
             "vector_sources":200},
        ]
        for result in cases:
            with self.subTest(result=result),patch.object(
                    qa,"verify_release",return_value=result):
                with self.assertRaises(qa.HostQAError):
                    qa.inspect(self.app,bundle=self.bundle,pack=self.pack)
    def test_prepare_creates_only_new_cartorig_qa_project_and_real_ofx_timelines(self):
        result=qa.prepare(self.app,name="CartoRig_TestOnly_001")
        self.assertEqual(result["status"],
                         "RESOLVE_QA_PROJECT_PREPARED_USER_INSPECTOR_CONFIGURATION_REQUIRED")
        self.assertEqual([r["timeline"] for r in result["timelines"]],
                         ["CartoRig-1440p","CartoRig-4K"])
        project=self.app.manager.created["CartoRig_TestOnly_001"]
        self.assertEqual(project.timelines[0].settings["timelineResolutionWidth"],"2560")
        self.assertEqual(project.timelines[1].settings["timelineResolutionHeight"],"2160")
        self.assertTrue(all(x["ofx_map_generator_inserted"] for x in result["timelines"]))
        self.assertFalse(result["rendered_frames_verified"])
        with self.assertRaisesRegex(qa.HostQAError,"already exists"):
            qa.prepare(self.app,name="CartoRig_TestOnly_001")
        with self.assertRaisesRegex(qa.HostQAError,"only dedicated"):
            qa.prepare(self.app,name="ProductionProject")
    def test_render_requires_real_video_dimensions_and_never_auto_certs_overlay(self):
        name="CartoRig_TestHost_001"
        qa.prepare(self.app,name=name)
        path=self.root/"render-output"
        def width_of_video(p):
            return (2560,1440) if "2560x1440" in p.name else (3840,2160)
        with patch.object(qa,"_video_resolution",side_effect=width_of_video):
            result=qa.render(self.app,name=name,target=path)
        self.assertTrue(result["real_resolve_host_rendered"])
        self.assertFalse(result["full_resolve_acceptance"])
        self.assertFalse(result["pack_raster_selected_by_script"])
        self.assertFalse(result["overlay_alpha_tested"])
        self.assertEqual(len(result["renders"]),2)
        self.assertTrue(all(x["dimensions_independently_verified"] for x in result["renders"]))
        self.assertTrue((path/"CartoRig-QA-3840x2160.mp4").is_file())
    def test_bad_resolve_output_resolution_fails_closed(self):
        name="CartoRig_TestWrongPixels"
        qa.prepare(self.app,name=name)
        with patch.object(qa,"_video_resolution",return_value=(1280,720)):
            with self.assertRaisesRegex(qa.HostQAError,"dimensions differ"):
                qa.render(self.app,name=name,target=self.root/"wrong")
    def test_blocked_host_writes_a_report_without_success_claims(self):
        report=self.root/"qa-result.json"
        with patch.object(qa,"inspect",side_effect=qa.HostQAError("not installed")):
            with self.assertRaises(qa.HostQAError):
                qa.run_cli(mode="inspect",report_path=report,
                           project="CartoRig_Test",target=None,app=self.app,
                           bundle=self.bundle,pack=self.pack)
        actual=json.loads(report.read_text(encoding="utf-8"))
        self.assertEqual(actual["status"],"BLOCKED")
        self.assertFalse(actual["real_resolve_host_rendered"])
        self.assertFalse(actual["complete_natural_earth_release"])

if __name__=="__main__":
    unittest.main()
