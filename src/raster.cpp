#include "cartorig.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <map>
#include <stdexcept>
#include <vector>

namespace cartorig {
namespace {
struct Painter {
  Surface s; int width,height; RasterStats *stats;
  void put(int x,int y,Color color){
    const int ofxY=height-1-y;
    if(x<s.x1||x>=s.x2||ofxY<s.y1||ofxY>=s.y2||!s.data)return;
    const int bytes=s.format==PixelFormat::ByteRGBA?4:16;
    char *p=static_cast<char *>(s.data)+static_cast<ptrdiff_t>(ofxY-s.y1)*s.rowBytes+static_cast<ptrdiff_t>(x-s.x1)*bytes;
    // Opaque pixels overwrite without ever reading the host's destination memory.
    // 1.0 + NaN * 0.0 is NaN: the previous blending path propagated undefined
    // or uninitialized float output buffers into the entire map.
    const double a=color.a/255.0;if(a<=0)return;
    if(s.format==PixelFormat::ByteRGBA){
      auto *q=reinterpret_cast<uint8_t *>(p);
      if(color.a==255){q[0]=color.r;q[1]=color.g;q[2]=color.b;q[3]=255;}
      else {
        const double oldA=q[3]/255.0,outA=a+oldA*(1-a);
        const uint8_t rgb[3]{color.r,color.g,color.b};
        for(int i=0;i<3;i++)
          q[i]=static_cast<uint8_t>(std::clamp((rgb[i]*a+(oldA>0?q[i]*oldA*(1-a):0.0))/std::max(outA,1e-8),0.0,255.0)+0.5);
        q[3]=static_cast<uint8_t>(outA*255+.5);
      }
    }else{
      auto *q=reinterpret_cast<float *>(p);
      if(color.a==255){q[0]=color.r/255.0f;q[1]=color.g/255.0f;q[2]=color.b/255.0f;q[3]=1.0f;}
      else {
        double oldA=q[3];
        if(!std::isfinite(oldA)||oldA<0.0||oldA>1.0)oldA=0.0;
        const double outA=a+oldA*(1-a);
        const uint8_t rgb[3]{color.r,color.g,color.b};
        for(int i=0;i<3;i++){
          const double old=oldA>0&&std::isfinite(q[i])?std::clamp(static_cast<double>(q[i]),0.0,1.0):0.0;
          q[i]=static_cast<float>(std::clamp((rgb[i]/255.0*a+old*oldA*(1-a))/std::max(outA,1e-8),0.0,1.0));
        }
        q[3]=static_cast<float>(outA);
      }
    }
    if(stats)stats->written++;
  }
  void fill(Color color){if(color.a==0){for(int y=s.y1;y<s.y2;++y)std::memset(static_cast<char*>(s.data)+static_cast<ptrdiff_t>(y-s.y1)*s.rowBytes,0,static_cast<size_t>(s.x2-s.x1)*(s.format==PixelFormat::ByteRGBA?4:16));return;}for(int y=std::max(0,height-s.y2);y<std::min(height,height-s.y1);++y)for(int x=s.x1;x<s.x2;++x)put(x,y,color);}
  void disk(double cx,double cy,double radius,Color c){if(radius<=0)return;int x0=std::max(s.x1,static_cast<int>(std::floor(cx-radius-1))),x1=std::min(s.x2,static_cast<int>(std::ceil(cx+radius+1)));int y0=std::max(height-s.y2,static_cast<int>(std::floor(cy-radius-1))),y1=std::min(height-s.y1,static_cast<int>(std::ceil(cy+radius+1)));double rr=radius*radius;for(int y=y0;y<y1;++y)for(int x=x0;x<x1;++x)if((x+.5-cx)*(x+.5-cx)+(y+.5-cy)*(y+.5-cy)<=rr)put(x,y,c);}
  void line(ScreenPoint a,ScreenPoint b,double width,Color c){double dx=b.x-a.x,dy=b.y-a.y,n=std::hypot(dx,dy);if(n>width*10+20000)return;int steps=static_cast<int>(std::ceil(n*1.15));if(steps>50000)return;for(int i=0;i<=steps;++i){double t=steps?static_cast<double>(i)/steps:0;disk(a.x+dx*t,a.y+dy*t,width/2,c);}}
  void polygon(const std::vector<std::vector<ScreenPoint>>&rings,Color fillColor,Color strokeColor){
    if(rings.empty())return;double ymin=1e12,ymax=-1e12;for(const auto &ring:rings)for(auto p:ring){ymin=std::min(ymin,p.y);ymax=std::max(ymax,p.y);}
    const int yStart=std::max(height-s.y2,static_cast<int>(std::floor(ymin))),yStop=std::min(height-s.y1,static_cast<int>(std::ceil(ymax)));
    for(int y=yStart;y<yStop;++y){std::vector<double> xs;const double sy=y+.5;
      for(auto &ring:rings)if(ring.size()>2)for(size_t i=1;i<ring.size();++i){auto a=ring[i-1],b=ring[i];if((a.y<=sy&&b.y>sy)||(b.y<=sy&&a.y>sy)){double x=a.x+(sy-a.y)*(b.x-a.x)/(b.y-a.y);if(std::isfinite(x))xs.push_back(x);}}
      std::sort(xs.begin(),xs.end());for(size_t i=1;i<xs.size();i+=2){int from=std::max(s.x1,static_cast<int>(std::ceil(xs[i-1]-.5))),to=std::min(s.x2,static_cast<int>(std::ceil(xs[i]-.5)));for(int x=from;x<to;++x)put(x,y,fillColor);}
    }
    if(strokeColor.a){for(auto &ring:rings)for(size_t i=1;i<ring.size();++i)if(std::hypot(ring[i].x-ring[i-1].x,ring[i].y-ring[i-1].y)<width*2.5)line(ring[i-1],ring[i],std::clamp(width/1600.0,0.6,2.0),strokeColor);}
  }
};
constexpr std::array<std::array<uint8_t,7>,37> font={{{0,0,0,0,0,0,0}, // unsupported
{14,17,17,31,17,17,17},{30,17,17,30,17,17,30},{14,17,16,16,16,17,14},{30,17,17,17,17,17,30},{31,16,16,30,16,16,31},{31,16,16,30,16,16,16},
{14,17,16,23,17,17,15},{17,17,17,31,17,17,17},{14,4,4,4,4,4,14},{7,2,2,2,18,18,12},{17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
{17,27,21,21,17,17,17},{17,25,21,19,17,17,17},{14,17,17,17,17,17,14},{30,17,17,30,16,16,16},{14,17,17,17,21,18,13},
{30,17,17,30,20,18,17},{15,16,16,14,1,1,30},{31,4,4,4,4,4,4},{17,17,17,17,17,17,14},{17,17,17,17,17,10,4},{17,17,17,21,21,21,10},
{17,17,10,4,10,17,17},{17,17,10,4,4,4,4},{31,1,2,4,8,16,31},{14,17,19,21,25,17,14},{4,12,4,4,4,4,14},{14,17,1,2,4,8,31},
{30,1,1,14,1,1,30},{2,6,10,18,31,2,2},{31,16,16,30,1,1,30},{14,16,16,30,17,17,14},{31,1,2,4,8,8,8},{14,17,17,14,17,17,14},{14,17,17,15,1,1,14}}};
void label(Painter &p,ScreenPoint anchor,const std::string &s,Color c){int x=static_cast<int>(anchor.x)+9,y=static_cast<int>(anchor.y)-11;int charCount=0;for(unsigned char ch:s){if(++charCount>48)break;unsigned n=0;if(ch>='A'&&ch<='Z')n=1+(ch-'A');else if(ch>='a'&&ch<='z')n=1+(ch-'a');else if(ch>='0'&&ch<='9')n=27+(ch-'0');for(int r=0;r<7;++r)for(int bit=0;bit<5;++bit)if(font[n][r]&(1<<(4-bit)))p.put(x+bit,y+r,c);x+=6;}}
}
Surface cropSurface(Surface s,int x1,int y1,int x2,int y2){
  if(!s.data||s.x1>=s.x2||s.y1>=s.y2||s.rowBytes==0)throw std::invalid_argument("invalid source surface");
  const int nx1=std::max(s.x1,x1),ny1=std::max(s.y1,y1);
  const int nx2=std::min(s.x2,x2),ny2=std::min(s.y2,y2);
  if(nx1>=nx2||ny1>=ny2){s.data=nullptr;s.x1=s.x2=nx1;s.y1=s.y2=ny1;return s;}
  const int pixelBytes=s.format==PixelFormat::ByteRGBA?4:16;
  s.data=static_cast<char*>(s.data)+static_cast<ptrdiff_t>(ny1-s.y1)*s.rowBytes+static_cast<ptrdiff_t>(nx1-s.x1)*pixelBytes;
  s.x1=nx1;s.y1=ny1;s.x2=nx2;s.y2=ny2;
  return s;
}
void render(const Scene &scene,const Dataset &data,const View &view,Surface dst,RasterStats *stats){
 if(view.width<=0||view.height<=0||view.width>16384||view.height>16384||!dst.data||dst.x1>=dst.x2||dst.y1>=dst.y2||dst.rowBytes==0)throw std::invalid_argument("invalid image target");
 Painter p{dst,view.width,view.height,stats};if(!view.preserveBackground)p.fill(scene.style.transparent?Color{0,0,0,0}:scene.style.ocean);
 const auto drawFeature=[&](const Feature &f,Color fillColor,bool border){for(auto &poly:f.polygons){std::vector<std::vector<ScreenPoint>> rings;rings.reserve(poly.rings.size());for(auto &r:poly.rings){std::vector<ScreenPoint> projected;projected.reserve(r.size());for(const auto &pt:r)projected.push_back(project(pt,view.camera,view.width,view.height));rings.push_back(std::move(projected));}p.polygon(rings,fillColor,border?scene.style.border:Color{0,0,0,0});}};
 for(auto &f:data.features)drawFeature(f,scene.style.land,true);
 for(auto &id:scene.highlighted){auto it=data.byId.find(id);if(it!=data.byId.end())drawFeature(data.features[it->second],scene.style.highlight,false);}
 for(const auto &r:scene.routes){auto find=[&](const std::string &id)->const Marker*{for(auto &m:scene.markers)if(m.id==id)return &m;return nullptr;};auto from=find(r.from),to=find(r.to);if(!from||!to)continue;auto a=project(from->at,view.camera,view.width,view.height),b=project(to->at,view.camera,view.width,view.height);double dx=b.x-a.x,dy=b.y-a.y,curve=r.curve/100.0;ScreenPoint control{(a.x+b.x)/2-dy*curve,(a.y+b.y)/2+dx*curve};auto at=[&](double t){return ScreenPoint{(1-t)*(1-t)*a.x+2*t*(1-t)*control.x+t*t*b.x,(1-t)*(1-t)*a.y+2*t*(1-t)*control.y+t*t*b.y};};std::vector<ScreenPoint> points;std::vector<double> lengths;double total=0;for(int i=0;i<=96;++i){auto q=at(i/96.0);if(!points.empty())total+=std::hypot(q.x-points.back().x,q.y-points.back().y);points.push_back(q);lengths.push_back(total);}double f=view.routeProgress>=0?std::clamp(view.routeProgress,0.0,1.0):routeFraction(r,view.frame);double progress=total*f;ScreenPoint tip=a;for(size_t i=1;i<points.size();++i){if(lengths[i-1]>=progress)break;double t=std::clamp((progress-lengths[i-1])/std::max(lengths[i]-lengths[i-1],1e-9),0.0,1.0);ScreenPoint q{points[i-1].x+t*(points[i].x-points[i-1].x),points[i-1].y+t*(points[i].y-points[i-1].y)};p.line(points[i-1],q,r.width,r.color);tip=q;if(t<1)break;}
 if(f>0.005){double angle=std::atan2(tip.y-a.y,tip.x-a.x),head=std::max(7.0,r.width*3.0);p.line({tip.x-std::cos(angle-.5)*head,tip.y-std::sin(angle-.5)*head},tip,r.width,r.color);p.line({tip.x-std::cos(angle+.5)*head,tip.y-std::sin(angle+.5)*head},tip,r.width,r.color);}
 }
 for(auto &m:scene.markers){auto a=project(m.at,view.camera,view.width,view.height);p.disk(a.x,a.y,m.size+1,{0,0,0,230});p.disk(a.x,a.y,m.size,m.color);if(!m.label.empty())label(p,a,m.label,m.color);}
}
}
