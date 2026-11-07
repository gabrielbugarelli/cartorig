"""Archive paths and links must never escape local release staging."""
import tempfile
from pathlib import Path
import stat
import unittest
import zipfile
from tools.natural_earth.verify_pack import verify_zip,VerificationError

class ZipSecurity(unittest.TestCase):
    def setUp(self):
        tmp=tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup)
        self.path=Path(tmp.name)/"test.zip"
    def test_reject_publisher_zip_symbolic_links(self):
        info=zipfile.ZipInfo("map/linked-file.tif")
        info.create_system=3
        info.external_attr = (stat.S_IFLNK|0o777)<<16
        with zipfile.ZipFile(self.path,"w") as z:z.writestr(info,"../../outside")
        with self.assertRaisesRegex(VerificationError,"symbolic links"):
            verify_zip(self.path)
    def test_reject_windows_drive_path(self):
        with zipfile.ZipFile(self.path,"w") as z:z.writestr("C:/windows/system32/naturalearth.tif","test")
        with self.assertRaisesRegex(VerificationError,"Windows drive path"):
            verify_zip(self.path)
    def test_normal_publisher_zip_is_accepted(self):
        with zipfile.ZipFile(self.path,"w") as z:
            z.writestr("map/NE_RASTER.tif",b"TIFF")
            z.writestr("map/NE_RASTER.tfw",b"1\n0\n0\n-1\n0\n0\n")
        self.assertEqual(verify_zip(self.path)["members"],2)

if __name__=="__main__":unittest.main()
