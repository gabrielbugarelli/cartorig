#!/usr/bin/env python3
"""Resolve 20 hybrid OpenFX + Fusion architecture probe (not an end-user feature).

inspect: read-only host/binary preflight.
prepare: opt-in NEW QA project with CartoRig OFX Generator + Fusion nodes.
verify: reload QA project and verify independent keyed Fusion node state.
A passing script is not proof of Viewer/Deliver or geographic anchoring.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

from tools.resolve_host_acceptance import load_resolve, installed_bundle_path

FORMAT = "cartorig-hybrid-resolve20-probe-v1"
PROJECT_RE = re.compile(r"^CartoRig_Fusion_[A-Za-z0-9_]{1,48}$")
TIMELINE = "CartoRig-Hybrid-1080p"
GENERATOR = "CartoRig Map (Edit)"
NODES = {"bra": "CR_Spike_BRA", "ven": "CR_Spike_VEN",
         "bra_merge": "CR_Spike_BRA_Merge", "ven_merge": "CR_Spike_VEN_Merge"}


class ProbeError(RuntimeError):
    pass


def require(ok, error):
    if not ok:
        raise ProbeError(error)


def invoke(obj, name, *args):
    method = getattr(obj, name, None)
    require(callable(method), "Required Resolve API missing: " + name)
    value = method(*args)
    require(value is not False and value is not None, "Resolve refused: " + name)
    return value


def preflight(app, binary):
    version = invoke(app, "GetVersion")
    require(isinstance(version, (tuple, list)) and version and
            int(version[0]) == 20, "DaVinci Resolve Studio 20 required")
    require("DaVinci Resolve" in str(invoke(app, "GetProductName")),
            "Unexpected host product")
    invoke(app, "GetProjectManager")
    require(binary.is_file(), "CartoRig OpenFX binary not found: " + str(binary))
    hasher = hashlib.sha256()
    with binary.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            hasher.update(chunk)
    return {
        "resolve_version": str(invoke(app, "GetVersionString")),
        "ofx_sha256": hasher.hexdigest(),
        "ofx_binary": str(binary),
        "host_connected": True,
        "fusion_on_ofx_supported": False,
        "real_viewer_or_deliver_tested": False,
        "geographic_anchoring_tested": False,
    }


def validate_name(name):
    require(bool(PROJECT_RE.fullmatch(name)),
            "Only new CartoRig_Fusion_* QA project names are permitted")


def node(comp, name):
    tool = invoke(comp, "FindTool", name)
    require(tool is not None, "Fusion node missing: " + name)
    return tool


def set_input(tool, key, value, frame=None):
    fn = getattr(tool, "SetInput", None)
    require(callable(fn), "Fusion SetInput not available")
    args = (key, value) if frame is None else (key, value, frame)
    require(fn(*args) is not False, "Fusion rejected input " + key)


def connect(tool, input_name, source):
    fn = getattr(tool, "ConnectInput", None)
    require(callable(fn), "Fusion ConnectInput missing")
    require(fn(input_name, source) is not False,
            "Fusion rejected node connection " + input_name)


def name_tool(tool, name):
    invoke(tool, "SetAttrs", {"TOOLS_Name": name})
    attrs = invoke(tool, "GetAttrs")
    require(str(attrs.get("TOOLS_Name")) == name,
            "Fusion node name did not persist: " + name)


def _global_start(comp):
    attrs_fn = getattr(comp, "GetAttrs", None)
    if not callable(attrs_fn):
        return 0
    attrs = attrs_fn() or {}
    try:
        return int(attrs.get("COMPN_GlobalStart", 0))
    except (ValueError, TypeError):
        return 0


def add_independent_objects(comp):
    find_by_id = getattr(comp, "FindToolByID", lambda x: None)
    find_by_name = getattr(comp, "FindTool", lambda x: None)
    media_in = find_by_name("MediaIn1") or find_by_id("MediaIn")
    media_out = find_by_name("MediaOut1") or find_by_id("MediaOut")
    require(media_in and media_out,
            "Fusion on OFX Generator has no MediaIn/MediaOut: architecture BLOCKED")
    start = _global_start(comp)
    undo_started = False
    if callable(getattr(comp, "StartUndo", None)):
        comp.StartUndo("CartoRig hybrid QA object creation")
        undo_started = True
    completed = False
    try:
        bra = invoke(comp, "AddTool", "TextPlus", -4, 1)
        ven = invoke(comp, "AddTool", "TextPlus", -4, 3)
        m_bra = invoke(comp, "AddTool", "Merge", -1, 1)
        m_ven = invoke(comp, "AddTool", "Merge", 1, 3)
        for tool, label in ((bra, NODES["bra"]), (ven, NODES["ven"]),
                            (m_bra, NODES["bra_merge"]), (m_ven, NODES["ven_merge"])):
            name_tool(tool, label)
        set_input(bra, "StyledText", "BRA (probe only)")
        set_input(ven, "StyledText", "VEN (probe only)")
        set_input(m_bra, "Center", {1: .32, 2: .5})
        set_input(m_ven, "Center", {1: .68, 2: .5})
        connect(m_bra, "Background", media_in)
        connect(m_bra, "Foreground", bra)
        connect(m_ven, "Background", m_bra)
        connect(m_ven, "Foreground", ven)
        connect(media_out, "Input", m_ven)
        for merge, key_start, key_end in ((m_bra, 0, 12), (m_ven, 24, 36)):
            invoke(merge, "AddModifier", "Blend", "BezierSpline")
            set_input(merge, "Blend", 0.0, start + key_start)
            set_input(merge, "Blend", 1.0, start + key_end)
        completed = True
    finally:
        if undo_started:
            comp.EndUndo(completed)
    return {
        "fusion_graph_created": True,
        "independent_objects": 2,
        "independent_keyframe_tracks_requested": True,
        "first_comp_frame": start,
        "real_viewer_or_deliver_tested": False,
        "geographic_anchoring_tested": False,
    }


def prepare(app, name, *, allow_project_switch):
    validate_name(name)
    require(allow_project_switch,
            "Save your current Resolve work and pass --allow-switch-project")
    pm = invoke(app, "GetProjectManager")
    # Never touch a pre-existing project, even with the QA prefix.
    project = pm.CreateProject(name)
    require(project, "QA project already exists or creation was refused")
    timeline = invoke(invoke(project, "GetMediaPool"), "CreateEmptyTimeline", TIMELINE)
    invoke(project, "SetCurrentTimeline", timeline)
    invoke(timeline, "SetSetting", "timelineResolutionWidth", "1920")
    invoke(timeline, "SetSetting", "timelineResolutionHeight", "1080")
    item = invoke(timeline, "InsertOFXGeneratorIntoTimeline", GENERATOR)
    require(int(invoke(item, "GetFusionCompCount")) == 0,
            "New generator already contains a Fusion comp; refusing replacement")
    comp = invoke(item, "AddFusionComp")
    graph = add_independent_objects(comp)
    invoke(pm, "SaveProject")
    return {
        "status": "HYBRID_GRAPH_PREPARED_REOPEN_TEST_PENDING",
        "project": name, "timeline": TIMELINE,
        "ofx_generator_inserted_on_edit": True,
        **graph, "project_saved": True,
        "persistence_verified": False,
    }


def _find_timeline_item(project):
    timeline = None
    for index in range(1, int(invoke(project, "GetTimelineCount")) + 1):
        candidate = invoke(project, "GetTimelineByIndex", index)
        if invoke(candidate, "GetName") == TIMELINE:
            timeline = candidate
            break
    require(timeline is not None, "Hybrid QA timeline not found")
    items = []
    for index in range(1, int(invoke(timeline, "GetTrackCount", "video")) + 1):
        items.extend(timeline.GetItemListInTrack("video", index) or [])
    matches = [item for item in items if GENERATOR in str(item.GetName())]
    require(len(matches) == 1, "Expected exactly one CartoRig Map generator")
    return matches[0]


def _blend(tool, frame):
    fn = getattr(tool, "GetInput", None)
    require(callable(fn), "Fusion GetInput not available")
    try:
        return float(fn("Blend", frame))
    except (TypeError, ValueError) as error:
        raise ProbeError("Fusion returned invalid keyed Blend value") from error


def verify(app, name):
    validate_name(name)
    pm = invoke(app, "GetProjectManager")
    project = pm.LoadProject(name)
    require(project and str(project.GetName()) == name,
            "Dedicated QA project could not be reloaded")
    item = _find_timeline_item(project)
    require(int(invoke(item, "GetFusionCompCount")) >= 1,
            "Saved OFX generator lost its Fusion composition")
    comp = invoke(item, "GetFusionCompByIndex", 1)
    for value in NODES.values():
        node(comp, value)
    start = _global_start(comp)
    m_bra = node(comp, NODES["bra_merge"])
    m_ven = node(comp, NODES["ven_merge"])
    samples = {
        "bra_f18": _blend(m_bra, start + 18),
        "ven_f18": _blend(m_ven, start + 18),
        "bra_f40": _blend(m_bra, start + 40),
        "ven_f40": _blend(m_ven, start + 40),
    }
    require(samples["bra_f18"] >= .99 and samples["ven_f18"] <= .01 and
            samples["bra_f40"] >= .99 and samples["ven_f40"] >= .99,
            "Independent keyframes not persisted: " + str(samples))
    return {
        "status": "LIVE_HOST_FUSION_NODES_AND_KEYS_REOPENED",
        "project": name, "fusion_on_ofx_supported": True,
        "independent_animation_persisted": True,
        "keyframe_samples": samples,
        "real_viewer_or_deliver_tested": False,
        "geographic_anchoring_tested": False,
    }


def run_cli(mode, report, project, *, app=None, binary=None,
            allow_project_switch=False):
    validate_name(project)
    result = {
        "format": FORMAT, "schema_version": 1,
        "utc": datetime.now(timezone.utc).isoformat(),
        "mode": mode, "status": "NOT_RUN",
        "full_cartorig_product_accepted": False,
        "real_host_viewer_or_deliver_verified": False,
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    try:
        if app is None:
            app = load_resolve()
        result["preflight"] = preflight(app, binary or installed_bundle_path())
        if mode == "inspect":
            result["status"] = "HOST_CONNECTED_HYBRID_GATES_PENDING"
        elif mode == "prepare":
            result["action"] = prepare(app, project,
                                       allow_project_switch=allow_project_switch)
            result["status"] = result["action"]["status"]
        elif mode == "verify":
            result["action"] = verify(app, project)
            result["status"] = result["action"]["status"]
        else:
            raise ProbeError("Unsupported mode: " + str(mode))
        return result
    except Exception as exc:
        result["status"] = "BLOCKED"
        result["blocker"] = type(exc).__name__ + ": " + str(exc)[:1200]
        raise
    finally:
        tmp = report.with_suffix(report.suffix + ".tmp")
        tmp.write_text(json.dumps(result, indent=2, sort_keys=True,
                                  ensure_ascii=False) + "\n", encoding="utf-8")
        tmp.replace(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", required=True,
                        choices=("inspect", "prepare", "verify"))
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--project", default="CartoRig_Fusion_Architecture_QA")
    parser.add_argument("--plugin-binary", type=Path)
    parser.add_argument("--allow-switch-project", action="store_true")
    args = parser.parse_args()
    try:
        result = run_cli(args.mode, args.report, args.project,
                         binary=args.plugin_binary,
                         allow_project_switch=args.allow_switch_project)
    except (RuntimeError, OSError, ValueError) as exc:
        print("Hybrid architecture test BLOCKED: " + str(exc), file=sys.stderr)
        raise SystemExit(2) from exc
    print(json.dumps({"status": result["status"],
                      "report": str(args.report)}, indent=2))


if __name__ == "__main__":
    main()
