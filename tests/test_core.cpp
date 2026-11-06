#include "cartorig.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <limits>
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
  auto pp=project({-60,10},s.camera,640,360);auto rr=unproject(pp,s.camera,640,360);check(std::abs(rr.lon+60)<1e-8&&std::abs(rr.lat-10)<1e-8,"projection round trip");
  auto a=project({-64,0},s.camera,640,360);check(std::abs(a.x-320)<1e-8&&std::abs(a.y-180)<1e-8,"camera center projects to center");
  Route r=s.routes[0];check(routeFraction(r,0)==0&&routeFraction(r,20)==0&&routeFraction(r,70)==0.5&&routeFraction(r,200)==1,"route progress boundaries");
  auto fit=fitBounds({{-67,10},{-47,-15}},1280,720,.1);check(fit.zoom>=0&&fit.zoom<=16,"fit bounds zoom range");
  check(!readText(std::string(CARTORIG_ROOT)+"/data/countries.geojson").empty(),"offline asset I/O");

  // Regression: camera-opposite seam was projecting adjacent Asian vertices
  // to opposite world copies, drawing kilometer-wide screen scanlines over
  // South America. A small polygon around lon +118 must remain offscreen
  // when the camera is at lon -62 (world seam is 180 degrees away).
  Camera seamCamera;seamCamera.lon=-62;seamCamera.lat=-11;seamCamera.zoom=2.8;seamCamera.bearing=0;
  Polygon seamPolygon;seamPolygon.rings={{{117.5,15},{118.5,15},{118.5,20},{117.5,20},{117.5,15}}};
  auto seamRings=projectPolygonContinuous(seamPolygon,seamCamera,640,360);
  const double worldPixels=256.0*std::pow(2.0,seamCamera.zoom)*.5;
  bool continuous=true;
  for(size_t i=1;i<seamRings[0].size();++i)
    continuous&=std::abs(seamRings[0][i].x-seamRings[0][i-1].x)<worldPixels*.5;
  check(continuous,"dateline continuity: adjacent longitude edges do not cross whole viewport");
  Dataset seamDataset;Feature seamFeature;seamFeature.id="SEAM";seamFeature.polygons.push_back(seamPolygon);
  seamDataset.features.push_back(seamFeature);seamDataset.byId["SEAM"]=0;
  Scene seamScene;seamScene.camera=seamCamera;seamScene.style.border.a=0;
  View seamView;seamView.width=640;seamView.height=360;seamView.camera=seamCamera;
  std::vector<uint8_t> baseline(640*360*4),seamBytes(640*360*4);
  Surface baseSurface{baseline.data(),0,0,640,360,640*4,PixelFormat::ByteRGBA};
  Surface seamSurface{seamBytes.data(),0,0,640,360,640*4,PixelFormat::ByteRGBA};
  Dataset emptyDataset;
  render(seamScene,emptyDataset,seamView,baseSurface);
  render(seamScene,seamDataset,seamView,seamSurface);
  check(baseline==seamBytes,"remote seam polygon cannot create horizontal stripe");
  // Exercise real offline geometry: Chinese and Indonesian polygons contain
  // adjacent vertices around the seam at longitude +118.
  bool worldContinuous=true;
  for(const auto *id:{"CHN","IDN","MYS","AUS"}){
    const auto &feature=world.features.at(world.byId.at(id));
    for(const auto &polygon:feature.polygons){
      auto rings=projectPolygonContinuous(polygon,seamCamera,1920,1080);
      const double fullWorld=256.0*std::pow(2.0,seamCamera.zoom)*1.5;
      for(const auto &ring:rings)for(size_t j=1;j<ring.size();++j)
        worldContinuous&=std::abs(ring[j].x-ring[j-1].x)<fullWorld*.5;
    }
  }
  check(worldContinuous,"real-world Asian topology continuous across opposite seam");

  // Golden spatial guard using the real default GeoJSON and the exact camera
  // from the first Resolve 20 screenshot. The former renderer painted Asia's
  // seam polygons as full-width horizontal stripes across this ocean column.
  // Check multiple scanlines, not only a single synthetic polygon.
  View worldView;worldView.width=640;worldView.height=360;
  worldView.camera=evaluateCamera(sample,0);worldView.frame=0;
  std::vector<uint8_t> worldPixels(640*360*4,0);
  Surface worldOutput{worldPixels.data(),0,0,640,360,640*4,PixelFormat::ByteRGBA};
  render(sample,world,worldView,worldOutput);
  bool clearOcean=true;
  for(int y:{10,25,40,70,150,210,240})
    for(int x:{10,80,120}){
      const size_t offset=(static_cast<size_t>(359-y)*640+x)*4;
      clearOcean &= worldPixels[offset]==sample.style.ocean.r &&
                    worldPixels[offset+1]==sample.style.ocean.g &&
                    worldPixels[offset+2]==sample.style.ocean.b &&
                    worldPixels[offset+3]==255;
    }
  check(clearOcean,"default whole-world render contains no false horizontal ocean bands");
  // Hole coordinates follow the same world repeat as their outer ring.
  auto holes=projectPolygonContinuous(data.features[0].polygons[0],seamCamera,640,360);
  check(holes.size()==2&&holes[0].size()>3&&holes[1].size()>3,
        "polygon outer ring and hole retained during continuous projection");

  reject("{");reject("[]");reject(R"({"schemaVersion":99})");reject(R"({"camera":{"lat":900}})");reject(R"({"routes":[{"id":"a","from":"x","to":"y"}]})");
  reject(R"({"type":"FeatureCollection","features":[{"properties":{"iso3":"AA"},"geometry":{"type":"Polygon","coordinates":[[[0,999],[1,0],[2,0]]]}}]})",true);
  std::vector<uint8_t> bytes(320*180*4);View view;view.width=320;view.height=180;view.camera=s.camera;view.frame=0;Surface dest{bytes.data(),0,0,320,180,320*4,PixelFormat::ByteRGBA};
  render(s,data,view,dest);auto h0=checksum(bytes);render(s,data,view,dest);check(h0==checksum(bytes),"deterministic RGBA render");
  view.frame=90;render(s,data,view,dest);check(h0!=checksum(bytes),"route progression alters frame");
  check(*std::max_element(bytes.begin(),bytes.end())==255,"opaque raster alpha");
  const size_t w=32,h=16;std::vector<uint8_t> tile(w*h*4+64,0xCD);Surface sub{tile.data()+32,20,50,52,66,int(w*4),PixelFormat::ByteRGBA};view.frame=0;render(s,data,view,sub);check(std::all_of(tile.begin(),tile.begin()+32,[](auto b){return b==0xCD;})&&std::all_of(tile.end()-32,tile.end(),[](auto b){return b==0xCD;}),"tile rendering memory safety");
  // RenderWindow must not overwrite pixels outside the requested rectangle.
  std::vector<uint8_t> sentinel(16*12*4,0xCD);Surface whole{sentinel.data(),0,0,16,12,16*4,PixelFormat::ByteRGBA};
  auto cropped=cropSurface(whole,3,2,13,9);View small;small.width=16;small.height=12;small.camera=s.camera;render(s,data,small,cropped);
  bool regionIsolated=true;
  for(int y=0;y<12;y++)for(int x=0;x<16;x++)if(x<3||x>=13||y<2||y>=9){for(int k=0;k<4;k++)regionIsolated&=sentinel[(y*16+x)*4+k]==0xCD;}
  check(regionIsolated,"RenderWindow cannot overwrite outside requested tile");
  auto empty=cropSurface(whole,30,30,40,40);check(empty.data==nullptr,"non-overlapping render window is empty");
  // Signed row stride is legal in OFX (top-down native allocations).
  auto reversed=whole;reversed.data=sentinel.data()+static_cast<ptrdiff_t>(11)*16*4;reversed.rowBytes=-16*4;
  auto reversedCrop=cropSurface(reversed,2,1,9,7);
  check(reversedCrop.data==sentinel.data()+static_cast<ptrdiff_t>(10)*16*4+2*4&&reversedCrop.rowBytes==-16*4,"negative rowBytes crop offset");
  // OpenFX output allocations are not guaranteed to contain initialized pixels.
  // A full-opaque map must be identical regardless of prior VRAM/RAM contents.
  std::vector<uint8_t> dirtyBytes(320*180*4,0xCD);
  Surface dirtyByteSurface{dirtyBytes.data(),0,0,320,180,320*4,PixelFormat::ByteRGBA};
  View noAnim=view;noAnim.width=320;noAnim.height=180;noAnim.camera=s.camera;noAnim.preserveBackground=false;
  s.style.transparent=false;
  std::vector<uint8_t> cleanBytes(320*180*4,0);
  Surface cleanByteSurface{cleanBytes.data(),0,0,320,180,320*4,PixelFormat::ByteRGBA};
  render(s,data,noAnim,dirtyByteSurface);render(s,data,noAnim,cleanByteSurface);
  check(dirtyBytes==cleanBytes,"opaque byte render independent of uninitialized destination");
  std::vector<float> dirtyFloats(320*180*4,std::numeric_limits<float>::quiet_NaN());
  std::vector<float> cleanFloats(320*180*4,0);
  Surface dirtyFloatSurface{dirtyFloats.data(),0,0,320,180,320*16,PixelFormat::FloatRGBA};
  Surface cleanFloatSurface{cleanFloats.data(),0,0,320,180,320*16,PixelFormat::FloatRGBA};
  render(s,data,noAnim,dirtyFloatSurface);render(s,data,noAnim,cleanFloatSurface);
  bool floatOpaqueDeterministic=true;
  for(size_t i=0;i<dirtyFloats.size();++i)
    floatOpaqueDeterministic&=std::isfinite(dirtyFloats[i])&&std::abs(dirtyFloats[i]-cleanFloats[i])<1e-6f;
  check(floatOpaqueDeterministic,"opaque float render overwrites prior NaN data deterministically");

  // Diagnostic pixels bypass the map engine and must have exact RGBA packing.
  std::vector<uint8_t> bars(8*2*4,0xDB);
  Surface barsSurface{bars.data(),0,0,8,2,8*4,PixelFormat::ByteRGBA};
  renderDiagnosticPattern(barsSurface,8,2,1);
  auto pixel=[&](int x,int y,int channel){return bars[(y*8+x)*4+channel];};
  check(pixel(0,0,0)==255&&pixel(0,0,1)==0&&pixel(0,0,2)==0&&pixel(0,0,3)==255,"diagnostic red exact RGBA8");
  check(pixel(2,1,0)==0&&pixel(2,1,1)==255&&pixel(2,1,2)==0,"diagnostic green exact RGBA8");
  check(pixel(4,1,2)==255&&pixel(4,1,0)==0&&pixel(4,1,1)==0,"diagnostic blue exact RGBA8");
  check(pixel(6,0,0)==255&&pixel(6,0,1)==255&&pixel(6,0,2)==255,"diagnostic white exact RGBA8");
  std::vector<float> barFloats(8*2*4,std::numeric_limits<float>::quiet_NaN());
  Surface barFloatSurface{barFloats.data(),0,0,8,2,8*16,PixelFormat::FloatRGBA};
  renderDiagnosticPattern(barFloatSurface,8,2,1);
  check(barFloats[0]==1&&barFloats[1]==0&&barFloats[2]==0&&barFloats[3]==1,"diagnostic red exact RGBA float");
  check(barFloats[8]==0&&barFloats[9]==1&&barFloats[10]==0&&barFloats[11]==1,"diagnostic green exact RGBA float");
  renderDiagnosticPattern(barFloatSurface,8,2,3);
  check(barFloats[3]==0&&barFloats[(4)*4+3]==0.5f&&barFloats[(6)*4+3]==1,"diagnostic alpha split float");
  // A small RenderWindow should not mutate pixels outside the tile.
  std::fill(bars.begin(),bars.end(),0xDB);
  auto barTile=cropSurface(barsSurface,2,0,5,2);
  renderDiagnosticPattern(barTile,8,2,1);
  bool outsideGood=true;
  for(int y=0;y<2;y++)for(int x=0;x<8;x++)if(x<2||x>=5)
    for(int channel=0;channel<4;channel++)outsideGood &= pixel(x,y,channel)==0xDB;
  check(outsideGood,"diagnostic respects cropped output tile");
  std::vector<float> floats(320*180*4,0);Surface f{floats.data(),0,0,320,180,320*16,PixelFormat::FloatRGBA};render(s,data,view,f);check(std::all_of(floats.begin(),floats.end(),[](float x){return std::isfinite(x)&&x>=0&&x<=1;}),"float RGBA finite bounds");
  s.style.transparent=true;render(s,data,view,dest);check(bytes[3]==0,"transparent empty ocean pixel");
  s.cameraKeys.clear();check(evaluateCamera(s,15).lon==s.camera.lon,"static camera");
  }catch(const std::exception &e){check(false,std::string("unexpected exception: ")+e.what());}
 std::cout<<passes<<" assertions passed, "<<failures<<" failures\n";return failures?1:0;
}
