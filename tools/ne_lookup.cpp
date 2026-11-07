#include "natural_earth_catalog.hpp"
#include <iostream>
#include <cmath>
#include <iomanip>
#include <limits>
#include <string>
#include <vector>
#ifdef _WIN32
# define WIN32_LEAN_AND_MEAN
# include <windows.h>
#endif
namespace {
int run(const std::vector<std::string>&args){
  if(args.size()!=3&&args.size()!=4){
    std::cerr<<"Usage: cartorig_ne_lookup INDEX.sqlite KIND SEARCH [SOURCE.gpkg]\n";return 2;
  }
  try {
    const auto results=cartorig::NaturalEarthCatalog::search(args[0],args[2],args[1]);
    for(const auto &r:results)
      {std::cout<<r.kind<<"\t"<<r.name<<"\t"<<r.parent<<"\t"<<r.geometryType
               <<"\t"<<r.sourceLayer<<"\t"<<r.featureKey;
        // Append stable publisher metadata for the unified CartoRig editor.
        // No city polygon is fabricated: point coordinates are real publisher
        // vertices; area focus uses only a visibly-labelled bounding-box center.
        std::cout<<"\t"<<r.sourceRowId<<"\t"<<r.scale;
        if(args.size()==4){
          cartorig::NaturalEarthGeometry geom;
          std::vector<cartorig::NaturalEarthGeometry> continent;
          if(r.kind=="continent"){
            continent=cartorig::NaturalEarthCatalog::continentGeometries(args[3],r.name,"10m");
          }else geom=cartorig::NaturalEarthCatalog::featureGeometry(args[3],r);
          double minlon=std::numeric_limits<double>::infinity();
          double maxlon=-minlon, minlat=minlon, maxlat=-minlon;
          const auto scan=[&](cartorig::GeoPoint p){
            if(!std::isfinite(p.lon)||!std::isfinite(p.lat))return;
            minlon=std::min(minlon,p.lon);maxlon=std::max(maxlon,p.lon);
            minlat=std::min(minlat,p.lat);maxlat=std::max(maxlat,p.lat);
          };
          for(const auto &entry:continent)
            for(const auto &poly:entry.polygons)
              for(const auto &ring:poly.rings)for(const auto &p:ring)scan(p);
          for(const auto &p:geom.points)scan(p);
          for(const auto &line:geom.lines)for(const auto &p:line)scan(p);
          for(const auto &poly:geom.polygons)
            for(const auto &ring:poly.rings)for(const auto &p:ring)scan(p);
          if(std::isfinite(minlon)){
            const double lon=geom.points.empty()?(minlon+maxlon)*0.5:geom.points.front().lon;
            const double lat=geom.points.empty()?(minlat+maxlat)*0.5:geom.points.front().lat;
            std::cout<<"\t"<<std::setprecision(12)<<lon<<"\t"<<lat;
          }else std::cout<<"\t\t";
          std::cout<<"\tPOINTS="<<geom.points.size()
                   <<"\tLINES="<<geom.lines.size()
                   <<"\tPOLYGONS="<<geom.polygons.size();
        }
        std::cout<<"\n";}
    return 0;
  }catch(const std::exception &e){
    std::cerr<<"CartoRig Natural Earth: "<<e.what()<<"\n";return 1;
  }
}
} // namespace
#ifdef _WIN32
// Windows CRT main(argv) decodes Unicode through the current ANSI codepage.
// Natural Earth place names must remain UTF-8 independently of system locale.
static std::string utf8(const wchar_t*source) {
  int len=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,source,-1,nullptr,0,nullptr,nullptr);
  if(len<=0)throw std::runtime_error("invalid UTF-16 Windows argument");
  std::string out(static_cast<size_t>(len),'\0');
  if(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,source,-1,
                         &out[0],len,nullptr,nullptr)!=len)
    throw std::runtime_error("UTF-8 argument conversion failed");
  out.pop_back();
  return out;
}
int wmain(int argc,wchar_t**argv){
  try{
    std::vector<std::string> args;
    for(int i=1;i<argc;++i)args.push_back(utf8(argv[i]));
    return run(args);
  }catch(const std::exception &e){
    std::cerr<<"CartoRig Natural Earth: "<<e.what()<<"\n";return 1;
  }
}
#else
int main(int argc,char**argv){
  std::vector<std::string> args;
  for(int i=1;i<argc;++i)args.emplace_back(argv[i]);
  return run(args);
}
#endif
