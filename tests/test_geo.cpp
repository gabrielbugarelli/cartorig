#include "cartorig/geo.hpp"
#include "cartorig/labels.hpp"
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
using namespace cartorig::rc1;
void check(bool yes,const char*message){
 if(!yes)throw std::runtime_error(message);
}
template<class T>void value(std::ofstream&f,T v){
 f.write(reinterpret_cast<const char*>(&v),sizeof(v));
}
int main(){
 try{
  auto folder=std::filesystem::temp_directory_path()/"cartorig_rc1_test";
  std::filesystem::create_directories(folder);
  std::string id="fixture_admin1:12";
  {
   std::ofstream out(folder/"geometry.crgeo",std::ios::binary|std::ios::trunc);
   out.write("CRG1",4);value<uint32_t>(out,1);
   value<uint16_t>(out,static_cast<uint16_t>(id.size()));
   out.write(id.data(),static_cast<std::streamsize>(id.size()));
   value<uint8_t>(out,1);value<uint32_t>(out,12);value<uint8_t>(out,5);
   for(auto f:std::array<double,4>{-45.,-25.,-43.,-22.})value<double>(out,f);
   value<uint32_t>(out,1);value<uint32_t>(out,5);value<uint32_t>(out,0);
   for(auto point:std::array<GeoPoint,5>{
      GeoPoint{-45,-25},{-43,-25},{-43,-22},{-45,-22},{-45,-25}}){
    value<double>(out,point.lon);value<double>(out,point.lat);
   }
  }
  auto bytes=std::filesystem::file_size(folder/"geometry.crgeo");
  {
   std::ofstream out(folder/"catalog.tsv",std::ios::trunc);
   out<<"id\tkind\tname\tparent\taliases\tminx\tminy\tmaxx\tmaxy\toffset\tbytes\n";
   out<<id<<"\tstate\tRio de Janeiro\tBrazil\trio de janeiro|estado do rio de janeiro"
      <<"\t-45\t-25\t-43\t-22\t8\t"<<bytes-8<<"\n";
  }
  Catalog catalog(folder);
  check(catalog.size()==1,"catalog count");
  auto matches=catalog.search("RIO DE JANEIRO","state");
  check(matches.size()==1&&matches[0].kind=="state","typed search");
  check(catalog.search("Rio de Janeiro","city").empty(),"city-state confusion");
  auto shape=catalog.geometry(id);
  check(shape.shape==5&&shape.points.size()==5,"published shape");
  Camera camera;camera.center={-44,-23.5};camera.zoom=8;
  auto center=project(camera.center,camera,800,600);
  check(std::abs(center.x-400)<.01&&std::abs(center.y-300)<.01,"camera center");
  check(std::abs(shortestLongitude(179,-179)-2)<.01,"antimeridian");
  Camera unwrapped;
  unwrapped.center={181,0};unwrapped.zoom=4;
  auto seamCenter=project({-179,0},unwrapped,800,600);
  check(std::abs(seamCenter.x-400)<.01&&std::abs(seamCenter.y-300)<.01,
        "unwrapped native camera 181° stays geographically centered at -179°");
  auto target=fit(shape.bounds,800,600);
  check(target.zoom>0&&target.zoom<=50,"region fit");
  Surface canvas(800,600);canvas.clear({0,0,0,0});
  drawGeometry(canvas,shape,camera,{201,42,42,255},{212,175,55,255},2,1);
  check(canvas.pixel(400,300).a>0,"Rio polygon fill");
  check(canvas.pixel(0,0).a==0,"unrelated alpha preserved");
  RegionStyle style;
  style.fill={130,150,164,255};
  style.stroke={215,224,231,255};
  style.strokeWidth=3;
  style.strokeProgress=0;
  Surface r0(800,600);r0.clear({0,0,0,0});
  drawRegion(r0,shape,camera,style);
  auto interior0=r0.pixel(400,300);
  style.strokeProgress=1;
  Surface r1(800,600);r1.clear({0,0,0,0});
  drawRegion(r1,shape,camera,style);
  check(r0.rgba!=r1.rgba,"Stroke Progress adds outline pixels");
  check(r1.pixel(400,300).r==interior0.r,
        "Border Draw cannot recolor Region Fill");
  style.highlightStrength=1;
  style.highlight={255,0,0,255};
  Surface highlighted(800,600);highlighted.clear({0,0,0,0});
  drawRegion(highlighted,shape,camera,style);
  check(highlighted.pixel(400,300).r>r1.pixel(400,300).r,
        "Highlight Pulse has an actual pixel effect");
  style.fillAlpha=0;style.strokeAlpha=0;
  Surface hidden(800,600);hidden.clear({0,0,0,0});
  drawRegion(hidden,shape,camera,style);
  check(hidden.pixel(400,300).a==0,"Fill and stroke alpha independent");
  auto original=canvas.rgba;
  RouteOptions route;route.from={-44.7,-24.8};route.to={-43.5,-22.5};
  route.curvature=20;route.progress=.5;route.arrowhead=true;
  drawRoute(canvas,camera,route);
  check(original!=canvas.rgba,"route appears at partial reveal");
  Surface straight(800,600),curved(800,600),withWaypoint(800,600),reversed(800,600);
  straight.clear({0,0,0,0});curved.clear({0,0,0,0});
  withWaypoint.clear({0,0,0,0});reversed.clear({0,0,0,0});
  route.progress=1;route.curvature=80;route.curved=false;
  drawRoute(straight,camera,route);
  route.curved=true;drawRoute(curved,camera,route);
  check(straight.rgba!=curved.rgba,
        "Straight and Curved routes have distinct geometry");
  route.waypoints.push_back({-44.9,-22.7});
  drawRoute(withWaypoint,camera,route);
  check(withWaypoint.rgba!=curved.rgba,
        "ordered geographic waypoints affect pixels");
  route.reverseArrowhead=true;
  drawRoute(reversed,camera,route);
  check(reversed.rgba!=withWaypoint.rgba,
        "Reverse arrowhead points towards origin without swapping endpoints");
  Surface seam(800,600);seam.clear({0,0,0,0});
  Camera seamCamera;seamCamera.center={179,0};seamCamera.zoom=12;
  RouteOptions seamRoute;seamRoute.from={179.5,0};seamRoute.to={-179.5,0};
  seamRoute.width=5;
  drawRoute(seam,seamCamera,seamRoute);
  check(seam.pixel(425,300).a>0,
        "antimeridian endpoints use shortest screen-space arc");
  MarkerOptions marker;marker.at={-44,-23.5};marker.ring=true;
  drawMarker(canvas,camera,marker);
  check(canvas.pixel(400,300).a>0,"marker centered on geoanchor");
  LabelOptions label;
  label.at={-44,-23.5};label.text="São Paulo";
  label.fontSize=32;label.halo=true;label.haloWidth=2;
  auto beforeLabel=canvas.rgba;
  drawLabel(canvas,camera,label);
  check(canvas.rgba!=beforeLabel,"georeferenced Unicode text label renders");
  label.fontSize=-1;bool badLabel=false;
  try{drawLabel(canvas,camera,label);}
  catch(const std::invalid_argument&){badLabel=true;}
  check(badLabel,"label rejects invalid font size");
  bool refused=false;
  try{
    auto wrong=route;wrong.trimStart=.9;wrong.trimEnd=.4;
    drawRoute(canvas,camera,wrong);
  }catch(const std::invalid_argument&){refused=true;}
  check(refused,"conflicting trim rejected");
  std::filesystem::remove_all(folder);
  std::cout<<"PASS geo: CRG1 reader, typed search, projection, fit, region, route, alpha\n";
  return 0;
 }catch(const std::exception&e){
  std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;
 }
}
