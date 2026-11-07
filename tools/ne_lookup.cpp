#include "natural_earth_catalog.hpp"
#include <iostream>
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
        if(args.size()==4){
          const auto geom=cartorig::NaturalEarthCatalog::featureGeometry(args[3],r);
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
