#include "cartorig/motion.hpp"
#include <cmath>
#include <iostream>
#include <set>
#include <stdexcept>
using namespace cartorig::rc1;
void check(bool condition,const char*message){
 if(!condition)throw std::runtime_error(message);
}
int main(){
 try{
  Motion model;
  check(model.catalog().size()==16,"exactly sixteen R1.0 Motion presets");
  std::set<std::string> unique;
  for(const auto&entry:model.catalog()){
   check(!entry.channels.empty()&&entry.suggestedFrames>0,"preset targets");
   check(unique.insert(entry.id).second,"duplicate preset ID");
  }
  model.setBase("ObjectOpacity",.7);
  Request request;request.start=10;request.duration=24;
  model.apply("MO-REG-01",request);
  check(model.at("ObjectOpacity",10)==0,"fade begins at zero");
  check(std::abs(model.at("ObjectOpacity",34)-.7)<1e-9,"fade ends at current target");
  check(model.at("ObjectOpacity",22)>0&&model.at("ObjectOpacity",22)<.7,
        "intermediate spline");
  check(!model.customized(),"fresh preset not customized");
  Request altered=request;altered.duration=40;
  model.update(altered);
  check(std::abs(model.at("ObjectOpacity",50)-.7)<1e-9,"safe update retimes");
  model.editManualKey("ObjectOpacity",30,.91);
  check(model.customized(),"manual edit detected");
  bool refused=false;
  try{model.update(request);}catch(const std::invalid_argument&){refused=true;}
  check(refused,"cannot overwrite customized spline silently");
  model.remove(Removal::DeleteOwnedKeys);
  check(model.activePreset().empty(),"preset removal");
  check(std::abs(model.at("ObjectOpacity",30)-.91)<1e-9,
        "manual key survives deleting preset-owned keys");

  Motion regions;
  regions.setBase("FillR",10);regions.setBase("FillG",20);regions.setBase("FillB",30);
  Request color;color.start=100;color.duration=30;
  color.target={{"FillR",230},{"FillG",110},{"FillB",35}};
  regions.apply("MO-REG-03",color);
  check(regions.at("FillR",100)==10&&regions.at("FillR",130)==230,
        "color transition changes only declared RGB tracks");
  refused=false;
  try{regions.apply("MO-REG-04",color);}catch(const std::invalid_argument&){refused=true;}
  check(refused,"conflicting active preset requires resolution");
  regions.remove(Removal::KeepManual);
  check(!regions.track("FillR").keys.empty(),"keep manual keys after unlink");

  Motion camera;
  camera.setBase("CenterLongitude",179);
  camera.setBase("CenterLatitude",-15);
  camera.setBase("Zoom",1);
  camera.setBase("Bearing",0);
  Request fly;fly.start=0;fly.duration=40;
  fly.target={{"CenterLongitude",-179},{"CenterLatitude",5},{"Zoom",4},{"Bearing",0}};
  camera.apply("MO-CAM-01",fly);
  check(std::abs(camera.at("CenterLongitude",40)-181)<1e-7,
        "antimeridian fly uses shortest longitudinal arc");
  check(camera.at("Zoom",20)>1&&camera.at("Zoom",20)<4,
        "camera zoom is continuously animated");
  Motion route;
  route.setBase("DrawProgress",1);
  Request draw;draw.duration=50;
  route.apply("MO-RTE-01",draw);
  check(route.at("DrawProgress",0)==0&&route.at("DrawProgress",50)==1,
        "draw path progress");
  route.remove(Removal::DeleteOwnedKeys);
  route.apply("MO-RTE-02",draw);
  check(route.at("DrawProgress",0)==1&&route.at("DrawProgress",50)==0,
        "erase path progress");
  Motion pulse;
  Request p;p.start=100;p.pulseCount=2;p.pulseCycle=18;p.pulsePeak=.35;
  pulse.apply("MO-REG-06",p);
  for(int frame:{100,118,136})
    check(std::abs(pulse.at("HighlightStrength",frame))<1e-8,
          "Highlight returns to zero after each cycle");
  for(int frame:{109,127})
    check(std::abs(pulse.at("HighlightStrength",frame)-.35)<1e-8,
          "Highlight has exactly two 35% peaks (QA-36)");
  Motion oneFrame;
  oneFrame.setBase("FillR",255);oneFrame.setBase("FillG",0);oneFrame.setBase("FillB",0);
  Request switchColor;switchColor.start=330;switchColor.duration=1;
  switchColor.target={{"FillR",0},{"FillG",255},{"FillB",0}};
  oneFrame.apply("MO-REG-04",switchColor);
  check(oneFrame.at("FillR",329)==255&&oneFrame.at("FillR",330)==0&&
        oneFrame.at("FillG",329)==0&&oneFrame.at("FillG",330)==255,
        "Instant Color changes on frame 330, not 331 (QA-15/16)");
  Motion layers;
  layers.setBase("CountryBorderLayerOpacity",1);
  layers.setBase("OceanLayerOpacity",.8);
  Request fadeLayer;fadeLayer.duration=18;fadeLayer.layerChannel="CountryBorderLayerOpacity";
  layers.apply("MO-MAP-01",fadeLayer);
  check(layers.at("CountryBorderLayerOpacity",0)==0&&
        layers.at("CountryBorderLayerOpacity",18)==1&&
        layers.at("OceanLayerOpacity",9)==.8,
        "Layer Fade changes only selected Admin-0 channel (QA-40)");
  Motion both;
  both.setBase("ObjectOpacity",1);both.setBase("Size",14);
  Request fade;fade.duration=18;
  both.apply("MO-MRK-01",fade);
  both.apply("MO-MRK-02",fade);
  check(both.activePresets().size()==2,
        "Fade + Pop coexist on independent channels (QA-32/43)");
  check(both.at("ObjectOpacity",9)>0&&both.at("Size",9)>0,
        "Both native channel curves evaluate together");
  bool sameChannelBlocked=false;
  try{both.apply("MO-REG-01",fade);}
  catch(const std::invalid_argument&){sameChannelBlocked=true;}
  check(sameChannelBlocked,"Active channel owner cannot be silently replaced");
  both.remove(Removal::DeleteOwnedKeys);
  check(both.activePresets().size()==1,"Remove affects only active preset");
  std::cout<<"PASS motion: 16 IDs, fade, color, camera, route, conflicts, customized, undo-safe removal\n";
  return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
