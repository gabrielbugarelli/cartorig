"""Offline complete-manifest identity, tamper and symlink refusal."""
from __future__ import annotations
import json
from pathlib import Path
import tempfile
import unittest
from tools.natural_earth import build_pack,verify_release

class OfflineReleaseVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        for relative in build_pack.REQUIRED:
            path=self.root/relative
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(b"local synthetic artifact")
        raster=self.root/"raster/validated-raster-assets.json"
        raster.write_text(json.dumps({"complete":False,"sources_expected":1,
            "sources_converted":0,"failures":["synthetic"]}),encoding="utf-8")
        build_pack.build_pack(self.root,{"complete":False},allow_incomplete=True)

    def test_rehash_files_and_manifest_identity(self):
        report=verify_release.verify_release(self.root,allow_incomplete=True)
        self.assertFalse(report["complete"])
        self.assertEqual(report["files_verified"],len(build_pack.REQUIRED))
        with self.assertRaisesRegex(ValueError,"incomplete"):
            verify_release.verify_release(self.root)
        data=json.loads((self.root/"pack.json").read_text())
        data["pack_id"]="f"*64
        (self.root/"pack.json").write_text(json.dumps(data),encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"identity"):
            verify_release.verify_release(self.root,allow_incomplete=True)

    def test_reject_unlisted_files_symlinks_and_tampered_bytes(self):
        source=self.root/"vector/catalog.sqlite"
        source.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError,"tampered"):
            verify_release.verify_release(self.root,allow_incomplete=True)
        source.write_bytes(b"local synthetic artifact")
        extra=self.root/"unexpected.txt"
        extra.write_text("not in manifest",encoding="utf-8")
        with self.assertRaisesRegex(ValueError,"undeclared"):
            verify_release.verify_release(self.root,allow_incomplete=True)
        extra.unlink()
        extra.symlink_to(source)
        with self.assertRaisesRegex(ValueError,"symlink"):
            verify_release.verify_release(self.root,allow_incomplete=True)

if __name__=="__main__":
    unittest.main()
