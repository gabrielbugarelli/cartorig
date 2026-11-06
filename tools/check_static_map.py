#!/usr/bin/env python3
"""Fail CI if the freshly created blank map changes as time advances."""
import hashlib
import pathlib
import sys

if len(sys.argv) < 3:
    raise SystemExit("usage: check_static_map.py frame0.ppm frame1.ppm ...")
frames = [pathlib.Path(p).read_bytes() for p in sys.argv[1:]]
hashes = [hashlib.sha256(data).hexdigest() for data in frames]
for path, digest in zip(sys.argv[1:], hashes):
    print(f"{path}: {digest}")
if any(digest != hashes[0] for digest in hashes[1:]):
    raise SystemExit("ERROR: default map animation detected: previews differ")
print(f"PASS: {len(frames)} independently rendered frames are pixel-identical")
