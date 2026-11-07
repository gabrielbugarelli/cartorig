#include "natural_earth_raster.hpp"
#include "json11.hpp"
#include "lodepng.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <limits>
#include <list>
#include <stdexcept>
#include <unordered_map>

namespace cartorig {
namespace {
constexpr int tileSize=256;
constexpr std::size_t tileBytes=tileSize*tileSize*4;
bool allowedAssetId(const std::string &value){
  if(value.empty()||value.size()>121)return false;
  for(unsigned char c:value)
    if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||
         (c>='0'&&c<='9')||c=='_'||c=='-'))return false;
  return true;
}
int integer(const json11::Json &json,const char*name,int min,int max){
  const auto &value=json[name];
  if(!value.is_number())throw std::invalid_argument("raster metadata integer missing");
  const auto v=value.number_value();
  if(!std::isfinite(v)||v<std::numeric_limits<int>::min()||
     v>std::numeric_limits<int>::max()||
     std::floor(v)!=v||v<min||v>max)
    throw std::invalid_argument("invalid raster metadata integer");
  return static_cast<int>(v);
}
std::vector<std::uint8_t> readTile(const std::filesystem::path &path,bool compressedPng){
  if(!std::filesystem::is_regular_file(path))
    throw std::runtime_error("Natural Earth offline raster tile missing");
  const auto bytes=std::filesystem::file_size(path);
  if(!compressedPng && bytes!=tileBytes)
    throw std::runtime_error("Natural Earth raw RGBA tile has invalid size");
  if(compressedPng && (bytes<1 || bytes>1024*1024))
    throw std::runtime_error("Natural Earth PNG tile exceeds bounded size");
  std::ifstream input(path,std::ios::binary);
  if(!input)throw std::runtime_error("Natural Earth raster tile could not be opened");
  if(compressedPng){
    std::vector<std::uint8_t> png(static_cast<std::size_t>(bytes));
    input.read(reinterpret_cast<char*>(png.data()),static_cast<std::streamsize>(png.size()));
    if(!input)throw std::runtime_error("Natural Earth compressed PNG tile read failed");
    // Bound the decoded dimensions *before* the PNG decoder allocates memory.
    // The v2 producer emits exactly 256x256, 8-bit RGBA PNG (color type 6).
    // Reject a tiny compressed decompression bomb with enormous IHDR width.
    const std::array<std::uint8_t,16> signatureAndIHDR{{
        137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82}};
    if(png.size()<33||
       !std::equal(signatureAndIHDR.begin(),signatureAndIHDR.end(),png.begin())||
       png[16]!=0||png[17]!=0||png[18]!=1||png[19]!=0||
       png[20]!=0||png[21]!=0||png[22]!=1||png[23]!=0||
       png[24]!=8||png[25]!=6||
       png[26]!=0||png[27]!=0||png[28]!=0)
      throw std::runtime_error("Natural Earth PNG tile has unsafe IHDR");
    std::vector<std::uint8_t> rgba;
    unsigned width=0,height=0;
    const unsigned error=lodepng::decode(rgba,width,height,png);
    if(error||width!=tileSize||height!=tileSize||rgba.size()!=tileBytes)
      throw std::runtime_error("Natural Earth PNG tile corrupt or wrong dimensions");
    return rgba;
  }
  std::vector<std::uint8_t> rgba(tileBytes);
  input.read(reinterpret_cast<char*>(rgba.data()),static_cast<std::streamsize>(tileBytes));
  if(!input)throw std::runtime_error("Natural Earth raw RGBA tile read failed");
  return rgba;
}
} // namespace

std::vector<NaturalEarthRasterAsset> listNaturalEarthRasterAssets(
    const std::filesystem::path &root){
  const auto path=root/"validated-raster-assets.json";
  const auto source=readText(path.string(),8*1024*1024);
  std::string error;
  const auto report=json11::Json::parse(source,error);
  if(!error.empty()||!report.is_object()||
     integer(report,"schema_version",1,1)!=1)
    throw std::invalid_argument("invalid Natural Earth offline raster catalogue");
  const auto &records=report["assets"].array_items();
  if(records.empty()||records.size()>10000)
    throw std::invalid_argument("offline Natural Earth raster catalogue is empty or too large");
  std::vector<NaturalEarthRasterAsset> assets;
  assets.reserve(records.size());
  for(const auto &item:records){
    if(!item.is_object()||item["status"].string_value()!="VALIDATED")
      throw std::invalid_argument("unvalidated raster catalogue asset");
    const auto id=item["asset_id"].string_value();
    const auto sourceId=item["source_id"].string_value();
    if(!allowedAssetId(id)||sourceId.empty()||sourceId.size()>160)
      throw std::invalid_argument("invalid raster asset provenance in offline catalogue");
    if(!std::filesystem::is_regular_file(root/id/"index.json"))
      throw std::invalid_argument("raster atlas missing from offline catalogue");
    assets.push_back({id,sourceId});
  }
  std::sort(assets.begin(),assets.end(),[](const auto &left,const auto &right){
    if(left.sourceId!=right.sourceId)return left.sourceId<right.sourceId;
    return left.assetId<right.assetId;
  });
  for(std::size_t i=1;i<assets.size();++i)
    if(assets[i-1].assetId==assets[i].assetId)
      throw std::invalid_argument("duplicate raster asset ID in offline catalogue");
  return assets;
}

NaturalEarthRaster loadNaturalEarthRaster(
    const std::filesystem::path &root,const std::string &assetId){
  if(!allowedAssetId(assetId))
    throw std::invalid_argument("invalid Natural Earth raster asset identifier");
  NaturalEarthRaster raster;
  raster.assetId=assetId;
  raster.directory=root/assetId;
  const std::string source=readText((raster.directory/"index.json").string(),1<<20);
  std::string error;
  const auto obj=json11::Json::parse(source,error);
  if(!error.empty()||!obj.is_object()||
     integer(obj,"schema_version",1,1)!=1||
     (obj["format"].string_value()!="cartorig-rgba-tiles-v1" &&
      obj["format"].string_value()!="cartorig-png-tiles-v2")||
     obj["asset_id"].string_value()!=assetId||
     integer(obj,"tile_size",tileSize,tileSize)!=tileSize)
    throw std::invalid_argument("unsupported Natural Earth raster metadata");
  const auto &extent=obj["extent"].array_items();
  if(extent.size()!=4)
    throw std::invalid_argument("invalid Natural Earth raster bounding rectangle");
  const double west=extent[0].number_value(),south=extent[1].number_value();
  const double east=extent[2].number_value(),north=extent[3].number_value();
  if(!std::isfinite(west)||!std::isfinite(south)||!std::isfinite(east)||
     !std::isfinite(north)||west<-180.001||east>180.001||
     south<-90.001||north>90.001||west>=east||south>=north)
    throw std::invalid_argument("invalid EPSG:4326 raster extent");
  raster.west=west;raster.south=south;raster.east=east;raster.north=north;
  raster.compressedPng=(obj["format"].string_value()=="cartorig-png-tiles-v2");
  const auto &levels=obj["levels"].array_items();
  if(levels.empty()||levels.size()>20)
    throw std::invalid_argument("invalid raster resolution pyramid");
  for(std::size_t n=0;n<levels.size();++n){
    auto &level=levels[n];
    NaturalEarthRasterLevel out;
    out.z=integer(level,"z",0,19);
    out.width=integer(level,"width",1,65536);
    out.height=integer(level,"height",1,65536);
    out.tilesX=integer(level,"tiles_x",1,256);
    out.tilesY=integer(level,"tiles_y",1,256);
    if(out.z!=static_cast<int>(n)||
       out.tilesX!=(out.width+tileSize-1)/tileSize||
       out.tilesY!=(out.height+tileSize-1)/tileSize||
       (!raster.levels.empty() &&
        (out.width<raster.levels.back().width||
         out.height<raster.levels.back().height)))
      throw std::invalid_argument("invalid raster tile pyramid topology");
    raster.levels.push_back(out);
  }
  return raster;
}
void renderNaturalEarthRaster(const NaturalEarthRaster &raster,
                              const View &view,Surface target,RasterStats *stats){
  if(!target.data||view.width<=0||view.height<=0||
     view.width>16384||view.height>16384||target.x1>=target.x2||
     target.y1>=target.y2||target.rowBytes==0||
     !std::isfinite(view.camera.zoom))
    throw std::invalid_argument("invalid Natural Earth raster output surface");
  if(raster.levels.empty())
    throw std::invalid_argument("empty Natural Earth raster level set");
  const double world=256.0*std::pow(2.0,view.camera.zoom)*
                     (view.width/1280.0);
  const double targetPixels=world*(raster.east-raster.west)/360.0;
  std::size_t z=0;
  // Smallest source level capable of delivering approximately one source
  // texel per destination pixel. No unnecessary high-res tile reads.
  while(z+1<raster.levels.size() &&
        raster.levels[z].width<targetPixels)++z;
  const auto &level=raster.levels[z];
  const std::string tileFolder=std::to_string(level.z);
  // Keep a strict per-render CPU tile budget, including when a 4K/8K frame
  // spans thousands of publisher tiles. A hard "1024 tiles" exception could
  // previously fail otherwise valid footage at wide viewports.
  // This LRU owns only per-render mutable state, so OFX tile requests can
  // execute on separate threads with no global locks or stale tiles.
  constexpr std::size_t maxResidentTiles=64; // 16 MiB RGBA upper bound
  struct CacheTile {
    std::vector<std::uint8_t> rgba;
    std::list<std::uint64_t>::iterator recent;
  };
  std::unordered_map<std::uint64_t,CacheTile> tiles;
  std::list<std::uint64_t> recent;
  auto sampleTile=[&](int tx,int ty)->const std::vector<std::uint8_t>&{
    const auto key=(static_cast<std::uint64_t>(ty)<<32)|
                    static_cast<std::uint32_t>(tx);
    auto existing=tiles.find(key);
    if(existing!=tiles.end()){
      recent.splice(recent.begin(),recent,existing->second.recent);
      return existing->second.rgba;
    }
    // Verify the next tile *before* evicting the last valid entry.
    const auto file=raster.directory/"tiles"/tileFolder/
                    (std::to_string(tx)+"_"+std::to_string(ty)+
                     (raster.compressedPng?".png":".rgba"));
    auto rgba=readTile(file,raster.compressedPng);
    if(tiles.size()==maxResidentTiles){
      const auto victim=recent.back();
      tiles.erase(victim);
      recent.pop_back();
    }
    recent.push_front(key);
    auto it=tiles.emplace(key,CacheTile{std::move(rgba),recent.begin()}).first;
    return it->second.rgba;
  };
  auto paintDecodedPixel=[&](int hostX,int hostY,int px,int py,
                           const std::vector<std::uint8_t> &tile){
    const std::size_t offset=(static_cast<std::size_t>(py%tileSize)*tileSize+
                              static_cast<std::size_t>(px%tileSize))*4;
    const Color pixel{tile[offset],tile[offset+1],tile[offset+2],tile[offset+3]};
    if(pixel.a==0)return;
    compositeColor(target,hostX,hostY,pixel,view.opacity);
    if(stats)++stats->written;
  };
  auto paintSample=[&](int hostX,int hostY,int px,int py){
    const auto &tile=sampleTile(px/tileSize,py/tileSize);
    paintDecodedPixel(hostX,hostY,px,py,tile);
  };
  if(view.camera.bearing==0.0){
    // Unrotated Mercator is separable: longitude depends only on screen X,
    // latitude only on screen Y. All projection math is evaluated through
    // the same unproject() function, preserving the existing source pixel
    // selection, antimeridian wrapping and OpenFX host coordinates.
    // Projection evaluations fall from O(width*height) to O(width+height).
    // The rotated-camera fallback below preserves the general projection.
    std::vector<int> sourceX(static_cast<std::size_t>(target.x2-target.x1),-1);
    std::vector<int> sourceY(static_cast<std::size_t>(target.y2-target.y1),-1);
    const double imageWidth=raster.east-raster.west;
    const double imageHeight=raster.north-raster.south;
    const int sampleScreenY=view.height-1-target.y1;
    for(int x=target.x1;x<target.x2;++x){
      const auto point=unproject(
          {x+0.5,sampleScreenY+0.5},view.camera,view.width,view.height);
      if(point.lon<raster.west||point.lon>=raster.east)continue;
      const double fx=(point.lon-raster.west)/imageWidth;
      if(!std::isfinite(fx))continue;
      sourceX[static_cast<std::size_t>(x-target.x1)]=std::clamp(
          static_cast<int>(fx*level.width),0,level.width-1);
    }
    for(int y=target.y1;y<target.y2;++y){
      const int screenY=view.height-1-y;
      const auto point=unproject(
          {target.x1+0.5,screenY+0.5},view.camera,view.width,view.height);
      if(point.lat<=raster.south||point.lat>raster.north)continue;
      const double fy=(raster.north-point.lat)/imageHeight;
      if(!std::isfinite(fy))continue;
      sourceY[static_cast<std::size_t>(y-target.y1)]=std::clamp(
          static_cast<int>(fy*level.height),0,level.height-1);
    }
    for(int hostY=target.y1;hostY<target.y2;++hostY){
      const int py=sourceY[static_cast<std::size_t>(hostY-target.y1)];
      if(py<0)continue;
      const int ty=py/tileSize;
      int lastTx=-1;
      const std::vector<std::uint8_t>* rowTile=nullptr;
      for(int hostX=target.x1;hostX<target.x2;++hostX){
        const int px=sourceX[static_cast<std::size_t>(hostX-target.x1)];
        if(px<0)continue;
        const int tx=px/tileSize;
        if(rowTile==nullptr||tx!=lastTx){
          // A constant projected Y and repeated X tile share the same tile
          // for a run of adjacent screen pixels. Avoid an unordered_map
          // lookup + LRU splice for every pixel. The pointer is used only
          // until the next sampleTile() call, so eviction is safe.
          rowTile=&sampleTile(tx,ty);
          lastTx=tx;
        }
        paintDecodedPixel(hostX,hostY,px,py,*rowTile);
      }
    }
    return;
  }
  for(int hostY=target.y1;hostY<target.y2;++hostY){
    const int screenY=view.height-1-hostY;
    for(int hostX=target.x1;hostX<target.x2;++hostX){
      const GeoPoint geo=unproject(
          {hostX+0.5,screenY+0.5},view.camera,view.width,view.height);
      if(geo.lon<raster.west||geo.lon>=raster.east||
         geo.lat<=raster.south||geo.lat>raster.north)continue;
      const double fx=(geo.lon-raster.west)/(raster.east-raster.west);
      const double fy=(raster.north-geo.lat)/(raster.north-raster.south);
      if(!std::isfinite(fx)||!std::isfinite(fy))continue;
      const int px=std::clamp(static_cast<int>(fx*level.width),0,level.width-1);
      const int py=std::clamp(static_cast<int>(fy*level.height),0,level.height-1);
      paintSample(hostX,hostY,px,py);
    }
  }
}
} // namespace cartorig
