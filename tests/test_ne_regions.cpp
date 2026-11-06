#include "natural_earth_regions.hpp"
#include <iostream>
#include <stdexcept>
using namespace cartorig;
static void require(bool condition,const char*reason){
  if(!condition)throw std::runtime_error(reason);
}
int main(){
  try{
    GeographicRegionSelection brazil;
    brazil.featureKey="ne_10m_admin_0_countries:15";
    brazil.kind="country";brazil.name="Brazil";brazil.parent="South America";
    brazil.sourceLayer="ne_10m_admin_0_countries";
    brazil.scale="10m";brazil.sourceRowId=15;
    brazil.fill={10,20,30,180};
    const auto base=upsertGeographicSelection("",brazil);
    const auto initial=parseGeographicSelections(base);
    require(initial.size()==1 && initial[0].fill.a==180,"one RGBA country");
    auto updated=brazil;updated.fill={200,10,60,200};
    const auto same=upsertGeographicSelection(base,updated);
    require(parseGeographicSelections(same).size()==1,
            "same stable geographic key updates color not duplicates");
    GeographicRegionSelection city=brazil;
    city.featureKey="ne_10m_populated_places:2";
    city.kind="city";city.name="São Paulo";city.parent="Brazil";
    city.sourceLayer="ne_10m_populated_places";
    city.sourceRowId=2;city.fill={0,255,160,255};
    const auto multi=upsertGeographicSelection(same,city);
    const auto both=parseGeographicSelections(multi);
    require(both.size()==2&&both[0].fill.r==200&&both[1].fill.g==255,
            "two independent persisted styles");
    const auto removed=removeGeographicSelection(multi,brazil.featureKey);
    require(parseGeographicSelections(removed).size()==1&&
            parseGeographicSelections(removed)[0].kind=="city",
            "remove only selected stable geographical ID");
    bool rejected=false;
    try{
      (void)parseGeographicSelections("[{\"kind\":\"city\"}]");
    }catch(const std::invalid_argument&){rejected=true;}
    require(rejected,"reject malformed region JSON");
    rejected=false;
    try{
      (void)parseGeographicSelections(multi+ "garbage");
    }catch(const std::invalid_argument&){rejected=true;}
    require(rejected,"reject trailing JSON");
    std::cout<<"PASS: region persistence, stable upsert, independent colors, removal, invalid JSON\n";
    return 0;
  }catch(const std::exception &e){
    std::cerr<<"FAILED: "<<e.what()<<"\n";return 1;
  }
}
