#include "natural_earth_raster.hpp"
#include "json11.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <limits>
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
std::vector<std::uint8_t> readTile(const std::filesystem::path &path){
  if(!std::filesystem::is_regular_file(path)||
     std::filesystem::file_size(path)!=tileBytes)
    throw std::runtime_error("Natural Earth offline raster tile missing or corrupt");
  std::ifstream input(path,std::ios::binary);
  std::vector<std::uint8_t> rgba(tileBytes);
  input.read(reinterpret_cast<char*>(rgba.data()),static_cast<std::streamsize>(tileBytes));
  if(!input)throw std::runtime_error("Natural Earth offline raster tile read failed");
  return rgba;
}
} // namespace

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
     obj["format"].string_value()!="cartorig-rgba-tiles-v1"||
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
  std::unordered_map<std::uint64_t,std::vector<std::uint8_t>> tiles;
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
      const int tx=px/tileSize,ty=py/tileSize;
      const std::uint64_t key=
          (static_cast<std::uint64_t>(ty)<<32)|static_cast<std::uint32_t>(tx);
      auto it=tiles.find(key);
      if(it==tiles.end()){
        if(tiles.size()>=1024)
          throw std::runtime_error("Natural Earth raster tile cache budget exceeded");
        const auto file=raster.directory/"tiles"/tileFolder/
                        (std::to_string(tx)+"_"+std::to_string(ty)+".rgba");
        it=tiles.emplace(key,readTile(file)).first;
      }
      const auto &tile=it->second;
      const std::size_t offset=(static_cast<std::size_t>(py%tileSize)*tileSize+
                                static_cast<std::size_t>(px%tileSize))*4;
      const Color pixel{tile[offset],tile[offset+1],tile[offset+2],tile[offset+3]};
      if(pixel.a==0)continue;
      compositeColor(target,hostX,hostY,pixel,view.opacity);
      if(stats)++stats->written;
    }
  }
}
} // namespace cartorig
