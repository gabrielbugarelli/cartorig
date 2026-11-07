#include "natural_earth_geometry.hpp"
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
using namespace cartorig;
static int passed=0,failed=0;
void check(bool ok,const char *what){
  if(ok)++passed;else{++failed;std::cerr<<"FAILED "<<what<<"\n";}
}
void reject(const std::vector<unsigned char>&binary,const char*what){
  try{(void)decodeGeoPackageGeometry(binary.data(),binary.size());check(false,what);}
  catch(const std::invalid_argument&){check(true,what);}
}
void put32(std::vector<unsigned char>&b,std::uint32_t value,bool little=true){
  for(int i=0;i<4;++i){
    const int shift=(little?i:3-i)*8;
    b.push_back(static_cast<unsigned char>((value>>shift)&255));
  }
}
void put64(std::vector<unsigned char>&b,double value,bool little=true){
  std::uint64_t bits;
  std::memcpy(&bits,&value,8);
  for(int i=0;i<8;++i){
    const int shift=(little?i:7-i)*8;
    b.push_back(static_cast<unsigned char>((bits>>shift)&255));
  }
}
void point(std::vector<unsigned char>&b,double lon,double lat,bool little=true){
  put64(b,lon,little);put64(b,lat,little);
}
std::vector<unsigned char>header(bool little=true,int envelope=0){
  std::vector<unsigned char>b{'G','P',0,static_cast<unsigned char>((envelope<<1)|(little?1:0))};
  put32(b,4326,little);
  for(int i=0;i<(envelope==1?4:0);++i)put64(b,i*.25,little);
  return b;
}
void polygonWKB(std::vector<unsigned char>&b,bool little=true){
  b.push_back(little?1:0);put32(b,3,little);put32(b,1,little);
  put32(b,5,little);
  point(b,-50,-20,little);point(b,-40,-20,little);
  point(b,-40,-10,little);point(b,-50,-10,little);
  point(b,-50,-20,little);
}
int main(){
  {
    auto b=header();polygonWKB(b);
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.srsId==4326&&g.polygons.size()==1&&g.polygons[0].rings.size()==1,
          "little endian polygon");
    check(g.polygons[0].rings[0].size()==5&&
          g.polygons[0].rings[0][0].lon==-50,
          "polygon rings retain coordinates");
    auto shorter=b;shorter.pop_back();reject(shorter,"truncated polygon rejected");
    auto extra=b;extra.push_back(1);reject(extra,"trailing bytes rejected");
  }
  {
    auto b=header(false,1);polygonWKB(b,false);
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.polygons.size()==1&&g.polygons[0].rings[0][1].lon==-40,
          "big endian GPKG with envelope and big endian WKB");
  }
  {
    auto b=header();b.push_back(1);put32(b,6);put32(b,2);
    polygonWKB(b);polygonWKB(b);
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.polygons.size()==2,"multipart country geometry");
  }
  {
    auto b=header();b.push_back(1);put32(b,2);put32(b,3);
    point(b,0,0);point(b,20,1);point(b,40,4);
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.lines.size()==1&&g.lines[0].size()==3,
          "rivers and roads LineString");
  }
  {
    auto b=header();b.push_back(1);put32(b,1);point(b,-46.633,-23.5505);
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.points.size()==1&&std::abs(g.points[0].lat+23.5505)<1e-9,
          "city point retained without inventing municipality polygon");
  }
  {
    auto b=header();b.push_back(1);put32(b,1001);
    point(b,13,52);put64(b,105.5);
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.points.size()==1&&g.points[0].lat==52,
          "3D WKB coordinates preserve geographic location");
  }
  {
    auto b=header();b.push_back(1);put32(b,1);
    point(b,std::numeric_limits<double>::quiet_NaN(),0);
    reject(b,"non-finite longitude rejected");
  }
  {
    auto b=header();b[4]=0;b[5]=0;b[6]=0;b[7]=0;
    b.push_back(1);put32(b,1);point(b,0,0);
    reject(b,"non-WGS84 geographic SRS rejected");
  }
  {
    auto b=header();b[0]='X';b.push_back(1);put32(b,1);point(b,0,0);
    reject(b,"invalid GP magic rejected");
  }
  {
    auto b=header();b[3]|=0x10;
    auto g=decodeGeoPackageGeometry(b.data(),b.size());
    check(g.empty(),"empty GP geometry safely represented");
  }
  std::cout<<passed<<" Natural Earth geometry checks passed, "<<failed<<" failures\n";
  return failed?1:0;
}
