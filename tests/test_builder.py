"""Offline fixture tests for CartoRig CRG1 builder; no external network."""
import importlib.util
import struct
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile

path=Path(__file__).resolve().parents[1]/"tools"/"build_ne.py"
spec=importlib.util.spec_from_file_location("build_ne",path)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def dbf(name):
    h=bytearray(65);h[0]=3
    struct.pack_into("<IHH",h,4,1,65,33)
    h[32:36]=b"NAME";h[43]=ord("C");h[48]=32;h[64]=13
    return bytes(h)+b" "+name.encode("utf-8").ljust(32,b" ")

def shp():
    coords=[(-55,-12),(-52,-12),(-52,-10),(-55,-10),(-55,-12)]
    xs=[a for a,b in coords];ys=[b for a,b in coords]
    box=min(xs),min(ys),max(xs),max(ys)
    rec=struct.pack("<I",5)+struct.pack("<ddddII",*box,1,len(coords))
    rec+=struct.pack("<I",0)+b"".join(struct.pack("<dd",*p) for p in coords)
    header=bytearray(100)
    struct.pack_into(">I",header,0,9994)
    struct.pack_into(">I",header,24,(108+len(rec))//2)
    struct.pack_into("<I",header,28,1000)
    struct.pack_into("<I",header,32,5)
    return bytes(header)+struct.pack(">II",1,len(rec)//2)+rec

class Tests(unittest.TestCase):
    def test_normalization(self):
        self.assertEqual(m.normalize("São PAULO"),"sao paulo")
        self.assertEqual(m.normalize("Amapá"),"amapa")

    def test_valid_full_pipeline(self):
        with TemporaryDirectory() as tmp:
            d=Path(tmp);name="ne_10m_admin_0_countries"
            with ZipFile(d/(name+".zip"),"w") as z:
                z.writestr(name+".dbf",dbf("Brazil"))
                z.writestr(name+".shp",shp())
            result=m.build(d,d/"installed",False,(("country",name,"10m_cultural","fixture"),))
            self.assertEqual(result["features"],1)
            self.assertFalse(result["network_required_by_runtime"])
            data=(d/"installed"/"geometry.crgeo").read_bytes()
            self.assertEqual(data[:4],b"CRG1")
            self.assertEqual(struct.unpack_from("<I",data,4)[0],1)
            self.assertIn("brasil",(d/"installed"/"catalog.tsv").read_text("utf-8"))
            self.assertEqual(result["geometry_sha256"],__import__("hashlib").sha256(data).hexdigest())

    def test_corruption(self):
        with self.assertRaisesRegex(ValueError,"SHP"):
            list(m.read_shp(b"abc"))
        with self.assertRaisesRegex(ValueError,"DBF"):
            m.read_dbf(b"abc")

    def test_offline_by_default(self):
        with TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                m.build(Path(tmp),Path(tmp)/"installed",False,(m.SOURCES[0],))

if __name__=="__main__":unittest.main()
