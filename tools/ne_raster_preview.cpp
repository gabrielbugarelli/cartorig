#include "cartorig.hpp"
#include "natural_earth_raster.hpp"
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>
int main(int argc,char **argv){
  if(argc!=3){
    std::cerr<<"Usage: cartorig_ne_raster_preview RASTER_ROOT ASSET_ID\n";
    return 2;
  }
  try{
    const auto atlas=cartorig::loadNaturalEarthRaster(argv[1],argv[2]);
    constexpr int w=640,h=360;
    std::vector<std::uint8_t> pixels(w*h*4,0);
    cartorig::Scene scene;
    scene.camera={0,0,2.0,0};
    cartorig::View view;view.width=w;view.height=h;view.camera=scene.camera;
    cartorig::Surface target{pixels.data(),0,0,w,h,w*4,cartorig::PixelFormat::ByteRGBA};
    cartorig::RasterStats stats;
    cartorig::render(scene,cartorig::Dataset{},view,target);
    const auto before=pixels;
    cartorig::renderNaturalEarthRaster(atlas,view,target,&stats);
    if(stats.written<100||pixels==before)
      throw std::runtime_error("Natural Earth raster failed to paint real pixels");
    std::uint64_t digest=1469598103934665603ULL;
    for(const auto b:pixels){digest^=b;digest*=1099511628211ULL;}
    std::cout<<"raster_pixels="<<stats.written<<" frame_hash="<<digest
             <<" atlas_levels="<<atlas.levels.size()<<"\n";
    return 0;
  }catch(const std::exception &e){
    std::cerr<<"Raster renderer error: "<<e.what()<<"\n";
    return 1;
  }
}
