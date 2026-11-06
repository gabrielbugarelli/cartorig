#include "cartorig.hpp"
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>

namespace cartorig {
namespace {
int pixelBytes(PixelFormat f){return f==PixelFormat::ByteRGBA?4:16;}
float finiteValue(float value){return std::isfinite(value)?value:0.0f;}
struct Pixel {float r=0,g=0,b=0,a=0;};
const char* pixelAddress(Surface s,int x,int y) {
  return static_cast<const char*>(s.data)+static_cast<ptrdiff_t>(y-s.y1)*s.rowBytes+
         static_cast<ptrdiff_t>(x-s.x1)*pixelBytes(s.format);
}
char* pixelAddressMutable(Surface s,int x,int y) {
  return static_cast<char*>(s.data)+static_cast<ptrdiff_t>(y-s.y1)*s.rowBytes+
         static_cast<ptrdiff_t>(x-s.x1)*pixelBytes(s.format);
}
Pixel read(Surface s,int x,int y){
  Pixel p;
  const auto *base=pixelAddress(s,x,y);
  float v[4];
  if(s.format==PixelFormat::ByteRGBA){
    const auto *q=reinterpret_cast<const uint8_t*>(base);
    for(int i=0;i<4;i++)v[i]=q[i]/255.0f;
  }else{
    // memcpy avoids UB for host-supplied float image pointers that are
    // valid but not necessarily aligned to alignof(float).
    std::memcpy(v,base,sizeof v);
    for(auto &c:v)c=finiteValue(c);
  }
  p.r=v[0];p.g=v[1];p.b=v[2];p.a=std::clamp(v[3],0.f,1.f);
  return p;
}
void write(Surface s,int x,int y,Pixel p){
  char *base=pixelAddressMutable(s,x,y);
  float v[]{p.r,p.g,p.b,std::clamp(p.a,0.f,1.f)};
  if(s.format==PixelFormat::ByteRGBA){
    auto *q=reinterpret_cast<uint8_t*>(base);
    for(int i=0;i<4;++i)q[i]=static_cast<uint8_t>(
      std::lround(std::clamp(finiteValue(v[i]),0.f,1.f)*255.f));
  }else{
    for(auto &c:v)c=finiteValue(c);
    std::memcpy(base,v,sizeof v);
  }
}
bool valid(Surface s){
  return s.data&&s.x1<s.x2&&s.y1<s.y2&&s.rowBytes!=0&&
    (s.rowBytes<0?-int64_t(s.rowBytes):int64_t(s.rowBytes))>=
    int64_t(s.x2-s.x1)*pixelBytes(s.format);
}
void clear(Surface s){
  for(int y=s.y1;y<s.y2;++y)
    std::memset(pixelAddressMutable(s,s.x1,y),0,
                size_t(s.x2-s.x1)*pixelBytes(s.format));
}
} // namespace
void compositeColor(Surface dst,int x,int y,Color color,double opacity){
  if(!valid(dst))throw std::invalid_argument("invalid RGBA surface");
  if(x<dst.x1||x>=dst.x2||y<dst.y1||y>=dst.y2)return;
  if(!std::isfinite(opacity))throw std::invalid_argument("invalid opacity");
  const float a=std::clamp(static_cast<float>(color.a/255.0*
      std::clamp(opacity,0.0,1.0)),0.f,1.f);
  if(a<=0)return;
  const float src[3]{color.r/255.f,color.g/255.f,color.b/255.f};
  if(a==1) {
    write(dst,x,y,{src[0],src[1],src[2],1.f});
    return;
  }
  Pixel old=read(dst,x,y);
  // All calculations are in premultiplied space, which avoids accidentally
  // multiplying an already-premultiplied source alpha twice.
  const float da=old.a,sa=a,oa=sa+da*(1-sa);
  Pixel out;out.a=oa;
  const float prev[3]{old.r,old.g,old.b};
  float *channels[3]{&out.r,&out.g,&out.b};
  for(int i=0;i<3;++i) {
    const float premul=src[i]*sa+(dst.premultiplied?prev[i]:prev[i]*da)*(1-sa);
    *channels[i]=dst.premultiplied?premul:(oa>0?premul/oa:0);
  }
  write(dst,x,y,out);
}
void copySurface(Surface source,Surface destination){
  if(!valid(source)||!valid(destination))
    throw std::invalid_argument("invalid source or destination surface");
  // A filter must produce a defined pixel for every output pixel even if
  // its input has a smaller region of definition than the requested window.
  clear(destination);
  const int x0=std::max(source.x1,destination.x1);
  const int y0=std::max(source.y1,destination.y1);
  const int x1=std::min(source.x2,destination.x2);
  const int y1=std::min(source.y2,destination.y2);
  if(x0>=x1||y0>=y1)return;
  const int size=pixelBytes(source.format);
  if(source.format==destination.format &&
     source.premultiplied==destination.premultiplied){
    for(int y=y0;y<y1;++y)
      std::memcpy(pixelAddressMutable(destination,x0,y),
        pixelAddress(source,x0,y),size_t(x1-x0)*size);
    return;
  }
  for(int y=y0;y<y1;++y)for(int x=x0;x<x1;++x){
    Pixel c=read(source,x,y);
    if(source.premultiplied&&!destination.premultiplied){
      if(c.a>1.e-8f){c.r/=c.a;c.g/=c.a;c.b/=c.a;}
      else{c.r=c.g=c.b=0;}
    }else if(!source.premultiplied&&destination.premultiplied){
      c.r*=c.a;c.g*=c.a;c.b*=c.a;
    }
    write(destination,x,y,c);
  }
}
} // namespace cartorig
