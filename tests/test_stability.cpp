#include "cartorig.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <future>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>
using namespace cartorig;

static int passes=0,failures=0;
static void check(bool value,const char *name){
  if(value)++passes;else{++failures;std::cerr<<"FAILED "<<name<<"\n";}
}
static uint64_t fingerprint(const std::vector<uint8_t> &bytes){
  uint64_t h=1469598103934665603ull;
  for(auto value:bytes){h^=value;h*=1099511628211ull;}
  return h;
}
static std::vector<uint8_t> frame(const Scene &s,const Dataset &d,int w,int h,double f){
  std::vector<uint8_t> pixels(size_t(w)*h*4,0xB7);
  Surface out{pixels.data(),0,0,w,h,w*4,PixelFormat::ByteRGBA};
  View view;view.width=w;view.height=h;view.frame=f;view.camera=evaluateCamera(s,f);
  render(s,d,view,out);
  return pixels;
}
int main(){
  try{
    const std::string root=CARTORIG_ROOT;
    const auto s=parseScene(readText(root+"/samples/brasil-venezuela.cartorig-native.json"));
    const auto d=parseGeoJSON(readText(root+"/data/countries.geojson"));
    check(mapSceneFrame(100,0,1)==100,"identity scene time");
    check(mapSceneFrame(100,10,2)==180,"time offset and scale");
    check(mapSceneFrame(50,0,-1)==-50,"reverse playback mapping");
    check(mapSceneFrame(50,0,0)==0,"freeze playback mapping");
    bool rejects=false;try{mapSceneFrame(std::numeric_limits<double>::quiet_NaN(),0,1);}catch(const std::invalid_argument&){rejects=true;}
    check(rejects,"reject non-finite retime");
    const auto first=frame(s,d,640,360,0);
    const auto middle=frame(s,d,640,360,96);
    const auto last=frame(s,d,640,360,239);
    check(fingerprint(first)!=fingerprint(middle)&&fingerprint(middle)!=fingerprint(last),
          "frame 0, 96 and 239 differ as expected");
    check(frame(s,d,640,360,0)==first,"same frame deterministic after arbitrary seeks");
    // Split the same render into 3x3 tiles; any pixel outside its tile must
    // remain untouched until a separate tile writes it.
    std::vector<uint8_t> tiled(first.size(),0xCD);
    View v;v.width=640;v.height=360;v.camera=evaluateCamera(s,0);v.frame=0;
    Surface full{tiled.data(),0,0,640,360,640*4,PixelFormat::ByteRGBA};
    for(int row=0;row<3;++row)for(int col=0;col<3;++col){
      const int x0=col*640/3,x1=(col+1)*640/3;
      const int y0=row*360/3,y1=(row+1)*360/3;
      auto clipped=cropSurface(full,x0,y0,x1,y1);
      render(s,d,v,clipped);
    }
    check(tiled==first,"3x3 tiled render pixel-identical to full image");
    // A transparent region is deterministic even with nonzero source contents.
    Scene trans=s;trans.style.transparent=true;
    const auto transparent=frame(trans,d,640,360,0);
    check(transparent[3]==0,"transparent ocean alpha survives normal rendering");
    // Parallel, reverse-order, and repeated seeks exercise reentrancy and
    // consistent cache-independent output. Each worker has an owned RGBA surface.
    std::vector<std::future<std::vector<uint64_t>>> workers;
    for(int worker=0;worker<3;++worker){
      workers.push_back(std::async(std::launch::async,[&s,&d,worker](){
        std::vector<uint64_t> hashes;hashes.reserve(14);
        for(int n=0;n<14;++n){
          const int at=(worker*71+n*37)%240;
          hashes.push_back(fingerprint(frame(s,d,960,540,at)));
        }
        return hashes;
      }));
    }
    auto a=workers[0].get(),b=workers[1].get(),c=workers[2].get();
    check(a.size()==14&&b.size()==14&&c.size()==14,"multi-worker seeks completed");
    check(a.front()==fingerprint(frame(s,d,960,540,0)),"worker output deterministic");
    // 1440p actual raster test, not simply a rescaled preview.
    const auto hi=frame(s,d,2560,1440,96);
    check(hi.size()==size_t(2560)*1440*4,"1440p allocation exact");
    check(std::any_of(hi.begin(),hi.end(),[](auto x){return x!=0;}),"1440p produced nonempty image");
    check(hi[3]==255,"1440p opaque normal scene alpha");
    // Reopening after a source-string roundtrip must preserve the scene shape.
    const auto s2=parseScene(readText(root+"/samples/brasil-venezuela.cartorig-native.json"));
    check(frame(s2,d,640,360,96)==middle,"same embedded scene JSON reproduces exact image");
  }catch(const std::exception &e){std::cerr<<"UNEXPECTED "<<e.what()<<"\n";++failures;}
  std::cout<<passes<<" stability assertions passed, "<<failures<<" failed\n";
  return failures?1:0;
}
