"""Safe byte-range HTTPS recovery for publisher archives (release machine only).

Never imported by OpenFX: only the opt-in release producer can invoke it.
The partial file and an atomic metadata sidecar survive process exits. Resume
is allowed only when HTTP validators pin the response to the same object.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

BLOCK = 1 << 20
RANGE = re.compile(r"^bytes (\d+)-(\d+)/(\d+)$")
USER_AGENT = "CartoRigNaturalEarthBuild/0.2"

def _atomic_json(path: Path, payload: dict) -> None:
    writing = path.with_suffix(path.suffix + ".tmp")
    try:
        with writing.open("w", encoding="utf-8") as stream:
            json.dump(payload, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        writing.replace(path)
    finally:
        writing.unlink(missing_ok=True)

def _validator(headers):
    etag = headers.get("ETag", "").strip()
    if etag and not etag.startswith("W/"):
        return "etag", etag
    updated = headers.get("Last-Modified", "").strip()
    if updated:
        return "last_modified", updated
    return None, None

def _verify_redirect(original: str, actual: str, allowed: set[str]) -> None:
    first, target = urlsplit(original), urlsplit(actual)
    if (first.scheme != "https" or first.hostname not in allowed or
        target.scheme != "https" or target.hostname not in allowed or
        first.username or first.password or target.username or target.password):
        raise ValueError("archive request or redirect leaves approved HTTPS publisher hosts")

def _delete_partial(part: Path, state: Path) -> None:
    part.unlink(missing_ok=True)
    state.unlink(missing_ok=True)

def download(url: str, path: Path, *, allowed_hosts: set[str],
             max_bytes: int, opener=urlopen) -> tuple[int, str]:
    """Download and SHA256 a publisher archive, resuming on validated ranges.

    Interrupted transfers retain *.part and *.part.json. A server which does
    not support validated ranges safely restarts the file. Never append a 200
    response to a partial download or accept a mismatched Content-Range.
    """
    if max_bytes <= 0:
        raise ValueError("invalid maximum archive size")
    _verify_redirect(url, url, allowed_hosts)
    path.parent.mkdir(parents=True, exist_ok=True)
    part = path.with_suffix(path.suffix + ".part")
    state = part.with_suffix(part.suffix + ".json")
    resume = {}
    if part.exists() or state.exists():
        try:
            resume = json.loads(state.read_text(encoding="utf-8"))
            valid = (part.is_file() and not part.is_symlink() and
                     resume.get("url") == url and
                     resume.get("validator_kind") in ("etag", "last_modified") and
                     isinstance(resume.get("validator"), str) and
                     bool(resume["validator"]) and
                     isinstance(resume.get("total"), int) and
                     0 < resume["total"] <= max_bytes and
                     0 < part.stat().st_size <= resume["total"])
            if not valid:
                raise ValueError("invalid partial transfer state")
        except (OSError, ValueError, TypeError, KeyError):
            _delete_partial(part, state)
            resume = {}
    offset = part.stat().st_size if resume else 0
    if resume and offset == resume["total"]:
        digest = hashlib.sha256()
        with part.open("rb") as f:
            for piece in iter(lambda: f.read(BLOCK), b""):
                digest.update(piece)
        part.replace(path)
        state.unlink(missing_ok=True)
        return offset, digest.hexdigest()

    headers = {"User-Agent": USER_AGENT}
    if offset:
        headers["Range"] = f"bytes={offset}-"
        headers["If-Range"] = resume["validator"]
    request = Request(url, headers=headers)
    try:
        source = opener(request, timeout=90)
    except HTTPError as error:
        if error.code == 416 and offset:
            _delete_partial(part, state)
            source = opener(Request(url, headers={"User-Agent": USER_AGENT}), timeout=90)
            offset = 0
        else:
            raise

    with source:
        _verify_redirect(url, source.geturl(), allowed_hosts)
        status = source.getcode()
        if status not in (200, 206):
            raise ValueError(f"unexpected archive HTTP status {status}")
        if status == 206 and not offset:
            raise ValueError("unsolicited partial publisher HTTP response")
        kind, validator = _validator(source.headers)
        if status == 206:
            match = RANGE.fullmatch(source.headers.get("Content-Range", ""))
            if not match:
                raise ValueError("missing or invalid Content-Range for resumed transfer")
            start, end, total = map(int, match.groups())
            if (start != offset or end < start or
                total != resume["total"] or end >= total or
                (kind != resume["validator_kind"] or
                 validator != resume["validator"])):
                raise ValueError("resumed publisher identity or byte range changed")
            content_length = source.headers.get("Content-Length")
            if content_length is not None and int(content_length) != end - start + 1:
                raise ValueError("resumed response Content-Length mismatch")
        else:
            offset = 0
            content_length = source.headers.get("Content-Length")
            total = int(content_length) if content_length is not None else None
            if total is not None and (total <= 0 or total > max_bytes):
                raise ValueError("publisher Content-Length exceeds safe limit")
            if not validator or not total:
                _delete_partial(part, state)
            else:
                _atomic_json(state, {"url": url, "validator_kind": kind,
                                     "validator": validator, "total": total})
        digest = hashlib.sha256()
        if offset:
            with part.open("rb") as existing:
                for piece in iter(lambda: existing.read(BLOCK), b""):
                    digest.update(piece)
        with part.open("ab" if offset else "wb") as output:
            size = offset
            while True:
                chunk = source.read(BLOCK)
                if not chunk:
                    break
                size += len(chunk)
                if size > max_bytes or (total is not None and size > total):
                    raise ValueError("archive exceeded safe size / declared HTTP length")
                output.write(chunk)
                digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
        if size <= 0 or (total is not None and size != total):
            raise IOError("publisher archive download interrupted or truncated")
        part.replace(path)
        state.unlink(missing_ok=True)
        return size, digest.hexdigest()
