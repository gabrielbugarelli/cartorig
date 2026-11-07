#!/usr/bin/env python3
"""Freeze/review raster publisher digests before any Complete data-pack release.

The initial release-source audit runs only via the explicit [source-probe] tag;
this job stores a small JSON report, never the full 52-archive raster corpus.
The first SHA256 digest is calculated from authentic publisher content and
committed after independent review. This lock then prevents silent upstream
changes, stale checkpoints, and self-declared download-manifest hashes from
certifying a later release. Installed OpenFX never reads this module.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

EXPECTED_VARIANTS=52
SCALES={"10m","50m"}
ALLOWED_HOSTS={"www.naturalearthdata.com","naturalearthdata.com",
               "naciscdn.org","naturalearth.s3.amazonaws.com"}
HEX64=re.compile(r"^[0-9a-f]{64}$")

class SourceLockError(ValueError):
    pass

def _source_map(inventory:dict,expected:int)->dict:
    if inventory.get("schema_version")!=1:
        raise SourceLockError("unsupported official inventory schema")
    if (not inventory.get("pages") or
        any(x.get("status")!="INDEXED" for x in inventory["pages"])):
        raise SourceLockError("publisher discovery contains blocked or absent pages")
    selected=[r for r in inventory.get("resources",[])
              if r.get("theme")=="raster"]
    if len(selected)!=expected:
        raise SourceLockError(f"expected {expected} raster download variants, got {len(selected)}")
    found={}
    for item in selected:
        ident=item.get("resource_id")
        url=item.get("url","")
        parsed=urlsplit(url)
        if (not isinstance(ident,str) or not ident.startswith("ne-") or
            ident in found or item.get("scale") not in SCALES or
            parsed.scheme!="https" or parsed.hostname not in ALLOWED_HOSTS or
            parsed.username or parsed.password or parsed.query or parsed.fragment):
            raise SourceLockError("invalid or duplicated raster publisher source identity")
        found[ident]=item
    return found

def freeze(inventory:dict,acquired:dict,*,expected:int=EXPECTED_VARIANTS)->dict:
    """Build a reviewed candidate lock: does NOT claim publisher-certified SHA."""
    found=_source_map(inventory,expected)
    records=acquired.get("resources")
    if acquired.get("schema_version")!=1 or not isinstance(records,list):
        raise SourceLockError("missing official source archive proof")
    if len(records)!=len(found):
        raise SourceLockError("acquisition source count differs from publisher inventory")
    proofs={}
    for item in records:
        ident=item.get("resource_id")
        if ident in proofs or ident not in found:
            raise SourceLockError("duplicate/unrecognized acquired raster source")
        proofs[ident]=item
    locked=[]
    for ident in sorted(found):
        src=found[ident]
        proof=proofs.get(ident,{})
        sha=proof.get("sha256")
        size=proof.get("archive_bytes")
        acquisition=proof.get("acquisition_url",src["url"])
        parsed=urlsplit(acquisition)
        if (proof.get("status")!="VERIFIED" or
            src["url"]!=proof.get("url") or
            proof.get("theme")!="raster" or
            proof.get("scale")!=src["scale"] or
            not isinstance(sha,str) or not HEX64.fullmatch(sha) or
            not isinstance(size,int) or size<=0 or
            parsed.scheme!="https" or parsed.hostname not in ALLOWED_HOSTS):
            raise SourceLockError("not independently ready for source freeze: "+ident)
        locked.append({
            "resource_id":ident,"scale":src["scale"],"url":src["url"],
            "source_page":src.get("source_page"),
            "label":src.get("label"),
            "theme_version":src.get("theme_version"),
            "archive_sha256":sha,"archive_bytes":size,
        })
    return {
        "schema_version":1,"format":"cartorig-natural-earth-raster-lock-v1",
        "publisher":"Natural Earth / NACIS",
        "baseline_variants":len(locked),
        "verification_note":"Derived from official publisher downloads; review and commit lock before distribution.",
        "resources":locked,
    }

def verify(lock:dict,inventory:dict,acquired:dict,*,expected:int=EXPECTED_VARIANTS)->None:
    """Reject changed source URLs, metadata, hashes, and missing variants."""
    if (lock.get("schema_version")!=1 or
        lock.get("format")!="cartorig-natural-earth-raster-lock-v1" or
        lock.get("baseline_variants")!=expected):
        raise SourceLockError("missing/unsupported reviewed raster source lock")
    ideal=freeze(inventory,acquired,expected=expected)
    if lock!=ideal:
        raise SourceLockError("publisher/acquisition differs from reviewed raster SHA256 lock")

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory",type=Path,required=True)
    parser.add_argument("--archives",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--verify",action="store_true",
                        help="Do not write; fail if reviewed lock differs")
    options=parser.parse_args()
    inventory=json.loads(options.inventory.read_text(encoding="utf-8"))
    acquired=json.loads(options.archives.read_text(encoding="utf-8"))
    if options.verify:
        verify(json.loads(options.out.read_text(encoding="utf-8")),inventory,acquired)
        print("PASS: all 52 acquired raster SHA256 values agree with frozen source lock")
    else:
        if options.out.exists():
            raise FileExistsError("refusing to silently rewrite reviewed source lock")
        locked=freeze(inventory,acquired)
        options.out.parent.mkdir(parents=True,exist_ok=True)
        options.out.write_text(json.dumps(locked,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8")
        print("CANDIDATE_LOCK_WRITTEN: review/commit SHA256 source lock before release")

if __name__=="__main__":main()
