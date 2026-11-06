#include "natural_earth_geometry.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>

namespace cartorig {
namespace {
constexpr std::size_t MAX_BLOB=256*1024*1024;
constexpr std::size_t MAX_COORDS=8*1024*1024;
constexpr std::size_t MAX_PARTS=1024*1024;
struct Reader {
  const unsigned char *data;
  std::size_t size,pos=0,coords=0,parts=0;
  bool little=true;
  Reader(const void* p,std::size_t n):data(static_cast<const unsigned char*>(p)),size(n){
    if(!data||n<8||n>MAX_BLOB)throw std::invalid_argument("invalid GeoPackage blob size");
  }
  void need(std::size_t n)const{
    if(n>size-pos)throw std::invalid_argument("truncated GeoPackage geometry");
  }
  unsigned char u8(){need(1);return data[pos++];}
  std::uint32_t u32(){
    need(4);
    std::uint32_t x=0;
    if(little){for(int i=3;i>=0;--i)x=(x<<8)|data[pos+i];}
    else{for(int i=0;i<4;++i)x=(x<<8)|data[pos+i];}
    pos+=4;return x;
  }
  double f64(){
    need(8);std::uint64_t bits=0;
    if(little){for(int i=7;i>=0;--i)bits=(bits<<8)|data[pos+i];}
    else{for(int i=0;i<8;++i)bits=(bits<<8)|data[pos+i];}
    pos+=8;
    double value;std::memcpy(&value,&bits,sizeof(value));return value;
  }
  void incrementCoordinates(std::uint32_t count,unsigned dim){
    if(dim<2||dim>4||count>MAX_COORDS-coords)
      throw std::invalid_argument("GeoPackage vertex budget exceeded");
    const auto bytes=static_cast<std::size_t>(count)*dim*8;
    need(bytes);
    coords+=count;
  }
  std::uint32_t countParts(){
    const auto count=u32();
    if(count>MAX_PARTS-parts)throw std::invalid_argument("GeoPackage part budget exceeded");
    parts+=count;return count;
  }
  GeoPoint readPoint(unsigned dim){
    const double lon=f64(),lat=f64();
    for(unsigned i=2;i<dim;++i)(void)f64();
    if(!std::isfinite(lon)||!std::isfinite(lat)||
       std::abs(lon)>540||std::abs(lat)>90)
      throw std::invalid_argument("invalid geographic coordinate");
    return {lon,lat};
  }
};
enum class Type :std::uint32_t{
 Point=1,LineString=2,Polygon=3,MultiPoint=4,
 MultiLineString=5,MultiPolygon=6,Collection=7
};
void parseWKB(Reader& r,NaturalEarthGeometry&out,int depth=0){
  if(depth>12)throw std::invalid_argument("GeoPackage geometry nesting limit");
  const auto endian=r.u8();
  if(endian>1)throw std::invalid_argument("unknown WKB byte order");
  const auto prior=r.little;
  r.little=endian==1;
  const std::uint32_t typeRaw=r.u32();
  // ISO WKB 1000/2000/3000 flags for XYZ, XYM, XYZM are supported.
  // EWKB (SRID/high-bit flags) is intentionally rejected until verified.
  if(typeRaw&0xE0000000u)
    throw std::invalid_argument("EWKB extensions are not part of GeoPackage core geometry");
  const std::uint32_t stride=typeRaw/1000;
  if(stride>3)throw std::invalid_argument("unsupported dimensional WKB type");
  const unsigned dim=stride==0?2:stride==3?4:3;
  const auto type=typeRaw%1000;
  switch(static_cast<Type>(type)){
    case Type::Point:{
      r.incrementCoordinates(1,dim);
      out.points.push_back(r.readPoint(dim));break;
    }
    case Type::LineString:{
      const auto n=r.countParts();r.incrementCoordinates(n,dim);
      std::vector<GeoPoint> line;line.reserve(n);
      for(std::uint32_t i=0;i<n;++i)line.push_back(r.readPoint(dim));
      if(n>1)out.lines.push_back(std::move(line));
      break;
    }
    case Type::Polygon:{
      const auto count=r.countParts();
      Polygon poly;poly.rings.reserve(count);
      for(std::uint32_t k=0;k<count;++k){
        const auto n=r.countParts();r.incrementCoordinates(n,dim);
        std::vector<GeoPoint> ring;ring.reserve(n);
        for(std::uint32_t i=0;i<n;++i)ring.push_back(r.readPoint(dim));
        if(n>=4){
          if(ring.front().lon!=ring.back().lon||ring.front().lat!=ring.back().lat)
            throw std::invalid_argument("GeoPackage polygon ring is not closed");
          poly.rings.push_back(std::move(ring));
        }else if(n>0)throw std::invalid_argument("invalid GeoPackage polygon ring");
      }
      if(!poly.rings.empty())out.polygons.push_back(std::move(poly));
      break;
    }
    case Type::MultiPoint:
    case Type::MultiLineString:
    case Type::MultiPolygon:
    case Type::Collection:{
      const auto n=r.countParts();
      for(std::uint32_t i=0;i<n;++i)parseWKB(r,out,depth+1);
      break;
    }
    default:
      throw std::invalid_argument("unsupported GeoPackage WKB geometry type");
  }
  r.little=prior;
}
} // namespace

NaturalEarthGeometry decodeGeoPackageGeometry(const void *blob,std::size_t size){
  Reader r(blob,size);
  if(r.u8()!='G'||r.u8()!='P')throw std::invalid_argument("invalid GeoPackage magic");
  const auto version=r.u8();
  if(version!=0)throw std::invalid_argument("unsupported GeoPackage version");
  const auto flags=r.u8();
  if(flags&0xC0)throw std::invalid_argument("reserved GeoPackage header bits");
  r.little=(flags&1)!=0;
  const unsigned envelope=(flags>>1)&7;
  if(envelope>4)throw std::invalid_argument("unsupported GeoPackage envelope");
  const auto srs=static_cast<std::int32_t>(r.u32());
  if(srs!=4326)throw std::invalid_argument("Natural Earth geometry must be EPSG:4326");
  static constexpr unsigned envelopeDoubles[]{0,4,6,6,8};
  for(unsigned i=0;i<envelopeDoubles[envelope];++i)(void)r.f64();
  NaturalEarthGeometry result;result.srsId=srs;
  if(flags&0x10){
    if(r.pos!=size)throw std::invalid_argument("empty geometry has trailing WKB");
    return result;
  }
  parseWKB(r,result);
  if(r.pos!=size)throw std::invalid_argument("GeoPackage has trailing binary data");
  return result;
}
} // namespace cartorig
