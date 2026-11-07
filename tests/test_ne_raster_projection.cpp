// Reference per-pixel unproject() vs native atlas renderer.
// Guards the axis-aligned fast path, antimeridian wrapping, rotating-camera
// fallback, alpha compositing and OpenFX sub-rectangle host coordinates.
#include "cartorig.hpp"
#include "natural_earth_raster.hpp"
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs=std::filesystem;
using namespace cartorig;

namespace {
constexpr int tw=256;
Color pattern(int px,int py){
  return {static_cast<std::uint8_t>(px%256),
          static_cast<std::uint8_t>(py%256),
          static_cast<std::uint8_t>((px+py)%256),
          static_cast<std::uint8_t>(60+px%180)};
}
void require(bool condition,const char *message){
  if(!condition)throw std::runtime_error(message);
}
void writeTiles(const fs::path &root){
  fs::create_directories(root/"tiles"/"0");
  for(int tx=0;tx<2;++tx){
    std::vector<std::uint8_t> buffer(static_cast<std::size_t>(tw)*tw*4);
    for(int y=0;y<tw;++y)for(int x=0;x<tw;++x){
      const Color c=pattern(tx*tw+x,y);
      const auto pos=static_cast<std::size_t>(y*tw+x)*4;
      buffer[pos]=c.r;buffer[pos+1]=c.g;
      buffer[pos+2]=c.b;buffer[pos+3]=c.a;
    }
    std::ofstream out(root/"tiles"/"0"/
         (std::to_string(tx)+"_0.rgba"),std::ios::binary);
    out.write(reinterpret_cast<const char*>(buffer.data()),
              static_cast<std::streamsize>(buffer.size()));
    require(out.good(),"test atlas tile write failed");
  }
}
void fillBackground(std::vector<std::uint8_t> &rgba){
  for(std::size_t i=0;i<rgba.size();i+=4){
    rgba[i]=7;rgba[i+1]=15;rgba[i+2]=27;rgba[i+3]=83;
  }
}
void checkScene(const NaturalEarthRaster &raster,const Camera &camera,
                bool partial){
  constexpr int width=128,height=96;
  View view;
  view.width=width;view.height=height;
  view.camera=camera;view.opacity=0.8;
  std::vector<std::uint8_t> actual(width*height*4);
  std::vector<std::uint8_t> expected(actual.size());
  fillBackground(actual);fillBackground(expected);
  const int x1=partial?9:0,y1=partial?7:0;
  const int x2=partial?115:width,y2=partial?91:height;
  const auto base=static_cast<std::size_t>(y1*width+x1)*4;
  Surface received{actual.data()+base,x1,y1,x2,y2,width*4,PixelFormat::ByteRGBA};
  Surface reference{expected.data()+base,x1,y1,x2,y2,width*4,PixelFormat::ByteRGBA};
  RasterStats stats;
  renderNaturalEarthRaster(raster,view,received,&stats);
  std::uint64_t expectedWritten=0;
  for(int y=y1;y<y2;++y){
    const int screenY=view.height-1-y;
    for(int x=x1;x<x2;++x){
      const auto geo=unproject({x+0.5,screenY+0.5},
                               view.camera,view.width,view.height);
      if(geo.lon<raster.west||geo.lon>=raster.east||
         geo.lat<=raster.south||geo.lat>raster.north)continue;
      const double fx=(geo.lon-raster.west)/(raster.east-raster.west);
      const double fy=(raster.north-geo.lat)/(raster.north-raster.south);
      if(!std::isfinite(fx)||!std::isfinite(fy))continue;
      const int px=std::clamp(static_cast<int>(fx*512),0,511);
      const int py=std::clamp(static_cast<int>(fy*256),0,255);
      const auto c=pattern(px,py);
      if(c.a==0)continue;
      compositeColor(reference,x,y,c,view.opacity);
      ++expectedWritten;
    }
  }
  require(actual==expected,
    "axis-aligned/rotated native renderer differs from independent per-pixel reference");
  require(stats.written==expectedWritten,
    "native renderer pixel statistics differ from reference");
}
}

int main(){
  const auto id=std::chrono::steady_clock::now().time_since_epoch().count();
  const fs::path root=fs::temp_directory_path()/
     ("cartorig_projection_parity_"+std::to_string(id));
  try{
    writeTiles(root);
    NaturalEarthRaster atlas;
    atlas.directory=root;
    atlas.assetId="projection_reference";
    atlas.west=-180;atlas.south=-90;atlas.east=180;atlas.north=90;
    atlas.levels.push_back({0,512,256,2,1});
    checkScene(atlas,{0,0,3,0},false);
    checkScene(atlas,{175,12,3,0},true);
    checkScene(atlas,{-178,-15,4,0},false);
    checkScene(atlas,{0,0,3,37},false);
    checkScene(atlas,{175,12,3,-55},true);
    fs::remove_all(root);
    std::cout<<"PASS: axis-aligned column/row optimization equals per-pixel reference;"
                " rotated, antimeridian, ROI and alpha preserved\n";
    return 0;
  }catch(const std::exception &exc){
    fs::remove_all(root);
    std::cerr<<"Native raster projection parity failed: "<<exc.what()<<"\n";
    return 1;
  }
}
