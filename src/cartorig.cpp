#include "cartorig.hpp"
#include "json11.hpp"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iterator>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace cartorig {
namespace {
constexpr double pi=3.14159265358979323846;
using J=json11::Json;
void require(bool ok,const char *message){if(!ok)throw std::invalid_argument(message);}
void finite(double n){require(std::isfinite(n),"nonfinite coordinate/value");}
double num(const J &v,double fallback){return v.is_number()?v.number_value():fallback;}
std::string str(const J &v,const std::string &fallback=""){return v.is_string()?v.string_value():fallback;}
Color hex(const J &value,Color fallback){if(!value.is_string())return fallback;std::string s=value.string_value();require(s.size()==7||s.size()==9,"color must be #RRGGBB[AA]");require(s[0]=='#',"color hex prefix");auto digit=[](char c)->int{if(c>='0'&&c<='9')return c-'0';if(c>='A'&&c<='F')return c-'A'+10;if(c>='a'&&c<='f')return c-'a'+10;throw std::invalid_argument("color hex digit");};auto byte=[&](int i){return static_cast<uint8_t>((digit(s[i])<<4)|digit(s[i+1]));};return {byte(1),byte(3),byte(5),s.size()==9?byte(7):static_cast<uint8_t>(255)};}
GeoPoint point(const J &a){require(a.is_array()&&a.array_items().size()>=2,"expected [longitude,latitude]");GeoPoint p{a[size_t(0)].number_value(),a[size_t(1)].number_value()};require(a[size_t(0)].is_number()&&a[size_t(1)].is_number(),"coordinate numbers");finite(p.lon);finite(p.lat);require(std::abs(p.lat)<=90 && std::abs(p.lon)<=540,"coordinate out of bounds");return p;}
GeoPoint objectPoint(const J &o){require(o.is_object(),"marker point object");GeoPoint p{num(o["lon"],0),num(o["lat"],0)};finite(p.lon);finite(p.lat);require(std::abs(p.lat)<=90 && std::abs(p.lon)<=540,"marker coordinates out of bounds");return p;}
Camera camera(const J &o,Camera fallback){if(o.is_object()){fallback.lon=num(o["lon"],fallback.lon);fallback.lat=num(o["lat"],fallback.lat);fallback.zoom=num(o["zoom"],fallback.zoom);fallback.bearing=num(o["bearing"],fallback.bearing);}finite(fallback.lon);finite(fallback.lat);finite(fallback.zoom);finite(fallback.bearing);require(std::abs(fallback.lat)<=85.051129 && fallback.zoom>=0 && fallback.zoom<=18,"camera bounds");return fallback;}
J parse(const std::string &text){std::string error;J obj=J::parse(text,error);require(error.empty(),"invalid JSON");return obj;}
void geometry(const J &g,Feature &out,size_t &points){std::string typ=str(g["type"]);const auto &cs=g["coordinates"];
 if(typ!="Polygon"&&typ!="MultiPolygon")return;
 require(cs.is_array(),"invalid polygon coordinates");
 std::vector<J> polygons=typ=="Polygon"?std::vector<J>{cs}:cs.array_items();
 for(const auto &poly:polygons){require(poly.is_array(),"polygon must be array");Polygon p;
 for(const auto &ring:poly.array_items()){require(ring.is_array(),"ring must be array");std::vector<GeoPoint> vv;
 for(const auto &coord:ring.array_items()){vv.push_back(point(coord));require(++points<=400000,"dataset too many vertices");}
 if(vv.size()>=3){if(vv.front().lon!=vv.back().lon||vv.front().lat!=vv.back().lat)vv.push_back(vv.front());p.rings.push_back(std::move(vv));}
 } if(!p.rings.empty())out.polygons.push_back(std::move(p));
 }
}
double mercatorY(double lat){lat=std::clamp(lat,-85.0511287798066,85.0511287798066);double s=std::sin(lat*pi/180.0);return 0.5-std::log((1+s)/(1-s))/(4*pi);}
double inverseY(double y){return std::atan(std::sinh(pi*(1-2*y)))*180/pi;}
double smooth(double x){return x*x*(3-2*x);}
double lerp(double a,double b,double t){return a+(b-a)*t;}
}
std::string readText(const std::string &path,size_t limit){std::ifstream f(path,std::ios::binary|std::ios::ate);if(!f)throw std::runtime_error("cannot open asset: "+path);auto n=f.tellg();if(n<0||static_cast<uint64_t>(n)>limit)throw std::runtime_error("asset exceeds size limit");f.seekg(0);std::string s(static_cast<size_t>(n),'\0');f.read(&s[0],n);if(!f)throw std::runtime_error("asset read error");return s;}
Dataset parseGeoJSON(const std::string &json){require(json.size()<=16*1024*1024,"dataset too large");J root=parse(json);require(str(root["type"])=="FeatureCollection","expected GeoJSON FeatureCollection");require(root["features"].is_array(),"features missing");Dataset d;size_t points=0;require(root["features"].array_items().size()<=10000,"too many features");for(const auto &f:root["features"].array_items()){
 auto properties=f["properties"];Feature feat;feat.id=str(properties["iso3"],str(properties["ISO_A3"],str(f["id"])));feat.name=str(properties["name"],feat.id);
 if(feat.id.empty()||feat.id.size()>120)continue;geometry(f["geometry"],feat,points);if(feat.polygons.empty())continue;
 if(d.byId.find(feat.id)!=d.byId.end())throw std::invalid_argument("duplicate geographic feature id");d.byId[feat.id]=d.features.size();d.features.push_back(std::move(feat));
 }return d;}
Scene parseScene(const std::string &json){require(json.size()<=2*1024*1024,"scene exceeds 2 MiB");J root=parse(json);require(root.is_object(),"scene must be object");Scene s;s.schemaVersion=static_cast<int>(num(root["schemaVersion"],1));require(s.schemaVersion==1,"unsupported scene schema version");s.title=str(root["title"],s.title);require(s.title.size()<=120,"scene title too long");s.fps=static_cast<int>(num(root["fps"],s.fps));s.frames=static_cast<int>(num(root["frames"],s.frames));require(s.fps>=1&&s.fps<=120&&s.frames>=1&&s.frames<=86400,"invalid timeline");s.camera=camera(root["camera"],s.camera);
 const J &colors=root["style"];if(colors.is_object()){s.style.ocean=hex(colors["ocean"],s.style.ocean);s.style.land=hex(colors["land"],s.style.land);s.style.border=hex(colors["border"],s.style.border);s.style.highlight=hex(colors["highlight"],s.style.highlight);s.style.transparent=colors["transparent"].bool_value();}
 if(root["highlights"].is_array())for(auto &h:root["highlights"].array_items()){require(h.is_string(),"highlight id string");require(h.string_value().size()<=120,"highlight id too long");s.highlighted.push_back(h.string_value());require(s.highlighted.size()<=2000,"too many highlights");}
 if(root["markers"].is_array())for(auto &o:root["markers"].array_items()){Marker m;m.id=str(o["id"]);m.label=str(o["label"]);require(!m.id.empty()&&m.id.size()<=120&&m.label.size()<=250,"invalid marker label/id");m.at=objectPoint(o);m.color=hex(o["color"],m.color);m.size=num(o["size"],m.size);finite(m.size);require(m.size>=1&&m.size<=100,"invalid marker size");s.markers.push_back(m);require(s.markers.size()<=2000,"too many markers");}
 if(root["routes"].is_array())for(auto &o:root["routes"].array_items()){Route r;r.id=str(o["id"]);r.from=str(o["from"]);r.to=str(o["to"]);require(!r.id.empty()&&!r.from.empty()&&!r.to.empty(),"invalid route identifiers");r.color=hex(o["color"],r.color);r.width=num(o["width"],r.width);r.curve=num(o["curve"],r.curve);r.start=static_cast<int>(num(o["start"],0));r.end=static_cast<int>(num(o["end"],s.frames-1));finite(r.curve);finite(r.width);require(r.width>=1&&r.width<=100&&std::abs(r.curve)<=100&&r.start>=0&&r.end>=r.start&&r.end<s.frames,"invalid route parameters");s.routes.push_back(r);require(s.routes.size()<=2000,"too many routes");}
 if(root["cameraKeys"].is_array())for(auto &o:root["cameraKeys"].array_items()){CameraKey k;k.frame=static_cast<int>(num(o["frame"],-1));k.camera=camera(o,s.camera);k.easing=str(o["easing"],k.easing);require(k.frame>=0&&k.frame<s.frames,"invalid camera key frame");require(k.easing=="smoothstep"||k.easing=="hold"||k.easing=="linear","unsupported easing");s.cameraKeys.push_back(k);require(s.cameraKeys.size()<=10000,"too many camera keys");}std::sort(s.cameraKeys.begin(),s.cameraKeys.end(),[](auto &a,auto &b){return a.frame<b.frame;});for(size_t i=1;i<s.cameraKeys.size();++i)require(s.cameraKeys[i-1].frame!=s.cameraKeys[i].frame,"duplicate camera keyframes");
 for(const auto &r:s.routes){bool from=false,to=false;for(const auto &m:s.markers){from|=m.id==r.from;to|=m.id==r.to;}require(from&&to&&r.from!=r.to,"route references missing marker");}
 return s;}
double normalizeLon(double lon){finite(lon);double n=std::fmod(lon+180,360);if(n<0)n+=360;return n-180;}
ScreenPoint project(GeoPoint p,const Camera &cam,int w,int h){require(w>0&&h>0,"invalid viewport");const double world=256*std::pow(2,cam.zoom)*(w/1280.0);double dx=(normalizeLon(p.lon)-normalizeLon(cam.lon))/360;while(dx>0.5)dx-=1;while(dx<-.5)dx+=1;double dy=mercatorY(p.lat)-mercatorY(cam.lat);double xx=dx*world,yy=dy*world,ang=cam.bearing*pi/180;return {w/2.0+std::cos(ang)*xx-std::sin(ang)*yy,h/2.0+std::sin(ang)*xx+std::cos(ang)*yy};}

std::vector<std::vector<ScreenPoint>> projectPolygonContinuous(
    const Polygon &polygon,const Camera &cam,int width,int height){
  if(width<=0||height<=0)throw std::invalid_argument("invalid projection viewport");
  const double world=256.0*std::pow(2.0,cam.zoom)*(width/1280.0);
  const double angle=cam.bearing*pi/180.0;
  const double cosA=std::cos(angle),sinA=std::sin(angle);
  const double cameraLon=normalizeLon(cam.lon);
  const double cameraY=mercatorY(cam.lat);
  std::vector<std::vector<ScreenPoint>> result;
  result.reserve(polygon.rings.size());
  double outerMeanLon=cameraLon;
  for(size_t ringIndex=0;ringIndex<polygon.rings.size();++ringIndex){
    const auto &ring=polygon.rings[ringIndex];
    if(ring.empty()){result.emplace_back();continue;}
    std::vector<double> unwrapped;unwrapped.reserve(ring.size());
    double longitude=cameraLon+normalizeLon(ring[0].lon-cameraLon);
    unwrapped.push_back(longitude);
    for(size_t j=1;j<ring.size();++j){
      // Edges follow their shortest geographic longitude displacement.
      // This preserves topology at the camera-opposite world seam.
      longitude+=normalizeLon(ring[j].lon-ring[j-1].lon);
      unwrapped.push_back(longitude);
    }
    double sum=0;size_t count=unwrapped.size();
    // Ignore duplicated closing point when choosing a world repeat.
    if(count>1&&ring.front().lon==ring.back().lon&&ring.front().lat==ring.back().lat)
      --count;
    for(size_t j=0;j<count;++j)sum+=unwrapped[j];
    const double mean=sum/std::max(size_t(1),count);
    const double reference=ringIndex==0?cameraLon:outerMeanLon;
    const double offset=360.0*std::round((reference-mean)/360.0);
    if(ringIndex==0)outerMeanLon=mean+offset;
    std::vector<ScreenPoint> points;points.reserve(ring.size());
    for(size_t j=0;j<ring.size();++j){
      const double xx=(unwrapped[j]+offset-cameraLon)/360.0*world;
      const double yy=(mercatorY(ring[j].lat)-cameraY)*world;
      points.push_back({width*.5+cosA*xx-sinA*yy,height*.5+sinA*xx+cosA*yy});
    }
    result.push_back(std::move(points));
  }
  return result;
}
GeoPoint unproject(ScreenPoint s,const Camera &cam,int w,int h){require(w>0&&h>0,"invalid viewport");const double world=256*std::pow(2,cam.zoom)*(w/1280.0),ang=cam.bearing*pi/180,dx=s.x-w/2.0,dy=s.y-h/2.0;double xx=std::cos(ang)*dx+std::sin(ang)*dy,yy=-std::sin(ang)*dx+std::cos(ang)*dy;return {normalizeLon(cam.lon+xx/world*360),inverseY(mercatorY(cam.lat)+yy/world)};}
Camera evaluateCamera(const Scene &s,double frame){if(s.cameraKeys.empty())return s.camera;const auto &keys=s.cameraKeys;if(frame<=keys.front().frame)return keys.front().camera;if(frame>=keys.back().frame)return keys.back().camera;auto after=std::upper_bound(keys.begin(),keys.end(),frame,[](double f,const CameraKey &k){return f<k.frame;});const CameraKey &a=*(after-1),&b=*after;double t=(frame-a.frame)/(b.frame-a.frame);if(a.easing=="hold")t=0;else if(a.easing=="smoothstep")t=smooth(t);const double delta=normalizeLon(b.camera.lon-a.camera.lon);double bearing=std::fmod(b.camera.bearing-a.camera.bearing+540,360)-180;Camera c;c.lon=normalizeLon(a.camera.lon+delta*t);c.lat=inverseY(lerp(mercatorY(a.camera.lat),mercatorY(b.camera.lat),t));c.zoom=lerp(a.camera.zoom,b.camera.zoom,t);c.bearing=a.camera.bearing+bearing*t;return c;}
double mapSceneFrame(double hostTime,double offset,double speed){
  if(!std::isfinite(hostTime)||!std::isfinite(offset)||!std::isfinite(speed))
    throw std::invalid_argument("non-finite scene time");
  if(std::abs(speed)>8||std::abs(offset)>86400)
    throw std::invalid_argument("invalid scene time mapping");
  const double value=(hostTime-offset)*speed;
  if(!std::isfinite(value)||std::abs(value)>1.e9)
    throw std::invalid_argument("scene time outside safe range");
  return value;
}
double routeFraction(const Route &r,double frame){if(frame<r.start)return 0;if(r.end<=r.start)return 1;return std::clamp((frame-r.start)/(r.end-r.start),0.0,1.0);}
Camera fitBounds(const std::vector<GeoPoint>&points,int w,int h,double padding){require(!points.empty()&&w>0&&h>0&&padding>=0&&padding<.45,"invalid fitBounds arguments");double west=std::numeric_limits<double>::infinity(),east=-west,north=-west,south=west;for(auto p:points){finite(p.lon);finite(p.lat);west=std::min(west,p.lon);east=std::max(east,p.lon);north=std::max(north,mercatorY(p.lat));south=std::min(south,mercatorY(p.lat));}Camera c;c.lon=normalizeLon((east+west)/2);c.lat=inverseY((north+south)/2);c.bearing=0;double usableW=w*(1-2*padding),usableH=h*(1-2*padding);double factor=std::max((east-west)/360/usableW,(north-south)/usableH);c.zoom=factor>0?std::clamp(std::log2(1/(factor*256*(w/1280.0))),0.0,16.0):16;return c;}
}
