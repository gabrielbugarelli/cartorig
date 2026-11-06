#include "natural_earth_catalog.hpp"
#include <iostream>
#include <string>
int main(int argc,char**argv){
  if(argc!=4){std::cerr<<"Usage: cartorig_ne_lookup INDEX.sqlite KIND SEARCH\n";return 2;}
  try{
    const auto results=cartorig::NaturalEarthCatalog::search(argv[1],argv[3],argv[2]);
    for(const auto&r:results)
      std::cout<<r.kind<<"\t"<<r.name<<"\t"<<r.parent<<"\t"<<r.geometryType
               <<"\t"<<r.sourceLayer<<"\t"<<r.featureKey<<"\n";
    return 0;
  }catch(const std::exception &e){
    std::cerr<<"CartoRig Natural Earth: "<<e.what()<<"\n";return 1;
  }
}
