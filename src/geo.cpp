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
 validateGeo(center);
 if(!finite(zoom)||zoom<.1||zoom>50||!finite(bearing)||bearing<-360||bearing>360)
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
 if(width<1||height<1||pad<0||pad>.35||b.west>b.east||
    b.south>b.north||std::abs(b.west)>180.01||std::abs(b.east)>180.01)
  throw std::invalid_argument("Invalid fit bounds");
 Camera camera;
 camera.center={(b.west+b.east)*.5,(b.south+b.north)*.5};
 const double dx=std::max(.001,(b.east-b.west)/360.);
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
void drawRoute(Surface&canvas,const Camera&camera,const RouteOptions&route){
 camera.validate();validateGeo(route.from);validateGeo(route.to);
 if(!finite(route.progress)||!finite(route.trimStart)||!finite(route.trimEnd)||
    route.trimStart<0||route.trimEnd>1||route.trimStart>route.trimEnd||
    route.progress<0||route.progress>1||route.width<0||route.width>32||
    route.opacity<0||route.opacity>1||route.curvature<-100||route.curvature>100)
  throw std::invalid_argument("Invalid route values");
 if(route.progress==0||route.opacity==0)return;
 auto a=project(route.from,camera,canvas.width,canvas.height);
 auto b=project(route.to,camera,canvas.width,canvas.height);
 const double dx=b.x-a.x,dy=b.y-a.y;
 const double ratio=route.curvature/200.;
 const ScreenPoint midpoint{(a.x+b.x)*.5-dy*ratio,(a.y+b.y)*.5+dx*ratio};
 auto sample=[&](double t){
  double q=1-t;
  return ScreenPoint{q*q*a.x+2*q*t*midpoint.x+t*t*b.x,
                     q*q*a.y+2*q*t*midpoint.y+t*t*b.y};
 };
 constexpr int steps=128;
 std::array<ScreenPoint,steps+1> coordinates;
 std::array<double,steps+1> accumulated{};
 coordinates[0]=sample(0);
 for(int i=1;i<=steps;++i){
  coordinates[i]=sample(i/static_cast<double>(steps));
  accumulated[i]=accumulated[i-1]+std::hypot(coordinates[i].x-coordinates[i-1].x,
                                              coordinates[i].y-coordinates[i-1].y);
 }
 const double total=accumulated[steps];
 if(total<=1e-9)return;
 const double lo=route.trimStart*total;
 const double hi=std::min(route.progress,route.trimEnd)*total;
 if(hi<=lo)return;
 ScreenPoint tip=a,previous=a;
 for(int i=1;i<=steps;++i){
  const double length=accumulated[i]-accumulated[i-1];
  if(length<=1e-9||accumulated[i]<=lo)continue;
  if(accumulated[i-1]>=hi)break;
  const double first=clamp01((lo-accumulated[i-1])/length);
  const double last=clamp01((hi-accumulated[i-1])/length);
  ScreenPoint p0{coordinates[i-1].x+first*(coordinates[i].x-coordinates[i-1].x),
                 coordinates[i-1].y+first*(coordinates[i].y-coordinates[i-1].y)};
  ScreenPoint p1{coordinates[i-1].x+last*(coordinates[i].x-coordinates[i-1].x),
                 coordinates[i-1].y+last*(coordinates[i].y-coordinates[i-1].y)};
  if(first<last){paintLine(canvas,p0,p1,route.width,route.stroke,route.opacity);
   tip=p1;previous=p0;}
 }
 if(route.arrowhead&&route.arrowheadSize>0){
  double angle=std::atan2(tip.y-previous.y,tip.x-previous.x);
  double size=std::clamp(route.arrowheadSize,2.,64.);
  ScreenPoint p0{tip.x-std::cos(angle-.5)*size,tip.y-std::sin(angle-.5)*size};
  ScreenPoint p1{tip.x-std::cos(angle+.5)*size,tip.y-std::sin(angle+.5)*size};
  paintLine(canvas,p0,tip,route.width,route.stroke,route.opacity);
  paintLine(canvas,p1,tip,route.width,route.stroke,route.opacity);
 }
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
