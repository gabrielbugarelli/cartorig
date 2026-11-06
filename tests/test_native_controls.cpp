#include "native_controls.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace cartorig;
static int pass=0,failed=0;
void check(bool yes,const std::string &what){
  if(yes)++pass;
  else{++failed;std::cerr<<"FAIL: "<<what<<"\n";}
}
template<class F> void rejects(F&& fn,const std::string&what){
  try{fn();check(false,what);}
  catch(const std::invalid_argument&){check(true,what);}
}
uint64_t checksum(const std::vector<uint8_t>&b){
  uint64_t v=1469598103934665603ULL;
  for(auto x:b){v^=x;v*=1099511628211ULL;}
  return v;
}
std::vector<uint8_t> paint(const Scene &s,const Dataset &d,int frame,double reveal=1){
  constexpr int w=640,h=360;
  std::vector<uint8_t> bytes(w*h*4,0);
  Surface output{bytes.data(),0,0,w,h,w*4,PixelFormat::ByteRGBA};
  View view;view.width=w;view.height=h;view.frame=frame;
  view.camera=evaluateCamera(s,frame);view.routeProgress=reveal;
  render(s,d,view,output);
  return bytes;
}
int main(){
  try{
    const auto scene=parseScene(readText(std::string(CARTORIG_ROOT)+
      "/data/default-map.cartorig-native.json"));
    const auto world=parseGeoJSON(readText(std::string(CARTORIG_ROOT)+
      "/data/countries.geojson"));
    check(scene.cameraKeys.empty(),"neutral map: no camera animation");
    check(scene.markers.empty(),"neutral map: no markers");
    check(scene.routes.empty(),"neutral map: no routes");
    check(scene.highlighted.empty(),"neutral map: no highlighted countries");
    check(std::abs(scene.camera.lon)<1e-9&&std::abs(scene.camera.lat)<1e-9,
          "neutral map: generic world camera");
    check(checksum(paint(scene,world,0))==checksum(paint(scene,world,96))&&
          checksum(paint(scene,world,96))==checksum(paint(scene,world,239)),
          "neutral map: all times identical without authored keys");

    check(normalizedISO3(" bra ")=="BRA","lower-case ISO3 normalizes");
    check(normalizedISO3("VeN")=="VEN","mixed-case ISO3 normalizes");
    check(normalizedISO3("BRA,VEN").empty(),"multiple codes must use separate fields");
    check(normalizedISO3("BR").empty(),"ISO2 not mistaken for ISO3");
    check(normalizedISO3("").empty(),"empty ISO3 valid neutral state");
    check(normalizedISO3("br4").empty(),"malformed ISO3 ignored");

    NativeMapControls c;
    auto untouched=sceneWithNativeControls(scene,c);
    check(untouched.routes.empty()&&untouched.markers.empty()&&
          untouched.highlighted.empty(),"no synthetic objects by default");
    check(checksum(paint(untouched,world,0))==checksum(paint(untouched,world,120)),
          "native default remains static");

    c.countryA=" bra ";c.countryB="VeN";
    auto highlighted=sceneWithNativeControls(scene,c);
    check(highlighted.highlighted.size()==2&&
          highlighted.highlighted[0]=="BRA"&&highlighted.highlighted[1]=="VEN",
          "countries selected by user, not baked in");
    check(scene.highlighted.empty(),"editing does not mutate cached source scene");
    check(checksum(paint(highlighted,world,0))!=checksum(paint(scene,world,0)),
          "highlight selection affects painted output");
    c.countryB="BRA";
    auto dedup=sceneWithNativeControls(scene,c);
    check(dedup.highlighted.size()==1,"duplicate country names deduplicated");
    c.countryB="";
    c.highlightStrength=0;
    auto transparentHighlight=sceneWithNativeControls(scene,c);
    check(transparentHighlight.style.highlight.a==0,"highlight opacity animatable to zero");
    check(checksum(paint(transparentHighlight,world,0))==
          checksum(paint(scene,world,0)),
          "highlight opacity zero removes highlighted fill");
    c.highlightStrength=1;

    c.routeEnabled=true;c.routeStart={-20,0};c.routeEnd={20,0};
    c.routeCurve=18;c.routeWidth=3;c.routeMarkers=false;
    auto route=sceneWithNativeControls(scene,c);
    check(route.routes.size()==1&&route.markers.size()==2,
          "user-enabled route builds complete marker endpoints");
    check(!route.markers[0].visible&&!route.markers[1].visible,
          "route endpoints can be hidden independently");
    check(checksum(paint(route,world,0,0))==checksum(paint(sceneWithNativeControls(scene,c),world,0,0)),
          "route drawing deterministic");
    check(checksum(paint(route,world,0,0))!=checksum(paint(route,world,0,1)),
          "native RouteProgress 0 to 1 animates only on demand");
    c.routeMarkers=true;c.startLabel="START";c.endLabel="END";
    auto markers=sceneWithNativeControls(scene,c);
    check(markers.markers[0].visible&&markers.markers[1].visible&&
          markers.markers[0].label=="START"&&markers.markers[1].label=="END",
          "user-controlled marker labels and visibility");
    c.routeEnd={35,12};
    check(checksum(paint(sceneWithNativeControls(scene,c),world,0,1))!=
          checksum(paint(markers,world,0,1)),
          "keyframe-able native route coordinates change the geometry");

    c.customColors=true;
    c.ocean={15,30,120,255};c.land={150,160,175,255};
    c.highlight={255,200,10,220};
    auto recolored=sceneWithNativeControls(scene,c);
    check(recolored.style.ocean.b==120&&recolored.style.land.r==150&&
          recolored.style.highlight.r==255,
          "user palette overrides built-in colors on demand");
    c.customColors=false;
    auto restoredPalette=sceneWithNativeControls(scene,c);
    check(restoredPalette.style.ocean.b==scene.style.ocean.b,
          "palette override disabled preserves imported scene colors");

    c.routeEnabled=false;c.highlightStrength=1.5;
    rejects([&]{(void)sceneWithNativeControls(scene,c);},
            "invalid strength rejected without crashing");
    c.highlightStrength=1;c.routeWidth=200;
    rejects([&]{(void)sceneWithNativeControls(scene,c);},
            "invalid route width rejected");
    c.routeWidth=3;c.routeEnabled=true;c.routeEnd.lat=100;
    rejects([&]{(void)sceneWithNativeControls(scene,c);},
            "invalid geographic latitude rejected");
  }catch(const std::exception &e){
    check(false,std::string("unexpected: ")+e.what());
  }
  std::cout<<pass<<" assertions, "<<failed<<" failures\n";
  return failed?1:0;
}
