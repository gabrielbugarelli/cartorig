#!/usr/bin/env python3
"""Offline SHA256 and ZIP-structure verification for publisher data packs."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

class VerificationError(ValueError):
    pass

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while data := stream.read(1024 * 1024):
            h.update(data)
    return h.hexdigest()

def verify_zip(path: Path, *, max_items=10000, max_uncompressed=4_000_000_000):
    with zipfile.ZipFile(path) as z:
        items = z.infolist()
        if len(items) > max_items:
            raise VerificationError("too many ZIP entries")
        total = 0
        names = set()
        for item in items:
            name = PurePosixPath(item.filename.replace("\\", "/"))
            if (name.is_absolute() or ".." in name.parts or
                    item.filename.startswith(("/", "\\")) or "\0" in item.filename):
                raise VerificationError("unsafe archive entry: " + item.filename)
            if str(name) in names:
                raise VerificationError("duplicate ZIP member: " + item.filename)
            names.add(str(name))
            if item.flag_bits & 1:
                raise VerificationError("encrypted entries are forbidden")
            total += item.file_size
            if total > max_uncompressed:
                raise VerificationError("archive expands beyond safe limit")
            if item.file_size > 10_000_000 and item.compress_size * 500 < item.file_size:
                raise VerificationError("suspicious compression ratio")
            if item.CRC < 0:
                raise VerificationError("invalid CRC metadata")
        bad = z.testzip()
        if bad:
            raise VerificationError("invalid ZIP CRC: " + bad)
        return {"members": len(items), "uncompressed_bytes": total}

def verify_manifest(manifest: dict, root: Path) -> dict:
    failed, verified = [], []
    if manifest.get("schema_version") != 1:
        raise VerificationError("unsupported manifest schema")
    resources = manifest.get("resources", [])
    if not isinstance(resources, list):
        raise VerificationError("resources must be list")
    for item in resources:
        ident = item.get("resource_id", "(unknown)")
        file_name = item.get("file")
        digest = item.get("sha256")
        if not file_name or not digest:
            failed.append({"resource_id": ident, "reason": "missing file/hash"})
            continue
        rel = PurePosixPath(file_name)
        if rel.is_absolute() or ".." in rel.parts:
            failed.append({"resource_id": ident, "reason": "unsafe file path"})
            continue
        path = root.joinpath(*rel.parts)
        if not path.is_file():
            failed.append({"resource_id": ident, "reason": "file not installed"})
            continue
        size = path.stat().st_size
        if item.get("archive_bytes") != size or sha256_file(path) != digest:
            failed.append({"resource_id": ident, "reason": "hash or byte count mismatch"})
            continue
        try:
            if path.suffix.lower() == ".zip":
                verify_zip(path)
        except (VerificationError, zipfile.BadZipFile) as exc:
            failed.append({"resource_id": ident, "reason": str(exc)})
            continue
        verified.append(ident)
    # A source audit with only discovered URLs can NEVER pass as complete.
    return {"complete": bool(resources) and not failed and len(verified) == len(resources)
            and all(r.get("status") == "VERIFIED" for r in resources),
            "expected": len(resources), "verified": len(verified), "failed": failed}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    options = parser.parse_args()
    report = verify_manifest(json.loads(options.manifest.read_text(encoding="utf-8")), options.data_dir)
    result = json.dumps(report, indent=2)
    if options.output:
        options.output.write_text(result + "\n", encoding="utf-8")
    print(result)
    if not report["complete"]:
        raise SystemExit(1)

if __name__ == "__main__":
    main()
