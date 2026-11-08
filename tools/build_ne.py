#!/usr/bin/env python3
"""Offline Natural Earth 10m builder; downloads happen ONLY on CI/maintainer build."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import unicodedata
import urllib.request
from zipfile import ZipFile

SOURCES = [
 ("country", "ne_10m_admin_0_countries", "10m_cultural", "5.1.1"),
 ("state", "ne_10m_admin_1_states_provinces", "10m_cultural", "5.1.1"),
 ("city", "ne_10m_populated_places", "10m_cultural", "5.1.2"),
 ("land", "ne_10m_land", "10m_physical", "5.1.0"),
]
TYPES = {"country":0, "state":1, "city":2, "land":3}

def normalize(name):
    return "".join(c for c in unicodedata.normalize("NFKD", name).casefold()
                   if not unicodedata.combining(c))

def safe(text):
    return re.sub(r"[\t\n\r\x00-\x1f]+", " ", text).strip()

def read_member(path, stem, ext):
    with ZipFile(path) as z:
        names=[n for n in z.namelist() if n.replace("\\","/").split("/")[-1].lower()==(stem+ext).lower()]
        if len(names)!=1:
            raise ValueError("Missing or ambiguous Natural Earth member "+stem+ext)
        info=z.getinfo(names[0])
        if info.file_size>150_000_000: raise ValueError("Data member too large")
        return z.read(info)

def read_dbf(data):
    if len(data)<33: raise ValueError("Invalid DBF header")
    n,header,stride=struct.unpack_from("<IHH",data,4)
    if n>1_000_000 or header<33 or stride<2 or header+n*stride>len(data):
        raise ValueError("Invalid DBF dimensions")
    fields=[];start=1
    for i in range(32,header,32):
        if data[i]==13:break
        if i+32>header:raise ValueError("Malformed DBF field")
        raw=data[i:i+32]
        name=raw[:11].split(b"\0",1)[0].decode("ascii","ignore").lower()
        width=raw[16]
        if not name or not width:raise ValueError("Malformed DBF column")
        fields.append((name,start,width));start+=width
    if start>stride:raise ValueError("DBF overflow")
    result=[]
    for j in range(n):
        row=data[header+j*stride:header+(j+1)*stride]
        if row[:1]==b"*": result.append({});continue
        fields_out={}
        for name,offset,length in fields:
            raw=row[offset:offset+length].strip(b" \0")
            try:value=raw.decode("utf-8")
            except UnicodeDecodeError:value=raw.decode("cp1252","replace")
            fields_out[name]=safe(value)
        result.append(fields_out)
    return result

def read_shp(data):
    if len(data)<100 or struct.unpack_from(">I",data,0)[0]!=9994:
        raise ValueError("Invalid SHP header")
    if struct.unpack_from(">I",data,24)[0]*2!=len(data):
        raise ValueError("SHP size mismatch")
    offset=100
    while offset<len(data):
        if offset+8>len(data):raise ValueError("Truncated SHP record")
        _,words=struct.unpack_from(">II",data,offset)
        end=offset+8+2*words
        if words<2 or end>len(data):raise ValueError("Bad SHP length")
        rec=data[offset+8:end]
        typ=struct.unpack_from("<I",rec,0)[0]
        if typ==0:
            yield None
        elif typ in (1,11,21):
            if len(rec)<20:raise ValueError("Bad SHP point")
            x,y=struct.unpack_from("<dd",rec,4)
            yield(1,(x,y,x,y),[0],[(x,y)])
        elif typ in (3,5,13,15,23,25):
            if len(rec)<44:raise ValueError("Bad SHP polygon")
            bbox=struct.unpack_from("<dddd",rec,4)
            parts,pts=struct.unpack_from("<II",rec,36)
            if pts>4_000_000 or parts>100_000 or parts>pts or 44+4*parts+16*pts>len(rec):
                raise ValueError("Bad SHP geometry dimensions")
            starts=list(struct.unpack_from("<"+"I"*parts,rec,44))
            if starts and (starts[0]!=0 or any(a>=b for a,b in zip(starts,starts[1:])) or starts[-1]>=pts):
                raise ValueError("Invalid SHP ring positions")
            pos=44+parts*4
            xy=[struct.unpack_from("<dd",rec,pos+16*j) for j in range(pts)]
            yield (5 if typ in (5,15,25) else 3,bbox,starts,xy)
        else:raise ValueError("Unsupported SHP geometry type: "+str(typ))
        offset=end

def archive(root,stem,family,network):
    path=root/(stem+".zip")
    if not path.exists():
        if not network:raise FileNotFoundError(str(path))
        uri=f"https://naturalearth.s3.amazonaws.com/{family}/{stem}.zip"
        with urllib.request.urlopen(uri,timeout=120) as f: blob=f.read(150_000_001)
        if len(blob)>150_000_000:raise ValueError("Archive oversized")
        root.mkdir(parents=True,exist_ok=True)
        path.write_bytes(blob)
    with ZipFile(path) as f:
        if f.testzip() is not None:raise ValueError("Corrupt publisher zip")
    return path

def first(row,*keys):
    return next((row[x] for x in keys if row.get(x)),"")

def build(root,out,network=False,sources=SOURCES):
    root=Path(root);out=Path(out)
    out.mkdir(parents=True,exist_ok=True)
    records=[];provenance=[]
    tmp=out/"geometry.crgeo.tmp"
    with tmp.open("wb") as dst:
        dst.write(b"CRG1"+struct.pack("<I",0))
        count=0
        for kind,stem,family,version in sources:
            file=archive(root,stem,family,network)
            shp=list(read_shp(read_member(file,stem,".shp")))
            dbf=read_dbf(read_member(file,stem,".dbf"))
            if len(shp)!=len(dbf):raise ValueError("SHP/DBF count mismatch: "+stem)
            n=0
            for index,(shape,row) in enumerate(zip(shp,dbf),1):
                if not shape or not row:continue
                typ,bounds,parts,coords=shape
                if not all(-180.01<=x<=180.01 and -90.01<=y<=90.01 for x,y in coords):
                    raise ValueError("Invalid lat/lon in "+stem)
                name=first(row,"name_en","name","name_long","nameascii")
                if not name and kind!="land":continue
                name=name or ("Land "+str(index))
                parent=first(row,*(
                    ("adm0name","admin","geonunit") if kind in ("city","state") else ("continent",)))
                aliases={normalize(name)}
                for field in ("name","name_en","name_pt","nameascii","name_long","name_alt"):
                    if row.get(field):aliases.add(normalize(row[field]))
                if normalize(name)=="brazil":aliases.add("brasil")
                ident=f"{stem}:{index}"
                beg=dst.tell()
                raw=ident.encode("utf-8")
                dst.write(struct.pack("<H",len(raw))+raw)
                dst.write(struct.pack("<BIBddddII",TYPES[kind],index,typ,*bounds,len(parts),len(coords)))
                for part in parts:dst.write(struct.pack("<I",part))
                for x,y in coords:dst.write(struct.pack("<dd",x,y))
                records.append((ident,kind,name,parent,"|".join(sorted(aliases)),
                                *bounds,beg,dst.tell()-beg))
                n+=1;count+=1
            provenance.append({"dataset":stem,"type":kind,"publisher_version":version,
                               "features":n,
                               "url":f"https://naturalearth.s3.amazonaws.com/{family}/{stem}.zip",
                               "zip_sha256":hashlib.sha256(file.read_bytes()).hexdigest()})
        dst.seek(4);dst.write(struct.pack("<I",count))
    indexed=out/"catalog.tsv.tmp"
    with indexed.open("w",encoding="utf-8",newline="\n") as f:
        f.write("id\tkind\tname\tparent\taliases\tminx\tminy\tmaxx\tmaxy\toffset\tbytes\n")
        for row in records:f.write("\t".join(map(str,row))+"\n")
    manifest={"format":"CRG1","source":"Natural Earth public domain","features":count,
              "network_required_by_runtime":False,"datasets":provenance,
              "geometry_sha256":hashlib.sha256(tmp.read_bytes()).hexdigest(),
              "catalog_sha256":hashlib.sha256(indexed.read_bytes()).hexdigest()}
    (out/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    tmp.replace(out/"geometry.crgeo");indexed.replace(out/"catalog.tsv")
    return manifest

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--archives",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    parser.add_argument("--online-build",action="store_true")
    opts=parser.parse_args()
    print(json.dumps(build(opts.archives,opts.out,opts.online_build),indent=2))
