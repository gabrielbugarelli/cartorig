#include "cartorig/geo.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <limits>
#include <numbers>
#include <sstream>
#include <stdexcept>

namespace cartorig::rc1 {
namespace {
constexpr double pi=std::numbers::pi_v<double>;
void require(bool yes,const char*msg){if(!yes)throw std::runtime_error(msg);}
template<typename T> T readNumber(std::istream& stream){
 T number{};
 stream.read(reinterpret_cast<char*>(&number),sizeof(number));
 require(stream.good(),"Truncated CRG1 numeric field");
 return number;
}
std::string readString(std::istream& stream,std::size_t n){
 require(n<=2048,"Oversized CRG1 identifier");
 std::string text(n,'\0');
 stream.read(text.data(),static_cast<std::streamsize>(n));
 require(stream.good(),"Truncated CRG1 identifier");
 return text;
}
std::vector<std::string> columns(const std::string&line){
 std::vector<std::string> out;std::size_t previous=0;
 while(true){
  auto pos=line.find('\t',previous);
  if(pos==std::string::npos){out.push_back(line.substr(previous));return out;}
  out.push_back(line.substr(previous,pos-previous));previous=pos+1;
 }
}
bool finite(double x){return std::isfinite(x);}
double clamp01(double x){return std::clamp(x,0.0,1.0);}
// Baseline projection CR-PS-2.0: equirectangular, not Web Mercator.
// We retain geographic longitude / latitude as stored, with camera bearing
// applied in screen space. Camera scaling must be common to every object.
double equiLatitude(double lat){return std::clamp(lat,-90.,90.);}
double deltaLon(double lon,double center){
 double d=std::remainder(lon-center,360.);
 if(d==-180.)d=180.;
 return d;
}
void validateGeo(GeoPoint p){
 if(!finite(p.lon)||!finite(p.lat)||std::abs(p.lon)>180.00001||std::abs(p.lat)>90.00001)
  throw std::invalid_argument("Invalid lon/lat");
}
std::vector<ScreenPoint> transformRing(const std::vector<GeoPoint>&points,
 std::size_t start,std::size_t end,const Camera&camera,int width,int height){
 std::vector<ScreenPoint> out;
 if(start>=end||end>points.size())return out;
 const double scale=width*camera.zoom/360.0;
 const double yScale=width*camera.zoom/360.0;
 const double angle=camera.bearing*pi/180.,c=std::cos(angle),s=std::sin(angle);
 const double baseline=equiLatitude(camera.center.lat);
 double previous=deltaLon(points[start].lon,camera.center.lon);
 for(std::size_t i=start;i<end;++i){
  double d=i==start?previous:previous+
    std::remainder(points[i].lon-points[i-1].lon,360.);
  previous=d;
  const double x=d*scale, y=-(equiLatitude(points[i].lat)-baseline)*yScale;
  out.push_back({width*.5+x*c-y*s,height*.5+x*s+y*c});
 }
 return out;
}
void paintLine(Surface&s,ScreenPoint a,ScreenPoint b,double thickness,Color color,
               double opacity){
 if(thickness<=0)return;
 const double r=std::max(.5,thickness*.5);
 const int x0=std::max(0,static_cast<int>(std::floor(std::min(a.x,b.x)-r-1)));
 const int y0=std::max(0,static_cast<int>(std::floor(std::min(a.y,b.y)-r-1)));
 const int x1=std::min(s.width-1,static_cast<int>(std::ceil(std::max(a.x,b.x)+r+1)));
 const int y1=std::min(s.height-1,static_cast<int>(std::ceil(std::max(a.y,b.y)+r+1)));
 const double dx=b.x-a.x,dy=b.y-a.y,den=dx*dx+dy*dy;
 for(int y=y0;y<=y1;++y)for(int x=x0;x<=x1;++x){
  const double t=den>1e-20?clamp01(((x+.5-a.x)*dx+(y+.5-a.y)*dy)/den):0;
  const double distance=std::hypot(x+.5-a.x-t*dx,y+.5-a.y-t*dy);
  const double cov=clamp01(r+.5-distance);
  if(cov>0)s.blend(x,y,color,opacity*cov);
 }
}
void drawDisk(Surface&s,ScreenPoint p,double radius,Color c,double opacity,bool ring=false,
              double strokeWidth=0){
 if(radius<=0)return;
 const int xmin=std::max(0,static_cast<int>(std::floor(p.x-radius-1)));
 const int xmax=std::min(s.width-1,static_cast<int>(std::ceil(p.x+radius+1)));
 const int ymin=std::max(0,static_cast<int>(std::floor(p.y-radius-1)));
 const int ymax=std::min(s.height-1,static_cast<int>(std::ceil(p.y+radius+1)));
 for(int y=ymin;y<=ymax;++y)for(int x=xmin;x<=xmax;++x){
  const double d=std::hypot(x+.5-p.x,y+.5-p.y);
  const double coverage=ring?
    clamp01(radius+.5-d)*clamp01(d-(radius-strokeWidth)+.5):
    clamp01(radius+.5-d);
  if(coverage>0)s.blend(x,y,c,coverage*opacity);
 }
}
void fillPolygons(Surface&canvas,const std::vector<std::vector<ScreenPoint>>&rings,
                  Color color,double opacity){
 int ymin=canvas.height,ymax=-1;
 for(const auto&ring:rings)for(const auto&p:ring)
  if(finite(p.x)&&finite(p.y)){
   ymin=std::min(ymin,static_cast<int>(std::floor(p.y)));
   ymax=std::max(ymax,static_cast<int>(std::ceil(p.y)));
  }
 ymin=std::max(0,ymin);ymax=std::min(canvas.height-1,ymax);
 std::vector<double> intersections;
 for(int y=ymin;y<=ymax;++y){
  intersections.clear();
  double at=y+.5;
  for(const auto&ring:rings){
   if(ring.size()<3)continue;
   for(std::size_t i=0;i<ring.size();++i){
    const auto&a=ring[i];const auto&b=ring[(i+1)%ring.size()];
    if((a.y<=at&&b.y>at)||(b.y<=at&&a.y>at))
     intersections.push_back(a.x+(at-a.y)*(b.x-a.x)/(b.y-a.y));
   }
  }
  std::sort(intersections.begin(),intersections.end());
  for(std::size_t i=1;i<intersections.size();i+=2){
   int left=std::max(0,static_cast<int>(std::ceil(intersections[i-1]-.5)));
   int right=std::min(canvas.width-1,static_cast<int>(std::floor(intersections[i]-.5)));
   for(int x=left;x<=right;++x)canvas.blend(x,y,color,opacity);
  }
 }
}
}
void Camera::validate() const{
 // Camera keys may use unwrapped longitudes (179 -> 181) to avoid a
 // 358-degree Fly To. Published geographic object anchors stay [-180,180].
 if(!finite(center.lon)||std::abs(center.lon)>540||
    !finite(center.lat)||std::abs(center.lat)>85||
    !finite(zoom)||zoom<.1||zoom>50||
    !finite(bearing)||bearing<-360||bearing>360)
  throw std::invalid_argument("Invalid camera parameters");
}
Surface::Surface(int w,int h):width(w),height(h){
 if(w<1||h<1||w>16384||h>16384||static_cast<uint64_t>(w)*h>100'000'000)
  throw std::invalid_argument("Unsafe render dimensions");
 rgba.resize(static_cast<std::size_t>(w)*h*4);
}
void Surface::clear(Color c){
 for(std::size_t i=0;i<rgba.size();i+=4){
  rgba[i]=c.r;rgba[i+1]=c.g;rgba[i+2]=c.b;rgba[i+3]=c.a;
 }
}
Color Surface::pixel(int x,int y) const{
 if(x<0||x>=width||y<0||y>=height)throw std::out_of_range("pixel");
 auto i=(static_cast<std::size_t>(y)*width+x)*4;
 return{rgba[i],rgba[i+1],rgba[i+2],rgba[i+3]};
}
void Surface::blend(int x,int y,Color color,double factor){
 if(x<0||x>=width||y<0||y>=height||factor<=0)return;
 auto k=(static_cast<std::size_t>(y)*width+x)*4;
 const double a=clamp01(factor)*(color.a/255.);
 const double da=rgba[k+3]/255.;
 const double oa=a+da*(1-a);
 if(oa<1e-10){rgba[k]=rgba[k+1]=rgba[k+2]=rgba[k+3]=0;return;}
 const std::array<double,3> src{static_cast<double>(color.r),color.g,color.b};
 for(int i=0;i<3;++i){
  double combined=(src[i]*a+rgba[k+i]*da*(1-a))/oa;
  rgba[k+i]=static_cast<uint8_t>(std::clamp(std::lround(combined),0l,255l));
 }
 rgba[k+3]=static_cast<uint8_t>(std::clamp(std::lround(oa*255),0l,255l));
}
double shortestLongitude(double from,double to){return std::remainder(to-from,360.);}
ScreenPoint project(GeoPoint p,const Camera&camera,int w,int h){
 camera.validate();validateGeo(p);
 if(w<1||h<1)throw std::invalid_argument("Invalid viewport");
 auto ring=transformRing({p},0,1,camera,w,h);
 return ring.at(0);
}
Camera fit(const Bounds& b,int width,int height,double pad){
 if(width<1||height<1||!finite(pad)||pad<0||pad>.35||
    !finite(b.west)||!finite(b.east)||!finite(b.south)||!finite(b.north)||
    b.south>b.north||std::abs(b.west)>180.||std::abs(b.east)>180.||
    std::abs(b.south)>90.||std::abs(b.north)>90.)
  throw std::invalid_argument("Invalid fit bounds");
 // A wrapped WGS84 envelope (west > east) spans the antimeridian,
 // e.g. [170,-10,-170,10] is 20 degrees wide, never 340 degrees.
 const double east=b.east<b.west?b.east+360.:b.east;
 const double longitudeSpan=east-b.west;
 Camera camera;
 camera.center={std::remainder((b.west+east)*.5,360.),
                (b.south+b.north)*.5};
 const double dx=std::max(.001,longitudeSpan/360.);
 const double dy=std::max(.001,(equiLatitude(b.north)-equiLatitude(b.south))/360.);
 const double use=1.-2.*pad;
 camera.zoom=std::clamp(std::min(use/dx,use*height/(width*dy)),.1,50.);
 camera.validate();return camera;
}
Catalog::Catalog(const std::filesystem::path& directory){
 archive_=directory/"geometry.crgeo";
 std::ifstream file(directory/"catalog.tsv");
 require(file.good(),"Natural Earth offline catalog unavailable");
 std::string line;require(static_cast<bool>(std::getline(file,line)),"Empty offline catalog");
 require(line.find("id\tkind\tname\t")==0,"Unrecognized catalog schema");
 while(std::getline(file,line)){
  if(line.empty())continue;
  auto c=columns(line);
  require(c.size()==11,"Malformed offline catalog record");
  Location r;
  r.id=c[0];r.kind=c[1];r.name=c[2];r.parent=c[3];r.aliases=c[4];
  r.bounds={std::stod(c[5]),std::stod(c[6]),std::stod(c[7]),std::stod(c[8])};
  r.offset=std::stoull(c[9]);r.length=std::stoull(c[10]);
  require(!r.id.empty()&&r.id.size()<=256&&r.length>=40&&
          r.length<=100'000'000,"Unsafe feature record");
  require(byId_.emplace(r.id,records_.size()).second,"Duplicate catalog ID");
  records_.push_back(std::move(r));
  require(records_.size()<=200'000,"Too many geographic features");
 }
 std::ifstream data(archive_,std::ios::binary|std::ios::ate);
 require(data.good(),"Natural Earth offline geometry unavailable");
 auto bytes=static_cast<uint64_t>(data.tellg());
 require(bytes>=8,"Truncated CRG1 geometry archive");
 data.seekg(0);
 char magic[4];data.read(magic,4);
 require(std::string(magic,4)=="CRG1","Unrecognized CRG1 geometry format");
 require(readNumber<uint32_t>(data)==records_.size(),"Catalog/geometry count mismatch");
 for(const auto&r:records_)
  require(r.offset>=8&&r.offset+r.length<=bytes,"Feature offset outside CRG1 data");
}
std::string normalizedQuery(const std::string& input){
 // Normalize UTF-8 Latin accents commonly found in Natural Earth names.
 // The publisher catalog itself has full Unicode search aliases generated
 // by Python NFKD; unknown scripts remain searchable by exact bytes.
 std::string out;
 for(std::size_t i=0;i<input.size();){
  const auto a=static_cast<unsigned char>(input[i]);
  if(a<128){out.push_back(static_cast<char>(std::tolower(a)));++i;continue;}
  if(i+1<input.size()&&a==0xC3){
   unsigned char b=static_cast<unsigned char>(input[i+1]);char mapped=0;
   switch(b){
    case 0x80:case 0x81:case 0x82:case 0x83:case 0x84:
    case 0xA0:case 0xA1:case 0xA2:case 0xA3:case 0xA4:mapped='a';break;
    case 0x87:case 0xA7:mapped='c';break;
    case 0x88:case 0x89:case 0x8A:case 0x8B:
    case 0xA8:case 0xA9:case 0xAA:case 0xAB:mapped='e';break;
    case 0x8C:case 0x8D:case 0x8E:case 0x8F:
    case 0xAC:case 0xAD:case 0xAE:case 0xAF:mapped='i';break;
    case 0x92:case 0x93:case 0x94:case 0x95:case 0x96:
    case 0xB2:case 0xB3:case 0xB4:case 0xB5:case 0xB6:mapped='o';break;
    case 0x99:case 0x9A:case 0x9B:case 0x9C:
    case 0xB9:case 0xBA:case 0xBB:case 0xBC:mapped='u';break;
    case 0x91:case 0xB1:mapped='n';break;
   }
   if(mapped){out.push_back(mapped);i+=2;continue;}
  }
  out.append(input.substr(i, a<0xE0?2:a<0xF0?3:4));
  i+=a<0xE0?2:a<0xF0?3:4;
 }
 auto left=out.find_first_not_of(" \t\r\n");
 if(left==std::string::npos)return "";
 auto right=out.find_last_not_of(" \t\r\n");
 return out.substr(left,right-left+1);
}
std::vector<Location> Catalog::search(const std::string& text,const std::string& kind,
                                      std::size_t limit) const{
 auto q=normalizedQuery(text);
 if(q.size()<2||q.size()>120||limit>100||limit==0)
  throw std::invalid_argument("Invalid search query");
 if(kind!="all"&&kind!="country"&&kind!="state"&&kind!="city"&&kind!="land")
  throw std::invalid_argument("Invalid region filter");
 struct Candidate{int rank;const Location* ref;};
 std::vector<Candidate> found;
 for(const auto&r:records_){
  if(kind!="all"&&r.kind!=kind)continue;
  if(kind=="all"&&r.kind=="land")continue;
  int rank=999;
  const auto name=normalizedQuery(r.name);
  if(name==q)rank=0;
  else if(name.rfind(q,0)==0)rank=1;
  else if(name.find(q)!=std::string::npos)rank=2;
  if(r.aliases.find(q)!=std::string::npos)rank=std::min(rank,3);
  if(rank<999)found.push_back({rank,&r});
 }
 std::sort(found.begin(),found.end(),[](const auto&a,const auto&b){
  if(a.rank!=b.rank)return a.rank<b.rank;
  if(a.ref->name!=b.ref->name)return a.ref->name<b.ref->name;
  return a.ref->id<b.ref->id;
 });
 std::vector<Location> results;
 for(auto&c:found){if(results.size()>=limit)break;results.push_back(*c.ref);}
 return results;
}
std::vector<Location> Catalog::all(const std::string& kind) const{
 if(kind!="country"&&kind!="state"&&kind!="city"&&kind!="land")
  throw std::invalid_argument("Invalid location kind");
 std::vector<Location> out;
 for(const auto&r:records_)if(r.kind==kind)out.push_back(r);
 return out;
}
Geometry Catalog::geometry(const std::string& id) const{
 auto it=byId_.find(id);
 if(it==byId_.end())throw std::invalid_argument("Unknown Natural Earth feature ID");
 const auto&r=records_[it->second];
 std::ifstream stream(archive_,std::ios::binary);
 require(stream.good(),"Missing CRG1 source");
 stream.seekg(static_cast<std::streamoff>(r.offset));
 uint16_t len=readNumber<uint16_t>(stream);
 Geometry g;g.id=readString(stream,len);
 require(g.id==r.id,"Geometry/catalog feature identity mismatch");
 auto kind=readNumber<uint8_t>(stream);
 (void)readNumber<uint32_t>(stream);
 g.shape=readNumber<uint8_t>(stream);
 g.bounds={readNumber<double>(stream),readNumber<double>(stream),
           readNumber<double>(stream),readNumber<double>(stream)};
 auto parts=readNumber<uint32_t>(stream),points=readNumber<uint32_t>(stream);
 require(parts<=200'000&&points<=4'000'000&&parts<=points,
         "Unsafe polygon ring dimensions");
 g.parts.resize(parts);
 for(auto&part:g.parts)part=readNumber<uint32_t>(stream);
 g.points.resize(points);
 for(auto&point:g.points){
  point.lon=readNumber<double>(stream);point.lat=readNumber<double>(stream);
  validateGeo(point);
 }
 require(!g.parts.empty()&&g.parts.front()==0,"Malformed geometry parts");
 for(std::size_t i=1;i<g.parts.size();++i)
  require(g.parts[i]>g.parts[i-1]&&g.parts[i]<points,
          "Malformed geometry ring order");
 const auto consumed=static_cast<uint64_t>(stream.tellg())-r.offset;
 require(consumed==r.length,"CRG1 record size mismatch");
 g.kind=(kind==0?"country":kind==1?"state":kind==2?"city":"land");
 return g;
}
void drawGeometry(Surface&canvas,const Geometry&g,const Camera&camera,
                  Color fill,Color stroke,double width,double opacity){
 camera.validate();
 if(width<0||width>64||opacity<0||opacity>1||!finite(opacity))
  throw std::invalid_argument("Invalid region style");
 if(g.shape==1){if(!g.points.empty())drawDisk(canvas,project(g.points[0],camera,
   canvas.width,canvas.height),std::max(.5,width),fill,opacity);return;}
 if(g.points.empty()||g.parts.empty())return;
 std::vector<std::vector<ScreenPoint>> screen;
 for(std::size_t i=0;i<g.parts.size();++i){
  std::size_t start=g.parts[i];
  std::size_t end=i+1<g.parts.size()?g.parts[i+1]:g.points.size();
  screen.push_back(transformRing(g.points,start,end,camera,canvas.width,canvas.height));
 }
 // Each ring's winding is preserved, and even-odd fill preserves published holes.
 fillPolygons(canvas,screen,fill,opacity);
 if(width>0)for(const auto&ring:screen){
  for(std::size_t j=1;j<ring.size();++j)
   paintLine(canvas,ring[j-1],ring[j],width,stroke,opacity);
 }
}
void drawRegion(Surface&canvas,const Geometry&g,const Camera&camera,
                const RegionStyle&style){
 camera.validate();
 auto unit=[](double x){return std::isfinite(x)&&x>=0&&x<=1;};
 if(!unit(style.fillAlpha)||!unit(style.strokeAlpha)||
    !unit(style.objectOpacity)||!unit(style.strokeProgress)||
    !unit(style.highlightStrength)||!std::isfinite(style.strokeWidth)||
    style.strokeWidth<0||style.strokeWidth>24)
  throw std::invalid_argument("Invalid Region style controls");
 if(g.shape!=5||g.points.empty()||g.parts.empty())
  throw std::invalid_argument("Region requires published polygon geometry");
 auto mix=[&](Color base){
  const double t=style.highlightStrength;
  auto component=[t](uint8_t from,uint8_t to){
   return static_cast<uint8_t>(std::lround((1-t)*from+t*to));
  };
  return Color{component(base.r,style.highlight.r),
               component(base.g,style.highlight.g),
               component(base.b,style.highlight.b),base.a};
 };
 const Color fillColor=style.highlightStroke?style.fill:mix(style.fill);
 const Color strokeColor=style.highlightStroke?mix(style.stroke):style.stroke;
 std::vector<std::vector<ScreenPoint>> rings;
 std::vector<bool> external;
 rings.reserve(g.parts.size());external.reserve(g.parts.size());
 for(std::size_t i=0;i<g.parts.size();++i){
  const std::size_t first=g.parts[i];
  const std::size_t last=i+1<g.parts.size()?g.parts[i+1]:g.points.size();
  rings.push_back(transformRing(g.points,first,last,camera,
                               canvas.width,canvas.height));
  // Natural Earth SHP follows the clockwise outer-ring convention.
  // Evaluate raw geographic vertices; do not let screen Y inversion flip it.
  double sum=0;
  for(std::size_t j=first;j+1<last;++j)
   sum+=g.points[j].lon*g.points[j+1].lat-
        g.points[j+1].lon*g.points[j].lat;
  external.push_back(sum<0||i==0);
 }
 const double fillOpacity=style.objectOpacity*style.fillAlpha;
 if(fillOpacity>0&&style.fill.a>0)
  fillPolygons(canvas,rings,fillColor,fillOpacity);
 if(!style.strokeVisible||style.strokeWidth==0||
    style.strokeProgress==0||style.strokeAlpha==0||
    style.objectOpacity==0||style.stroke.a==0)return;
 const double opacity=style.objectOpacity*style.strokeAlpha;
 double total=0;
 for(std::size_t i=0;i<rings.size();++i){
  if(style.outerContoursOnly&&!external[i])continue;
  const auto&ring=rings[i];
  for(std::size_t j=1;j<ring.size();++j)
   total+=std::hypot(ring[j].x-ring[j-1].x,ring[j].y-ring[j-1].y);
 }
 const double limit=total*style.strokeProgress;
 double current=0;
 for(std::size_t i=0;i<rings.size();++i){
  if(style.outerContoursOnly&&!external[i])continue;
  const auto&ring=rings[i];
  for(std::size_t j=1;j<ring.size();++j){
   auto a=ring[j-1],b=ring[j];
   const double length=std::hypot(b.x-a.x,b.y-a.y);
   if(length<=1e-10)continue;
   if(current>=limit)return;
   if(current+length>limit){
    const double f=(limit-current)/length;
    b={a.x+f*(b.x-a.x),a.y+f*(b.y-a.y)};
   }
   paintLine(canvas,a,b,style.strokeWidth,strokeColor,opacity);
   current+=length;
  }
 }
}
void drawRoute(Surface&canvas,const Camera&camera,const RouteOptions&route){
 camera.validate();validateGeo(route.from);validateGeo(route.to);
 for(const auto&point:route.waypoints)validateGeo(point);
 if(route.waypoints.size()>64||!finite(route.progress)||
    !finite(route.trimStart)||!finite(route.trimEnd)||
    !finite(route.followerProgress)||route.followerProgress<0||
    route.followerProgress>1||route.trimStart<0||route.trimEnd>1||
    route.trimStart>route.trimEnd||route.progress<0||route.progress>1||
    route.width<0||route.width>32||!finite(route.width)||
    route.opacity<0||route.opacity>1||!finite(route.opacity)||
    !finite(route.curvature)||route.curvature<-100||route.curvature>100)
  throw std::invalid_argument("Invalid route geometry or temporal values");
 if(route.progress==0||route.opacity==0)return;
 std::vector<GeoPoint> anchors{route.from};
 anchors.insert(anchors.end(),route.waypoints.begin(),route.waypoints.end());
 anchors.push_back(route.to);
 std::vector<ScreenPoint> screen;
 screen.reserve(anchors.size());
 const double angle=camera.bearing*pi/180.;
 const ScreenPoint wrap{canvas.width*camera.zoom*std::cos(angle),
                        canvas.width*camera.zoom*std::sin(angle)};
 for(const auto&anchor:anchors){
  const auto original=project(anchor,camera,canvas.width,canvas.height);
  if(screen.empty()){screen.push_back(original);continue;}
  ScreenPoint best=original;
  double distance=std::hypot(best.x-screen.back().x,best.y-screen.back().y);
  for(int shift:{-1,1}){
   ScreenPoint candidate{original.x+shift*wrap.x,original.y+shift*wrap.y};
   const double test=std::hypot(candidate.x-screen.back().x,
                                candidate.y-screen.back().y);
   if(test<distance){distance=test;best=candidate;}
  }
  screen.push_back(best);
 }
 constexpr int subdivision=96;
 std::vector<ScreenPoint> sampled;
 sampled.reserve((screen.size()-1)*subdivision+1);
 for(std::size_t segment=1;segment<screen.size();++segment){
  auto a=screen[segment-1],b=screen[segment];
  const double dx=b.x-a.x,dy=b.y-a.y;
  const double ratio=route.curved?route.curvature/200.:0.;
  const ScreenPoint mid{(a.x+b.x)*.5-dy*ratio,
                        (a.y+b.y)*.5+dx*ratio};
  for(int index=(segment==1?0:1);index<=subdivision;++index){
   const double t=index/static_cast<double>(subdivision),q=1-t;
   sampled.push_back({q*q*a.x+2*q*t*mid.x+t*t*b.x,
                      q*q*a.y+2*q*t*mid.y+t*t*b.y});
  }
 }
 if(sampled.size()<2)return;
 std::vector<double> cumulative(sampled.size(),0);
 for(std::size_t i=1;i<sampled.size();++i)
  cumulative[i]=cumulative[i-1]+std::hypot(sampled[i].x-sampled[i-1].x,
                                            sampled[i].y-sampled[i-1].y);
 const double length=cumulative.back();
 if(length<1e-9)return;
 const double first=route.trimStart*length;
 const double last=std::min(route.trimEnd,route.progress)*length;
 if(last<=first)return;
 std::vector<std::pair<ScreenPoint,ScreenPoint>> drawn;
 for(std::size_t i=1;i<sampled.size();++i){
  const double segment=cumulative[i]-cumulative[i-1];
  if(segment<=1e-9||cumulative[i]<=first)continue;
  if(cumulative[i-1]>=last)break;
  const double lo=clamp01((first-cumulative[i-1])/segment);
  const double hi=clamp01((last-cumulative[i-1])/segment);
  if(lo>=hi)continue;
  auto from=sampled[i-1],to=sampled[i];
  ScreenPoint p0{from.x+lo*(to.x-from.x),from.y+lo*(to.y-from.y)};
  ScreenPoint p1{from.x+hi*(to.x-from.x),from.y+hi*(to.y-from.y)};
  if(route.width>0)paintLine(canvas,p0,p1,route.width,route.stroke,route.opacity);
  drawn.push_back({p0,p1});
 }
 if(drawn.empty()||!route.arrowhead||route.arrowheadSize<=0||
    route.width==0)return;
 const auto pair=route.reverseArrowhead?drawn.front():drawn.back();
 const auto tip=route.reverseArrowhead?pair.first:pair.second;
 const auto behind=route.reverseArrowhead?pair.second:pair.first;
 const double direction=std::atan2(tip.y-behind.y,tip.x-behind.x);
 const double size=std::clamp(route.arrowheadSize,2.,64.);
 ScreenPoint left{tip.x-std::cos(direction-.5)*size,
                  tip.y-std::sin(direction-.5)*size};
 ScreenPoint right{tip.x-std::cos(direction+.5)*size,
                   tip.y-std::sin(direction+.5)*size};
 paintLine(canvas,left,tip,route.width,route.stroke,route.opacity);
 paintLine(canvas,right,tip,route.width,route.stroke,route.opacity);
}
void drawMarker(Surface&canvas,const Camera&camera,const MarkerOptions&m){
 camera.validate();validateGeo(m.at);
 if(!finite(m.size)||m.size<0||m.size>128||m.strokeWidth<0||
    m.strokeWidth>16||m.opacity<0||m.opacity>1)
  throw std::invalid_argument("Invalid marker style");
 auto p=project(m.at,camera,canvas.width,canvas.height);
 p.x+=m.offsetX;p.y+=m.offsetY;
 if(m.ring){
  drawDisk(canvas,p,m.size*.5,m.stroke,m.opacity,true,m.strokeWidth);
 }else{
  drawDisk(canvas,p,m.size*.5,m.stroke,m.opacity);
  drawDisk(canvas,p,std::max(0.,m.size*.5-m.strokeWidth),m.fill,m.opacity);
 }
}
}
