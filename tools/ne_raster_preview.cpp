#include "cartorig.hpp"
#include "natural_earth_raster.hpp"
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
std::pair<std::uint64_t,std::uint64_t> rasterFrame(
    const cartorig::NaturalEarthRaster &atlas,int w,int h) {
  std::vector<std::uint8_t> pixels(static_cast<std::size_t>(w)*h*4,0);
  cartorig::Scene scene;
  scene.camera={0,0,2.0,0};
  cartorig::View view;
  view.width=w;
  view.height=h;
  view.camera=scene.camera;
  cartorig::Surface target{pixels.data(),0,0,w,h,w*4,
                           cartorig::PixelFormat::ByteRGBA};
  cartorig::RasterStats stats;
  cartorig::render(scene,cartorig::Dataset{},view,target);
  const auto before=pixels;
  cartorig::renderNaturalEarthRaster(atlas,view,target,&stats);
  if(stats.written<100||pixels==before)
    throw std::runtime_error("Natural Earth raster failed to paint real pixels");
  std::uint64_t digest=1469598103934665603ULL;
  for(const auto b:pixels){digest^=b;digest*=1099511628211ULL;}
  return {stats.written,digest};
}
struct BenchResult {
  double medianMs=0;
  std::uint64_t pixels=0;
  std::uint64_t frameHash=0;
};
BenchResult benchmark(const cartorig::NaturalEarthRaster &atlas,
                      int width,int height,int passes) {
  // Includes I/O/decode, geographic projection, alpha composition and
  // per-render cold tile LRU. This is NOT a Resolve host benchmark.
  std::vector<double> samples;
  BenchResult proof;
  for(int i=0;i<passes;++i){
    const auto start=std::chrono::steady_clock::now();
    const auto result=rasterFrame(atlas,width,height);
    const auto stop=std::chrono::steady_clock::now();
    if(result.first<100||result.second==0)
      throw std::runtime_error("Native benchmark failed to paint raster");
    if(i==0){ proof.pixels=result.first;proof.frameHash=result.second; }
    else if(result.first!=proof.pixels||result.second!=proof.frameHash)
      throw std::runtime_error("Nondeterministic native raster frame");
    samples.push_back(
      std::chrono::duration<double,std::milli>(stop-start).count());
  }
  std::sort(samples.begin(),samples.end());
  proof.medianMs=samples[static_cast<std::size_t>(passes/2)];
  return proof;
}
}

int main(int argc,char **argv){
  if(argc!=3 && !(argc==4 &&
      (std::string(argv[3])=="--bench" ||
       std::string(argv[3])=="--bench-matrix"))){
    std::cerr<<"Usage: cartorig_ne_raster_preview RASTER_ROOT ASSET_ID [--bench|--bench-matrix]\n";
    return 2;
  }
  try{
    const auto atlas=cartorig::loadNaturalEarthRaster(argv[1],argv[2]);
    const auto [written,hash]=rasterFrame(atlas,640,360);
    std::cout<<"raster_pixels="<<written<<" frame_hash="<<hash
             <<" atlas_levels="<<atlas.levels.size()<<"\n";
    if(argc==4 && std::string(argv[3])=="--bench"){
      const auto result=benchmark(atlas,1280,720,5);
      std::cout<<std::fixed<<std::setprecision(3)
               <<"bench_width=1280 bench_height=720 bench_passes=5"
               <<" median_frame_ms="<<result.medianMs<<"\n";
    }
    if(argc==4 && std::string(argv[3])=="--bench-matrix"){
      for(const auto size : {std::pair<int,int>{1280,720},
                             {2560,1440},{3840,2160}}){
        const auto result=benchmark(atlas,size.first,size.second,5);
        std::cout<<std::fixed<<std::setprecision(3)
                 <<"bench_width="<<size.first
                 <<" bench_height="<<size.second
                 <<" bench_passes=5 median_frame_ms="<<result.medianMs
                 <<" frame_hash="<<result.frameHash
                 <<" raster_pixels="<<result.pixels<<"\n";
      }
    }
    return 0;
  }catch(const std::exception &e){
    std::cerr<<"Raster renderer error: "<<e.what()<<"\n";
    return 1;
  }
}
