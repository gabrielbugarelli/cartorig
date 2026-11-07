#!/usr/bin/env python3
"""Reproducible Natural Earth COMPLETE release producer (never run in Resolve).

The only network path is explicitly gated by --allow-network. The release
machine downloads official data in resumable batches and verifies publisher
SHA256 before constructing a complete offline data pack.

Usage (repeat until all official sources are acquired):
 python -m tools.natural_earth.release_pipeline \
   --workspace /disk/ne-build --output /disk/CartoRigNaturalEarth \
   --allow-network --max-downloads 12 --resume
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import sqlite3
import zipfile

from tools.natural_earth import (
    assemble_pack, inventory, materialize, source_lock, supplements, verify_pack
)

OFFICIAL_VECTOR_ZIP="https://naciscdn.org/naturalearth/packages/natural_earth_vector.gpkg.zip"
PINNED_VECTOR_ZIP_SHA256="b9e2e7b3d5c2c59593f6eafc19be2ba87fb04788a90c57ccd6cf32a587b6ecc3"
MAX_VECTOR_ZIP_BYTES=750_000_000
MAX_VECTOR_EXPANDED_BYTES=5_500_000_000

class ReleaseNotReady(RuntimeError):
    """A partial producer step is safe to resume, not a completed release."""


def _load_verified_inventory(workspace:Path,allow_network:bool)->dict:
    path=workspace/"official_sources.json"
    if not path.is_file():
        if not allow_network:
            raise ReleaseNotReady(
                "Official inventory is absent; producer must run with --allow-network "
                "or supply a previously saved official_sources.json")
        report=inventory.audit()
        path.write_text(json.dumps(report,indent=2,ensure_ascii=False)+"\n",
                        encoding="utf-8")
    else:
        report=json.loads(path.read_text(encoding="utf-8"))
    if report.get("schema_version")!=1:
        raise ValueError("unsupported publisher source inventory")
    blocked=[row.get("url") for row in report.get("pages",[])
             if row.get("status")!="INDEXED"]
    if blocked or not report.get("resources"):
        raise ReleaseNotReady(
            "Source-page audit incomplete or empty; cannot certify full Natural Earth: "+
            str(blocked[:6]))
    return report


def _extract_pinned_vector(workspace:Path,allow_network:bool)->Path:
    root=workspace/"publisher"
    root.mkdir(exist_ok=True)
    archive=root/"natural_earth_vector.gpkg.zip"
    out=root/"natural_earth_vector.gpkg"
    proof=root/"vector-provenance.json"
    if out.is_file() and proof.is_file():
        previous=json.loads(proof.read_text(encoding="utf-8"))
        if (previous.get("publisher_zip_sha256")==PINNED_VECTOR_ZIP_SHA256 and
            previous.get("gpkg_sha256")==verify_pack.sha256_file(out)):
            return out
    if not archive.is_file():
        if not allow_network:
            raise ReleaseNotReady("Pinned official Natural Earth vector ZIP absent")
        count,digest=inventory.download_and_hash(
            OFFICIAL_VECTOR_ZIP,archive,max_bytes=MAX_VECTOR_ZIP_BYTES)
        if digest!=PINNED_VECTOR_ZIP_SHA256:
            archive.unlink(missing_ok=True)
            raise ValueError("official aggregate vector GeoPackage ZIP SHA256 changed")
    digest=verify_pack.sha256_file(archive)
    if digest!=PINNED_VECTOR_ZIP_SHA256:
        raise ValueError("pinned Natural Earth vector archive SHA256 mismatch")
    verify_pack.verify_zip(archive,max_items=300,
                           max_uncompressed=MAX_VECTOR_EXPANDED_BYTES)
    with zipfile.ZipFile(archive) as data:
        candidates=[file for file in data.infolist()
                    if file.filename.lower().endswith(".gpkg") and not file.is_dir()]
        if len(candidates)!=1 or candidates[0].file_size>MAX_VECTOR_EXPANDED_BYTES:
            raise ValueError("expected one bounded GeoPackage in official vector ZIP")
        staged=out.with_suffix(".gpkg.partial")
        try:
            with data.open(candidates[0]) as src,staged.open("wb") as dest:
                shutil.copyfileobj(src,dest,1024*1024)
            db=sqlite3.connect(staged.resolve().as_uri()+"?mode=ro",uri=True)
            try:
                if db.execute("PRAGMA integrity_check").fetchone()[0]!="ok":
                    raise ValueError("publisher GeoPackage fails integrity check")
                rows=db.execute(
                    "SELECT COUNT(*) FROM gpkg_contents WHERE data_type='features'").fetchone()[0]
                if rows<182:
                    raise ValueError("publisher aggregate GeoPackage lacks expected layers")
            finally:db.close()
            staged.replace(out)
        finally:staged.unlink(missing_ok=True)
    proof.write_text(json.dumps({
        "publisher":OFFICIAL_VECTOR_ZIP,
        "publisher_zip_sha256":digest,
        "gpkg_sha256":verify_pack.sha256_file(out),
        "status":"PINNED_VECTOR_GPKG_VERIFIED",
    },sort_keys=True,indent=2)+"\n",encoding="utf-8")
    return out


def _make_supplements(workspace:Path,manifest:dict,allow_network:bool)->Path:
    root=workspace/"publisher"
    root.mkdir(exist_ok=True)
    output=root/"supplements.gpkg"
    if output.is_file():
        return output
    if not allow_network:
        raise ReleaseNotReady("Missing official v5.1.2 supplemental GeoPackage")
    entries=supplements.manifest_entries(manifest)
    source_dir=root/"pinned-geojson"
    supplements.fetch_official(entries,source_dir)
    report=supplements.create_geopackage(manifest,source_dir,output)
    if not report.get("complete") or report.get("imported")!=33:
        raise ValueError("publisher v5.1.2 supplemental vector layers incomplete")
    (root/"supplements-provenance.json").write_text(
        json.dumps(report,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    return output


def produce(*,workspace:Path,output:Path,allow_network:bool=False,
            max_downloads:int=12,resume:bool=True,
            project_root:Path|None=None)->dict:
    if max_downloads<0:
        raise ValueError("max_downloads must be non-negative")
    root=project_root or Path(__file__).resolve().parents[2]
    vector_pin=root/"data/natural-earth/vector_layers_v5.1.2.json"
    supplement_pin=root/"data/natural-earth/aggregate_geojson_supplements_v5.1.2.json"
    if not vector_pin.is_file() or not supplement_pin.is_file():
        raise FileNotFoundError("pinned Natural Earth v5.1.2 source manifest missing")
    workspace=workspace.resolve()
    workspace.mkdir(parents=True,exist_ok=True)
    sources=_load_verified_inventory(workspace,allow_network)
    # Verify 215 vector layers using official GPKG + 33 pinned supplements.
    # Source-page vector ZIP links are alternate distribution formats and
    # need not be downloaded redundantly. Download all raster variants.
    raster_only=dict(sources,resources=[item for item in sources["resources"]
                                      if item.get("theme")=="raster"])
    if not raster_only["resources"]:
        raise ReleaseNotReady("Natural Earth inventory has no raster archives")
    acquired=materialize.materialize(
        raster_only,workspace/"downloads",allow_network=allow_network,
        max_downloads=max_downloads if allow_network else 0)
    if not acquired["summary"]["complete"]:
        raise ReleaseNotReady(
            "PARTIAL_DOWNLOAD: verified "+str(acquired["summary"]["verified"])+
            "/"+str(acquired["summary"]["expected"])+
            " publisher archives. Rerun the same command to resume, "
            "or inspect downloads/source-archives.json")
    # Acquisition SHA256 alone cannot approve a production release; it needs
    # a separately reviewed and committed publisher source lock.
    reviewed_lock=root/"data/natural-earth/raster_sources.lock.json"
    if not reviewed_lock.is_file():
        raise ReleaseNotReady(
            "All raster downloads acquired but the reviewed SHA256 lock is absent. "
            "Run tools.natural_earth.source_lock --inventory <inventory> "
            "--archives <downloads/source-archives.json> "
            "--out data/natural-earth/raster_sources.lock.json, then review/commit "
            "it before building a release")
    source_lock.verify(json.loads(reviewed_lock.read_text(encoding="utf-8")),
                       sources,acquired)
    vector=_extract_pinned_vector(workspace,allow_network)
    supplement_manifest=json.loads(supplement_pin.read_text(encoding="utf-8"))
    supplement=_make_supplements(workspace,supplement_manifest,allow_network)
    return assemble_pack.assemble(
        vector=vector,supplement=supplement,
        sources=workspace/"official_sources.json",
        archives=workspace/"downloads/source-archives.json",
        archive_root=workspace/"downloads",
        vector_pin=vector_pin,supplement_pin=supplement_pin,
        out=output,resume=resume)


def main()->None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--allow-network",action="store_true",
                        help="Release-machine-only opt-in to official publisher HTTPS")
    parser.add_argument("--max-downloads",type=int,default=12,
                        help="Maximum new publisher archives to fetch per run")
    parser.add_argument("--resume",action="store_true",
                        help="Resume SHA-verified staged raster conversion")
    options=parser.parse_args()
    try:
        result=produce(workspace=options.workspace,output=options.output,
                       allow_network=options.allow_network,
                       max_downloads=options.max_downloads,resume=options.resume)
        print(json.dumps({"status":"COMPLETE",**result},indent=2))
    except ReleaseNotReady as exc:
        print(json.dumps({"status":"INCOMPLETE","reason":str(exc)},indent=2))
        raise SystemExit(2)

if __name__=="__main__":
    main()
