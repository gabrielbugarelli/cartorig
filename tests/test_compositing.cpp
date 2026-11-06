#include "cartorig.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>
using namespace cartorig;
static int ok=0,failures=0;
static void check(bool yes,const char *name){
  if(yes)++ok;else{++failures;std::cerr<<"FAILED "<<name<<"\n";}
}
static float eq(float a,float b){return std::abs(a-b);}
static float component(const std::vector<float>&v,int pixel,int channel){return v[pixel*4+channel];}
int main(){
  const Color red50{255,0,0,128},blue{0,0,255,255};
  std::vector<float> straight(4,0);
  Surface s{straight.data(),0,0,1,1,16,PixelFormat::FloatRGBA,false};
  compositeColor(s,0,0,red50);
  check(eq(straight[0],1)<1e-6f&&eq(straight[3],128.f/255)<1e-6f,
        "straight alpha stores full red in transparent buffer");
  std::vector<float> premul(4,0);
  Surface p{premul.data(),0,0,1,1,16,PixelFormat::FloatRGBA,true};
  compositeColor(p,0,0,red50);
  check(eq(premul[0],128.f/255)<1e-6f&&eq(premul[3],128.f/255)<1e-6f,
        "premultiplied transparent buffer stores alpha-scaled RGB");
  compositeColor(s,0,0,blue);
  compositeColor(p,0,0,blue);
  check(eq(straight[2],1)<1e-6f&&eq(premul[2],1)<1e-6f&&
        eq(straight[3],1)<1e-6f&&eq(premul[3],1)<1e-6f,
        "opaque draw overwrites both alpha modes");
  // Red over opaque blue should produce same visible RGB in either mode.
  compositeColor(s,0,0,red50);
  compositeColor(p,0,0,red50);
  check(eq(straight[0],128.f/255)<1e-6f&&
        eq(premul[0],128.f/255)<1e-6f&&
        eq(straight[2],127.f/255)<1e-6f&&
        eq(premul[2],127.f/255)<1e-6f,
        "source over opaque video is consistent in both associations");
  // Alpha of overlay is globally controllable; no opaque land at opacity=0.
  auto before=premul;
  compositeColor(p,0,0,{255,255,255,255},0);
  check(premul==before,"zero global opacity leaves footage untouched");
  std::vector<uint8_t> bytes(4,0);
  Surface b{bytes.data(),0,0,1,1,4,PixelFormat::ByteRGBA,true};
  compositeColor(b,0,0,red50);
  check(bytes[0]==128&&bytes[1]==0&&bytes[2]==0&&bytes[3]==128,
        "RGBA8 premultiplied alpha");
  // Test float32 source -> float32 premult destination, including alpha0.
  std::vector<float> source{1,0,0,.5f, 1,1,1,0};
  std::vector<float> target(8,std::numeric_limits<float>::quiet_NaN());
  Surface src{source.data(),0,0,2,1,32,PixelFormat::FloatRGBA,false};
  Surface dst{target.data(),0,0,2,1,32,PixelFormat::FloatRGBA,true};
  copySurface(src,dst);
  check(eq(component(target,0,0),.5f)<1e-6f&&
        eq(component(target,0,3),.5f)<1e-6f&&
        target[4]==0&&target[5]==0&&target[6]==0&&target[7]==0,
        "source association converted to premult and zero-alpha RGB cleared");
  // Round trip to straight alpha without double-multiplying.
  std::vector<float> back(8,0);
  Surface backSurface{back.data(),0,0,2,1,32,PixelFormat::FloatRGBA,false};
  copySurface(dst,backSurface);
  check(eq(back[0],1.f)<1e-6f&&eq(back[3],.5f)<1e-6f,
        "premult-to-straight alpha conversion is reversible for alpha>0");
  // Conversion across pixel depths.
  std::vector<float> floatInput{.5f,.25f,1.f,1.f};
  std::vector<uint8_t> byteOutput(4,0);
  Surface fin{floatInput.data(),0,0,1,1,16,PixelFormat::FloatRGBA,true};
  Surface bout{byteOutput.data(),0,0,1,1,4,PixelFormat::ByteRGBA,true};
  copySurface(fin,bout);
  check(byteOutput[0]==128&&byteOutput[1]==64&&byteOutput[2]==255&&byteOutput[3]==255,
        "Float32 source converts to RGBA8");
  // Image regions must not leak outside the requested output tile.
  std::vector<uint8_t> srcPixels(4*3*4,22),dstPixels(4*3*4,0xCA);
  Surface fullSrc{srcPixels.data(),0,0,4,3,16,PixelFormat::ByteRGBA,true};
  Surface fullDst{dstPixels.data(),0,0,4,3,16,PixelFormat::ByteRGBA,true};
  Surface cropped=cropSurface(fullDst,1,1,3,2);
  copySurface(fullSrc,cropped);
  bool isolated=true;
  for(int y=0;y<3;++y)for(int x=0;x<4;++x)
    for(int channel=0;channel<4;++channel){
      auto v=dstPixels[(y*4+x)*4+channel];
      isolated&=(y==1&&x>=1&&x<3)?(v==22):(v==0xCA);
    }
  check(isolated,"copy preserves memory outside RenderWindow");
  // In-place OFX source/output buffers must never be cleared.
  auto srcBefore=srcPixels;
  copySurface(fullSrc,fullSrc);
  check(srcPixels==srcBefore,"in-place identity copy preserves footage");
  // Test negative rowBytes and true source alpha.
  std::vector<uint8_t> neg(4*2*4);
  Surface upsideDown{neg.data()+4*4,0,0,4,2,-4*4,PixelFormat::ByteRGBA,false};
  compositeColor(upsideDown,1,0,blue);
  check(neg[4*4+4+2]==255&&neg[4*4+4+3]==255,
        "negative stride is honored during composition");
  // Opaque source must erase NaN from destination when overdrawing.
  std::vector<float> dirty(4,std::numeric_limits<float>::quiet_NaN());
  Surface dirtyDst{dirty.data(),0,0,1,1,16,PixelFormat::FloatRGBA,true};
  compositeColor(dirtyDst,0,0,blue);
  check(dirty[0]==0&&dirty[1]==0&&dirty[2]==1&&dirty[3]==1,
        "opaque pixel overwrites uninitialized host float memory");
  std::cout<<ok<<" compositing checks passed, "<<failures<<" failed\n";
  return failures?1:0;
}
