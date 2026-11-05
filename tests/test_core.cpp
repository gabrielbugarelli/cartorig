#include "cartorig.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace cartorig;
static int failures=0,passes=0;
static void check(bool b,const std::string &message){if(!b){++failures;std::cerr<<"FAIL "<<message<<"\n";}else ++passes;}
static void reject(const std::string &json,bool dataset=false){try{if(dataset)parseGeoJSON(json);else parseScene(json);check(false,"reject invalid JSON: "+json.substr(0,30));}catch(const std::exception &){check(true,"reject");}}
static const char *geo=R"({"type":"FeatureCollection","features":[{"type":"Feature","properties":{"iso3":"AAA","name":"Alpha"},"geometry":{"type":"Polygon","coordinates":[[[-80,-10],[-50,-10],[-50,10],[-80,10],[-80,-10]],[[-72,-3],[-62,-3],[-62,3],[-72,3],[-72,-3]]]}},{"type":"Feature","properties":{"iso3":"BBB"},"geometry":{"type":"MultiPolygon","coordinates":[[[[20,0],[40,0],[40,30],[20,30],[20,0]]]]}}]})";
static const char *scene=R"({"schemaVersion":1,"title":"Test","fps":24,"frames":240,"highlights":["AAA"],"camera":{"lon":-64,"lat":0,"zoom":2,"bearing":0},"markers":[{"id":"A","label":"A","lon":-67,"lat":0},{"id":"B","label":"B","lon":-52,"lat":0}],"routes":[{"id":"AB","from":"A","to":"B","start":20,"end":120,"curve":30}],"cameraKeys":[{"frame":0,"lon":-179,"lat":0,"zoom":2},{"frame":100,"lon":179,"lat":0,"zoom":4}]})";
static uint64_t checksum(const std::vector<uint8_t> &v){uint64_t h=1469598103934665603ull;for(auto x:v){h^=x;h*=1099511628211ull;}return h;}
int main(){
 try{
  auto data=parseGeoJSON(geo);check(data.features.size()==2,"polygon and multipolygon parsing");check(data.byId.count("AAA")&&data.byId.count("BBB"),"ISO3 lookup");check(data.features[0].polygons[0].rings.size()==2,"preserved polygon hole");
  auto s=parseScene(scene);check(s.routes.size()==1&&s.markers.size()==2,"scene objects");check(s.cameraKeys.size()==2,"camera keys");
  auto sample=parseScene(readText(std::string(CARTORIG_ROOT)+"/samples/brasil-venezuela.cartorig-native.json"));
  auto world=parseGeoJSON(readText(std::string(CARTORIG_ROOT)+"/data/countries.geojson"));
  check(world.features.size()>150,"offline world dataset loaded");check(world.byId.count("BRA")&&world.byId.count("VEN"),"world includes Brazil and Venezuela");check(sample.routes.size()==1&&sample.highlighted.size()==2,"sample works");
  check(std::abs(normalizeLon(181)+179)<1e-9,"longitude wrap");check(std::abs(normalizeLon(-181)-179)<1e-9,"negative longitude wrap");
  auto cam=evaluateCamera(s,50);check(std::abs(std::abs(cam.lon)-180)<1.1,"short antimeridian crossing");check(std::abs(cam.zoom-3)<1e-8,"interpolated camera zoom");
  auto pp=project({-60,10},s.camera,640,360),rr=unproject(pp,s.camera,640,360);check(std::abs(rr.lon+60)<1e-8&&std::abs(rr.lat-10)<1e-8,"projection round trip");
  auto a=project({-64,0},s.camera,640,360);check(std::abs(a.x-320)<1e-8&&std::abs(a.y-180)<1e-8,"camera center projects to center");
  Route r=s.routes[0];check(routeFraction(r,0)==0&&routeFraction(r,20)==0&&routeFraction(r,70)==0.5&&routeFraction(r,200)==1,"route progress boundaries");
  auto fit=fitBounds({{-67,10},{-47,-15}},1280,720,.1);check(fit.zoom>=0&&fit.zoom<=16,"fit bounds zoom range");
  check(!readText(std::string(CARTORIG_ROOT)+"/data/countries.geojson").empty(),"offline asset I/O");
  reject("{");reject("[]");reject(R"({"schemaVersion":99})");reject(R"({"camera":{"lat":900}})");reject(R"({"routes":[{"id":"a","from":"x","to":"y"}]})");
  reject(R"({"type":"FeatureCollection","features":[{"properties":{"iso3":"AA"},"geometry":{"type":"Polygon","coordinates":[[[0,999],[1,0],[2,0]]]}}]})",true);
  std::vector<uint8_t> bytes(320*180*4);View view;view.width=320;view.height=180;view.camera=s.camera;view.frame=0;Surface dest{bytes.data(),0,0,320,180,320*4,PixelFormat::ByteRGBA};
  render(s,data,view,dest);auto h0=checksum(bytes);render(s,data,view,dest);check(h0==checksum(bytes),"deterministic RGBA render");
  view.frame=90;render(s,data,view,dest);check(h0!=checksum(bytes),"route progression alters frame");
  check(*std::max_element(bytes.begin(),bytes.end())==255,"opaque raster alpha");
  const size_t w=32,h=16;std::vector<uint8_t> tile(w*h*4+64,0xCD);Surface sub{tile.data()+32,20,50,52,66,int(w*4),PixelFormat::ByteRGBA};view.frame=0;render(s,data,view,sub);check(std::all_of(tile.begin(),tile.begin()+32,[](auto b){return b==0xCD;})&&std::all_of(tile.end()-32,tile.end(),[](auto b){return b==0xCD;}),"tile rendering memory safety");
  std::vector<float> floats(320*180*4,0);Surface f{floats.data(),0,0,320,180,320*16,PixelFormat::FloatRGBA};render(s,data,view,f);check(std::all_of(floats.begin(),floats.end(),[](float x){return std::isfinite(x)&&x>=0&&x<=1;}),"float RGBA finite bounds");
  s.style.transparent=true;render(s,data,view,dest);check(bytes[3]==0,"transparent empty ocean pixel");
  s.cameraKeys.clear();check(evaluateCamera(s,15).lon==s.camera.lon,"static camera");
  }catch(const std::exception &e){check(false,std::string("unexpected exception: ")+e.what());}
 std::cout<<passes<<" assertions passed, "<<failures<<" failures\n";return failures?1:0;
}
