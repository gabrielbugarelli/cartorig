"""Create a tiny, deliberately incomplete Natural Earth pack for Windows CI."""
from pathlib import Path
import json
import sys
from tools.natural_earth.build_pack import build_pack

root=Path(sys.argv[1])
for relative in (
    "vector/natural_earth_vector.gpkg",
    "vector/supplements.gpkg","vector/catalog.sqlite",
):
    path=root/relative
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(b"synthetic-offline-data-"+relative.encode("utf-8"))
rasters=root/"raster"
rasters.mkdir(parents=True,exist_ok=True)
(rasters/"validated-raster-assets.json").write_text(
    json.dumps({"complete":False,"sources_expected":1,
                "sources_converted":0,"failures":["synthetic fixture"]}),
    encoding="utf-8")
(rasters/"test/index.json").parent.mkdir(parents=True,exist_ok=True)
(rasters/"test/index.json").write_text('{"synthetic":true}',encoding="utf-8")
report=build_pack(root,{"complete":False},allow_incomplete=True)
assert report["status"]=="EXPERIMENTAL_INCOMPLETE"
print(report["pack_id"])
