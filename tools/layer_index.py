"""Deterministic, seekable Natural Earth layer geometry index.

Build-time conversion only. Does not download datasets or require Python on
end-user machines. Records original WGS84 geometry, byte offsets and hashes.
"""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path

SCHEMA = "cartorig.offline.layers/1"
LAYER_TYPES = {
    "land": {"Polygon", "MultiPolygon"},
    "lakes": {"Polygon", "MultiPolygon"},
    "coastline": {"LineString", "MultiLineString"},
    "boundaries": {"LineString", "MultiLineString"},
}

def _geometry_bounds(geometry: dict) -> tuple[list[float], bool]:
    coords = geometry.get("coordinates")
    if not isinstance(coords, (list, tuple)):
        raise ValueError("missing or malformed geographic coordinates")
    points: list[tuple[float, float]] = []
    crosses = False
    def visit(value):
        nonlocal crosses
        if isinstance(value, (list, tuple)) and len(value) >= 2 and all(
                isinstance(x, (int, float)) and not isinstance(x, bool) for x in value[:2]):
            lon, lat = float(value[0]), float(value[1])
            if not math.isfinite(lon) or not math.isfinite(lat) or abs(lon) > 180 or abs(lat) > 90:
                raise ValueError("coordinate outside finite WGS84 bounds")
            points.append((lon, lat))
            return
        if not isinstance(value, (list, tuple)):
            raise ValueError("malformed nested coordinates")
        last = None
        for child in value:
            before = len(points)
            visit(child)
            if len(points) > before and isinstance(child, (list, tuple)) and (
                len(child) >= 2 and isinstance(child[0], (float,int)) and isinstance(child[1], (float,int))
            ):
                if last is not None and abs(float(child[0])-last)>180:
                    crosses=True
                last = float(child[0])
    visit(coords)
    if not points:
        raise ValueError("empty layer feature")
    xs,ys=zip(*points)
    return [min(xs), min(ys), max(xs), max(ys)], crosses

def write_layer_index(out: Path, dataset: str, features: list[dict], version: str) -> dict:
    if dataset not in LAYER_TYPES:
        raise ValueError(f"unsupported indexed layer {dataset}")
    if not isinstance(features, list) or not features:
        raise ValueError("empty indexed layer")
    out.mkdir(parents=True, exist_ok=True)
    data_name=f"features_{dataset}.jsonl"
    index_name=f"index_{dataset}.json"
    rows=[]
    with (out/data_name).open("wb") as stream:
        for i,feature in enumerate(features):
            if not isinstance(feature,dict) or feature.get("type")!="Feature":
                raise ValueError(f"invalid feature record {dataset}:{i}")
            geo=feature.get("geometry")
            if not isinstance(geo,dict) or geo.get("type") not in LAYER_TYPES[dataset]:
                raise ValueError(f"invalid layer geometry type {dataset}:{i}")
            bbox,wrap=_geometry_bounds(geo)
            raw=(json.dumps(feature,ensure_ascii=False,separators=(",",":"),allow_nan=False)+"\n").encode("utf-8")
            if len(raw)>30_000_000:
                raise ValueError(f"layer feature exceeds safe single-record budget: {dataset}:{i}")
            offset=stream.tell()
            stream.write(raw)
            rows.append({"id":f"natural-earth:{dataset}:{i}","bbox":bbox,
                "crossesAntimeridian":wrap,"geometryType":geo["type"],
                "featureOffset":offset,"featureBytes":len(raw)})
    index={"schema":SCHEMA,"dataset":dataset,"version":version,
           "featureFile":data_name,"features":rows}
    raw=json.dumps(index,ensure_ascii=False,separators=(",",":"),allow_nan=False).encode("utf-8")
    (out/index_name).write_bytes(raw)
    return {"dataset":dataset,"filename":index_name,"sha256":hashlib.sha256(raw).hexdigest(),
            "data_file":data_name,"data_sha256":hashlib.sha256((out/data_name).read_bytes()).hexdigest(),
            "feature_count":len(rows)}
