#include "natural_earth_catalog.hpp"
#include "cartorig.hpp"
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

// Standalone end-to-end test harness. The production path uses the exact
// same NativeCatalog->Dataset->CartoRig CPU-render chain in OpenFX.
int main(int argc,char**argv){
  if(argc!=3&&argc!=4){
    std::cerr<<"Usage: cartorig_ne_preview SOURCE.gpkg SCALE [OPTIONAL_LAYER]\n";return 2;
  }
  try {
    auto dataset=cartorig::NaturalEarthCatalog::countryPolygons(argv[1],argv[2]);
    std::size_t polygonCount=0;
    for(const auto&f:dataset.features)polygonCount+=f.polygons.size();
    if(dataset.features.empty()||polygonCount==0)
      throw std::runtime_error("no renderable Natural Earth polygons");
    constexpr int w=640,h=360;
    std::vector<std::uint8_t> frame(w*h*4,0);
    cartorig::Scene scene;
    scene.camera={-45,-15,2,0};
    cartorig::View view;view.width=w;view.height=h;view.frame=0;
    view.camera=scene.camera;
    cartorig::Surface surface{frame.data(),0,0,w,h,w*4,cartorig::PixelFormat::ByteRGBA};
    cartorig::RasterStats stats;
    cartorig::render(scene,dataset,view,surface,&stats);
    std::size_t overlayCount=0;
    if(argc==4){
      const auto overlay=cartorig::NaturalEarthCatalog::layerGeometries(argv[1],argv[3]);
      overlayCount=overlay.size();
      const auto before=stats.written;
      cartorig::renderNaturalEarthLayer(
          overlay,view,surface,cartorig::Color{76,144,110,155},
          cartorig::Color{96,193,231,235},cartorig::Color{255,207,115,245},&stats);
      if(stats.written==before)
        throw std::runtime_error("optional Natural Earth layer did not paint any pixels");
    }
    std::uint64_t digest=1469598103934665603ULL;
    for(std::uint8_t b:frame){digest^=b;digest*=1099511628211ULL;}
    if(stats.written<=static_cast<std::uint64_t>(w*h))
      throw std::runtime_error("country geometry did not paint any visible pixels");
    std::cout<<"countries="<<dataset.features.size()<<" polygons="<<polygonCount
             <<" painted="<<stats.written<<" frame_hash="<<digest<<" overlay_features="<<overlayCount<<"\n";
    return 0;
  }catch(const std::exception&e){
    std::cerr<<"Natural Earth end-to-end render failed: "<<e.what()<<"\n";
    return 1;
  }
}
