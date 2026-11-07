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
    brazil.stroke={80,90,100,255};
    brazil.visible=false;
    const auto base=upsertGeographicSelection("",brazil);
    const auto initial=parseGeographicSelections(base);
    require(initial.size()==1 && initial[0].fill.a==180,"one RGBA country");
    require(!initial[0].visible&&initial[0].stroke.g==90,
            "region visibility and independent border color survive serialization");
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
    // Each source feature owns its own color animation timeline.
    const auto k0=upsertGeographicColorKey(
        multi,brazil.featureKey,0,Color{0,0,0,255},"linear");
    const auto k1=upsertGeographicColorKey(
        k0,brazil.featureKey,100,Color{200,80,40,155},"linear");
    const auto keyed=parseGeographicSelections(k1);
    require(keyed.size()==2&&keyed[0].colorKeys.size()==2&&
            keyed[1].colorKeys.empty(),"independent RGBA keyframe tracks");
    const auto half=evaluateGeographicRegionColor(keyed[0],50);
    require(half.r==100&&half.g==40&&half.b==20&&half.a==205,
            "linear rgba interpolation at intermediate timeline frame");
    require(evaluateGeographicRegionColor(keyed[1],50).g==255,
            "unanimated city color unaffected by country animation");
    const auto replaceFrame=upsertGeographicColorKey(
        k1,brazil.featureKey,100,Color{10,10,10,255},"hold");
    require(parseGeographicSelections(replaceFrame)[0].colorKeys.size()==2,
            "upsert does not duplicate animation frame");
    auto staticRecolor=brazil;staticRecolor.fill={40,40,40,180};
    require(parseGeographicSelections(
        upsertGeographicSelection(replaceFrame,staticRecolor))[0].colorKeys.size()==2,
        "static color edits preserve existing animation keys");
    bool missingRejected=false;
    try{(void)upsertGeographicColorKey(multi,"imaginary",2,Color{}, "linear");}
    catch(const std::invalid_argument&){missingRejected=true;}
    require(missingRejected,"cannot keyframe a nonexistent geographic feature");
    const auto removed=removeGeographicSelection(k1,brazil.featureKey);
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
