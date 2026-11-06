#include "ofx_pixel_layout.hpp"
#include <iostream>
#include <string_view>
using namespace cartorig;
static int passed=0,failed=0;
static void check(bool yes,const char *name){
  if(yes){++passed;}else{++failed;std::cerr<<"FAILED "<<name<<"\n";}
}
int main(){
  auto test=[](std::string_view components,std::string_view depth,
               int x1,int y1,int x2,int y2,int pitch,bool generator){
    return classifyOfxLayout(components,depth,x1,y1,x2,y2,pitch,generator);
  };
  check(test("OfxImageComponentNone","OfxBitDepthFloat",0,0,1920,1080,30720,true)
        ==OfxLayout::Resolve20FloatRGBAUnspecified,"Resolve20 observed Float4 generator");
  check(test("OfxImageComponentRGBA","OfxBitDepthFloat",0,0,1920,1080,30736,true)
        ==OfxLayout::RGBA,"RGBA float padded");
  check(test("OfxImageComponentRGBA","OfxBitDepthByte",0,0,1920,1080,7680,false)
        ==OfxLayout::RGBA,"RGBA byte filter");
  check(test("OfxImageComponentNone","OfxBitDepthFloat",0,0,1920,1080,30720,false)
        ==OfxLayout::Reject,"None must not pass as filter");
  check(test("OfxImageComponentNone","OfxBitDepthByte",0,0,1920,1080,7680,true)
        ==OfxLayout::Reject,"None byte forbidden");
  check(test("OfxImageComponentNone","OfxBitDepthFloat",0,0,1920,1080,30719,true)
        ==OfxLayout::Reject,"short pitch");
  check(test("OfxImageComponentNone","OfxBitDepthFloat",0,0,1920,1080,30736,true)
        ==OfxLayout::Reject,"ambiguous padded None");
  check(test("OfxImageComponentRGB","OfxBitDepthFloat",0,0,1920,1080,30720,true)
        ==OfxLayout::Reject,"RGB is not RGBA");
  check(test("OfxImageComponentAlpha","OfxBitDepthFloat",0,0,1920,1080,30720,true)
        ==OfxLayout::Reject,"Alpha only forbidden");
  check(test("OfxImageComponentNone","OfxBitDepthFloat",0,0,1920,1080,-30720,true)
        ==OfxLayout::Reject,"negative pitch None");
  check(test("OfxImageComponentNone","OfxBitDepthFloat",0,0,0,1080,0,true)
        ==OfxLayout::Reject,"zero area");
  check(test("OfxImageComponentNone","OfxBitDepthHalf",0,0,1920,1080,15360,true)
        ==OfxLayout::Reject,"half float unsupported");
  check(test("OfxImageComponentRGBA","OfxBitDepthFloat",30,20,60,40,480,true)
        ==OfxLayout::RGBA,"valid cropped RGBA tile");
  check(test("OfxImageComponentNone","OfxBitDepthFloat",30,20,60,40,480,true)
        ==OfxLayout::Resolve20FloatRGBAUnspecified,"valid tightly packed None float tile");
  check(test("","OfxBitDepthFloat",0,0,1920,1080,30720,true)
        ==OfxLayout::Reject,"missing metadata");
  check(test("OfxImageComponentRGBA","OfxBitDepthFloat",0,0,1920,1080,6000,true)
        ==OfxLayout::Reject,"undersized canonical pitch");
  std::cout<<passed<<" layout cases passed, "<<failed<<" failures\n";
  return failed?1:0;
}
