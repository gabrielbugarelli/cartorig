"""Publisher HTTPS byte-range recovery must never corrupt GIS source archives."""
from __future__ import annotations
from io import BytesIO
import hashlib
from pathlib import Path
import tempfile
import unittest

from tools.natural_earth.resumable_download import download, BLOCK

HOSTS={"naturalearth.s3.amazonaws.com","www.naturalearthdata.com"}
URL="https://naturalearth.s3.amazonaws.com/10m_raster/NE_TEST.zip"

class Reply:
    def __init__(self, body, *, status=200, headers=None, url=URL, interrupt=False):
        self.buffer=BytesIO(body)
        self.status=status
        self.headers=headers or {}
        self.url=url
        self.interrupt=interrupt
        self.read_count=0
    def __enter__(self):return self
    def __exit__(self,*args): self.buffer.close()
    def getcode(self):return self.status
    def geturl(self):return self.url
    def read(self,n):
        self.read_count+=1
        if self.interrupt and self.read_count>1:
            raise ConnectionResetError("simulated publisher network interruption")
        return self.buffer.read(n)

class Tests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path=Path(temp.name)/"publisher.zip"
        self.data=b"A"*BLOCK+b"B"*1579
    def call(self,opener,limit=None):
        return download(URL,self.path,allowed_hosts=HOSTS,max_bytes=limit or 8*BLOCK,
                        opener=opener)
    def interrupted(self):
        headers={"ETag":'"fixture-v1"',"Content-Length":str(len(self.data))}
        with self.assertRaises(ConnectionResetError):
            self.call(lambda *a,**k: Reply(self.data,headers=headers,interrupt=True))
        self.assertEqual(self.path.with_suffix(".zip.part").stat().st_size,BLOCK)
        return headers
    def test_resume_byte_range_and_sha256(self):
        self.interrupted()
        self.assertTrue(self.path.with_suffix(".zip.part.json").is_file())
        def resumed(request,timeout):
            self.assertEqual(request.headers["Range"],f"bytes={BLOCK}-")
            self.assertEqual(request.headers["If-range"],'"fixture-v1"')
            return Reply(self.data[BLOCK:],status=206,headers={
                "ETag":'"fixture-v1"',"Content-Length":str(len(self.data)-BLOCK),
                "Content-Range":f"bytes {BLOCK}-{len(self.data)-1}/{len(self.data)}"})
        self.assertEqual(self.call(resumed),
                         (len(self.data),hashlib.sha256(self.data).hexdigest()))
        self.assertEqual(self.path.read_bytes(),self.data)
        self.assertFalse(self.path.with_suffix(".zip.part.json").exists())
    def test_ignored_range_restarts_instead_of_appending(self):
        headers=self.interrupted()
        def ignored(request,timeout):
            self.assertIn("Range",request.headers)
            return Reply(self.data,headers=headers,status=200)
        self.assertEqual(self.call(ignored)[0],len(self.data))
        self.assertEqual(self.path.read_bytes(),self.data)
    def test_mismatched_resumed_range_fails_closed(self):
        self.interrupted()
        def bad(request,timeout):
            return Reply(self.data[BLOCK:],status=206,headers={
                "ETag":'"fixture-v1"',"Content-Length":str(len(self.data)-BLOCK),
                "Content-Range":f"bytes 0-{len(self.data)-BLOCK-1}/{len(self.data)}"})
        with self.assertRaisesRegex(ValueError,"byte range changed"):
            self.call(bad)
        self.assertFalse(self.path.exists())
    def test_changed_etag_never_appends_to_old_file(self):
        self.interrupted()
        def changed(request,timeout):
            return Reply(self.data[BLOCK:],status=206,headers={
                "ETag":'"fixture-v2"',"Content-Length":str(len(self.data)-BLOCK),
                "Content-Range":f"bytes {BLOCK}-{len(self.data)-1}/{len(self.data)}"})
        with self.assertRaisesRegex(ValueError,"identity or byte range changed"):
            self.call(changed)
        self.assertEqual(self.path.with_suffix(".zip.part").stat().st_size,BLOCK)
    def test_absent_validator_forces_clean_restart(self):
        with self.assertRaises(ConnectionResetError):
            self.call(lambda *a,**k: Reply(self.data,headers={
                "Content-Length":str(len(self.data))},interrupt=True))
        self.assertFalse(self.path.with_suffix(".zip.part.json").exists())
        def restart(request,timeout):
            self.assertNotIn("Range",request.headers)
            return Reply(self.data,headers={"Content-Length":str(len(self.data))})
        self.call(restart)
        self.assertEqual(self.path.read_bytes(),self.data)
    def test_unapproved_redirect_and_oversize_rejected(self):
        with self.assertRaisesRegex(ValueError,"approved HTTPS"):
            self.call(lambda *a,**k:Reply(self.data,url="https://evil.example/unsafe.zip"))
        with self.assertRaisesRegex(ValueError,"exceeds safe limit"):
            self.call(lambda *a,**k:Reply(self.data,headers={
                "ETag":'"fixture-v1"',"Content-Length":str(9*BLOCK)}))
        self.assertFalse(self.path.exists())

if __name__=="__main__":unittest.main()
