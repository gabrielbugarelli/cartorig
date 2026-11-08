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
  camera.setBase("Longitude",179);
  camera.setBase("Latitude",-15);
  camera.setBase("Zoom",1);
  camera.setBase("Bearing",0);
  Request fly;fly.start=0;fly.duration=40;
  fly.target={{"Longitude",-179},{"Latitude",5},{"Zoom",4},{"Bearing",0}};
  camera.apply("MO-CAM-01",fly);
  check(std::abs(camera.at("Longitude",40)-181)<1e-7,
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
  Request p;p.start=20;p.duration=32;p.target={{"HighlightStrength",.8}};
  pulse.apply("MO-REG-06",p);
  check(pulse.at("HighlightStrength",20)==0&&
        std::abs(pulse.at("HighlightStrength",36)-.8)<1e-8&&
        pulse.at("HighlightStrength",52)==0,"pulse 3-key determinism");
  std::cout<<"PASS motion: 16 IDs, fade, color, camera, route, conflicts, customized, undo-safe removal\n";
  return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
