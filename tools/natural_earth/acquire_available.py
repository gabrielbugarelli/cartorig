#!/usr/bin/env python3
"""NE-SOURCE-02: acquire available Natural Earth rasters, NEVER certify a pack.

Download/resume official ZIP archives to a persistent local workstation disk.
Only an explicitly reviewed source outage is bypassed; it stays as a required
52nd source, not a fictitious acquired archive. No downloads at Resolve runtime.

Example:
 py -m tools.natural_earth.acquire_available --workspace D:\CartoRigBuild \
   --allow-network --skip-reviewed-unavailable --max-downloads 12
Repeat the identical command for each batch. Progress and per-source SHA256
live in workspace/downloads/source-archives.json, not in Git or Actions Cache.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

from tools.natural_earth import known_unavailable, materialize, release_pipeline


def acquire(*, workspace: Path, project_root: Path|None=None,
            allow_network: bool=False, max_downloads: int=12,
            skip_reviewed_unavailable: bool=False) -> dict:
    """Return an explicitly non-certifying status of the 52-source acquisition.

    status=AVAILABLE_SOURCES_VERIFIED is a terminal acquisition-only state
    for an acknowledged upstream gap. It must never be interpreted as
    NATURAL_EARTH_COMPLETE.
    """
    if max_downloads<0:
        raise ValueError("max_downloads must be nonnegative")
    root=(project_root or Path(__file__).resolve().parents[2]).resolve()
    workspace=workspace.resolve()
    workspace.mkdir(parents=True,exist_ok=True)
    official=release_pipeline._load_verified_inventory(workspace,allow_network)
    raster=dict(official,resources=[
        r for r in official["resources"] if r.get("theme")=="raster"])
    if len(raster["resources"])!=52:
        raise release_pipeline.ReleaseNotReady(
            "expected all 52 official publisher raster identities")
    exceptions=(known_unavailable.read_verified(root,official)
                if skip_reviewed_unavailable else {})
    manifest=materialize.materialize(
        raster,workspace/"downloads",allow_network=allow_network,
        max_downloads=max_downloads if allow_network else 0,
        known_unavailable=exceptions)
    summary=manifest["summary"]
    if summary["complete"]:
        status="ALL_52_ARCHIVES_VERIFIED_CONTENT_LOCK_PENDING"
    elif (skip_reviewed_unavailable and
          summary["known_unavailable"]==len(exceptions) and
          summary["remaining"]==0 and
          summary["verified"]+summary["known_unavailable"]==52):
        status="AVAILABLE_SOURCES_VERIFIED_NOT_CERTIFIED"
    else:
        status="PARTIAL_ACQUISITION"
    result={
        "schema_version":1,
        "format":"cartorig-ne-acquisition-status-v1",
        "status":status,
        "source_count":52,
        "verified_archives":summary["verified"],
        "known_unavailable":summary["known_unavailable"],
        "pending_or_blocked":summary["remaining"],
        "blocked_downloads":summary["blocked"],
        "release_certified":False,
        "pack_status":"NOT_BUILT",
        "archive_manifest":str(workspace/"downloads/source-archives.json"),
        "upstream_issue":"https://github.com/gabrielbugarelli/cartorig/issues/4"
            if summary["known_unavailable"] else None,
        "note":"Acquisition evidence only; 52-source approved SHA256 lock and full pack are mandatory for release.",
    }
    path=workspace/"acquisition-status.json"
    tmp=path.with_suffix(".json.tmp")
    try:
        tmp.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)
    return result


def main()->None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace",type=Path,required=True)
    parser.add_argument("--allow-network",action="store_true",
                        help="Only explicit release-machine HTTPS is permitted")
    parser.add_argument("--max-downloads",type=int,default=12)
    parser.add_argument("--skip-reviewed-unavailable",action="store_true",
                        help="Skip only the one reviewed publisher 404; never certify incomplete data")
    options=parser.parse_args()
    try:
        result=acquire(workspace=options.workspace,
                       allow_network=options.allow_network,
                       max_downloads=options.max_downloads,
                       skip_reviewed_unavailable=options.skip_reviewed_unavailable)
    except release_pipeline.ReleaseNotReady as error:
        print(json.dumps({"status":"INCOMPLETE","reason":str(error)}))
        raise SystemExit(2) from error
    print(json.dumps(result,indent=2))
    if result["status"]=="PARTIAL_ACQUISITION":
        raise SystemExit(2)

if __name__=="__main__":
    main()
