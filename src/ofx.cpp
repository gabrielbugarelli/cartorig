// CartoRig 1.0 Fusion rewrite — original OpenFX 1.4 adapter.
// This is a host candidate; CI export/compile is not Resolve 20 certification.
#include "cartorig/geo.hpp"
#include <ofxImageEffect.h>
#include <ofxParam.h>
#include <ofxProperty.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace {
using namespace cartorig::rc1;
enum class Type{Map,Region,Route,Marker,Camera};
OfxHost* host=nullptr;
const OfxImageEffectSuiteV1* fx=nullptr;
const OfxPropertySuiteV1* prop=nullptr;
const OfxParameterSuiteV1* param=nullptr;
std::mutex catalogMutex;
std::unique_ptr<Catalog> catalogCache;
std::filesystem::path cachePath;
std::unordered_map<std::string,std::shared_ptr<const Geometry>> geometries;
void require(bool value,const char*message){if(!value)throw std::runtime_error(message);}
std::filesystem::path installedData(){
 if(const char*path=std::getenv("CARTORIG_RC1_DATA")){
  if(*path)return std::filesystem::u8path(path);
 }
#ifdef _WIN32
 HMODULE dll=nullptr;
 GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|
                    GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                    reinterpret_cast<LPCSTR>(&installedData),&dll);
 wchar_t path[32768]{};
 auto length=GetModuleFileNameW(dll,path,32768);
 require(length>0&&length<32768,"Plugin path unavailable");
 return std::filesystem::path(std::wstring(path,length))
   .parent_path().parent_path()/"Resources"/"data";
#else
 Dl_info info{};
 require(dladdr(reinterpret_cast<const void*>(&installedData),&info)!=0,
         "Plugin path unavailable");
 return std::filesystem::path(info.dli_fname)
   .parent_path().parent_path()/"Resources"/"data";
#endif
}
const Catalog& getCatalog(){
 std::lock_guard<std::mutex> lock(catalogMutex);
 const auto root=installedData();
 if(!catalogCache||root!=cachePath){
  auto next=std::make_unique<Catalog>(root);
  geometries.clear();
  catalogCache=std::move(next);cachePath=root;
 }
 return *catalogCache;
}
std::shared_ptr<const Geometry> getGeometry(const std::string&id){
 std::lock_guard<std::mutex> lock(catalogMutex);
 auto root=installedData();
 if(!catalogCache||cachePath!=root){
  catalogCache=std::make_unique<Catalog>(root);cachePath=root;
  geometries.clear();
 }
 auto it=geometries.find(id);
 if(it!=geometries.end())return it->second;
 auto entry=std::make_shared<Geometry>(catalogCache->geometry(id));
 if(geometries.size()>256)geometries.clear();
 geometries[id]=entry;
 return entry;
}
void logFailure(const std::string&reason) noexcept{
 try{
  std::ofstream file(std::filesystem::temp_directory_path()/"cartorig-rc1-error.log",
                     std::ios::app);
  file<<reason.substr(0,500)<<"\n";
 }catch(...){}
}
void setString(OfxPropertySetHandle p,const char*k,const char*v,int i=0){
 require(prop->propSetString(p,k,i,v)==kOfxStatOK,"OFX property string failed");
}
void setInt(OfxPropertySetHandle p,const char*k,int v,int i=0){
 require(prop->propSetInt(p,k,i,v)==kOfxStatOK,"OFX property integer failed");
}
void setDouble(OfxPropertySetHandle p,const char*k,double v,int i=0){
 require(prop->propSetDouble(p,k,i,v)==kOfxStatOK,"OFX property double failed");
}
OfxPropertySetHandle def(OfxParamSetHandle ps,const char*type,
                         const char*name,const char*label,bool animate=false){
 OfxPropertySetHandle d=nullptr;
 require(param->paramDefine(ps,type,name,&d)==kOfxStatOK,"OFX parameter definition failed");
 setString(d,kOfxPropLabel,label);
 setInt(d,kOfxParamPropAnimates,animate?1:0);
 return d;
}
void number(OfxParamSetHandle ps,std::vector<std::string>&names,
            const char*name,const char*label,double initial,double min,double max,
            bool animate=true){
 auto d=def(ps,kOfxParamTypeDouble,name,label,animate);
 setDouble(d,kOfxParamPropDefault,initial);
 setDouble(d,kOfxParamPropMin,min);setDouble(d,kOfxParamPropMax,max);
 setDouble(d,kOfxParamPropDisplayMin,min);setDouble(d,kOfxParamPropDisplayMax,max);
 names.emplace_back(name);
}
void boolean(OfxParamSetHandle ps,std::vector<std::string>&names,
             const char*name,const char*label,bool initial){
 auto d=def(ps,kOfxParamTypeBoolean,name,label);
 setInt(d,kOfxParamPropDefault,initial?1:0);
 names.emplace_back(name);
}
void color(OfxParamSetHandle ps,std::vector<std::string>&names,
           const char*name,const char*label,
           double r,double g,double b,double a=1){
 auto d=def(ps,kOfxParamTypeRGBA,name,label,true);
 const std::array<double,4> rgba{r,g,b,a};
 for(int i=0;i<4;++i)setDouble(d,kOfxParamPropDefault,rgba[i],i);
 names.emplace_back(name);
}
void string(OfxParamSetHandle ps,std::vector<std::string>&names,
            const char*name,const char*label){
 auto d=def(ps,kOfxParamTypeString,name,label);
 setString(d,kOfxParamPropDefault,"");
 names.emplace_back(name);
}
void choice(OfxParamSetHandle ps,std::vector<std::string>&names,const char*name,
            const char*label,const std::vector<std::string>&options,int selected=0){
 auto d=def(ps,kOfxParamTypeChoice,name,label);
 setInt(d,kOfxParamPropDefault,selected);
 for(std::size_t i=0;i<options.size();++i)
  setString(d,kOfxParamPropChoiceOption,options[i].c_str(),static_cast<int>(i));
 names.emplace_back(name);
}
void button(OfxParamSetHandle ps,std::vector<std::string>&names,
            const char*name,const char*label){
 def(ps,kOfxParamTypePushButton,name,label);
 names.emplace_back(name);
}
void page(OfxParamSetHandle ps,const char*id,const char*label,
          const std::vector<std::string>&names){
 auto d=def(ps,kOfxParamTypePage,id,label);
 for(std::size_t i=0;i<names.size();++i)
  setString(d,kOfxParamPropPageChild,names[i].c_str(),static_cast<int>(i));
}
void commonCamera(OfxParamSetHandle ps,std::vector<std::string>&n){
 number(ps,n,"CameraLongitude","Camera Longitude",0,-180,180);
 number(ps,n,"CameraLatitude","Camera Latitude",0,-85,85);
 number(ps,n,"CameraZoom","Camera Zoom",1,.1,50);
 number(ps,n,"CameraBearing","Camera Bearing",0,-180,180);
}
std::vector<std::string> presetNames(Type type){
 switch(type){
 case Type::Map:return {"Layer Fade"};
 case Type::Region:return {"Fade In","Fade Out","Color Transition",
                            "Instant Color Change","Border Draw","Highlight Pulse"};
 case Type::Route:return {"Draw Path","Erase Path","Follow Path"};
 case Type::Marker:return {"Fade In","Pop In"};
 case Type::Camera:return {"Fly To Location","Zoom To","Fit Transition"};
 }
 return {};
}
OfxStatus describe(OfxImageEffectHandle e,Type type){
 OfxPropertySetHandle p=nullptr;
 require(fx->getPropertySet(e,&p)==kOfxStatOK,"Effect properties not found");
 const std::string label=type==Type::Map?"CartoRig Base Map":
  type==Type::Region?"CartoRig Region":type==Type::Route?"CartoRig Route":
  type==Type::Marker?"CartoRig Marker":"CartoRig Camera";
 setString(p,kOfxPropLabel,label.c_str());
 setString(p,kOfxImageEffectPropSupportedContexts,kOfxImageEffectContextFilter);
 setString(p,kOfxImageEffectPropSupportedPixelDepths,kOfxBitDepthByte,0);
 setString(p,kOfxImageEffectPropSupportedPixelDepths,kOfxBitDepthFloat,1);
 setInt(p,kOfxImageEffectPropSupportsTiles,0);
 setInt(p,kOfxImageEffectPropSupportsMultiResolution,0);
 setString(p,kOfxImageEffectPluginRenderThreadSafety,kOfxImageEffectRenderFullySafe);
 return kOfxStatOK;
}
OfxStatus describeContext(OfxImageEffectHandle e,Type type){
 OfxPropertySetHandle p=nullptr;
 require(fx->clipDefine(e,kOfxImageEffectSimpleSourceClipName,&p)==kOfxStatOK,
         "Input clip unavailable");
 setString(p,kOfxImageEffectPropSupportedComponents,kOfxImageComponentRGBA);
 require(fx->clipDefine(e,kOfxImageEffectOutputClipName,&p)==kOfxStatOK,
         "Output clip unavailable");
 setString(p,kOfxImageEffectPropSupportedComponents,kOfxImageComponentRGBA);
 OfxParamSetHandle ps=nullptr;
 require(fx->getParamSet(e,&ps)==kOfxStatOK,"Parameter set missing");
 std::vector<std::string> controls,motion;
 if(type!=Type::Camera)commonCamera(ps,controls);
 if(type==Type::Map){
  choice(ps,controls,"DisplayMode","Display Mode",
          {"Full Map","Transparent Overlay"});
  color(ps,controls,"Ocean","Ocean Fill",16./255,40./255,60./255);
  color(ps,controls,"Land","Land Fill",57./255,76./255,89./255);
  color(ps,controls,"Coastline","Coastline Color",181./255,193./255,204./255);
  number(ps,controls,"CoastlineWidth","Coastline Width (px)",1,0,12);
  color(ps,controls,"Border","Country Border Color",150./255,170./255,185./255);
  number(ps,controls,"CountryBorderWidth","Country Border Width (px)",1,0,12);
  boolean(ps,controls,"StateBorderVisible","State Borders",false);
  color(ps,controls,"StateBorder","State Border Color",130./255,149./255,164./255);
  number(ps,controls,"StateBorderWidth","State Border Width (px)",.6,0,8);
  number(ps,controls,"LayerOpacity","Base Opacity",1,0,1);
  number(ps,controls,"OceanLayerOpacity","Ocean Layer Opacity",1,0,1);
  number(ps,controls,"LandLayerOpacity","Land Layer Opacity",1,0,1);
  number(ps,controls,"CoastlineLayerOpacity","Coastline Layer Opacity",1,0,1);
  number(ps,controls,"CountryBorderLayerOpacity","Country Border Layer Opacity",1,0,1);
  number(ps,controls,"StateBorderLayerOpacity","State Border Layer Opacity",1,0,1);
  boolean(ps,controls,"Visible","Base Visible",true);
 }else if(type==Type::Region){
  string(ps,controls,"FeatureId","Publisher Region ID");
  color(ps,controls,"Fill","Fill",.79,.165,.165);
  color(ps,controls,"Stroke","Stroke",.83,.69,.22);
  number(ps,controls,"StrokeWidth","Stroke Width (px)",1.5,0,32);
  number(ps,controls,"StrokeProgress","Stroke Progress",1,0,1);
  number(ps,controls,"HighlightStrength","Highlight Strength",0,0,1);
  color(ps,controls,"HighlightColor","Highlight Color",.9,.77,.42);
 }else if(type==Type::Route){
  number(ps,controls,"FromLongitude","From Longitude",-47.88,-180,180,false);
  number(ps,controls,"FromLatitude","From Latitude",-15.79,-85,85,false);
  number(ps,controls,"ToLongitude","To Longitude",-51.3,-180,180,false);
  number(ps,controls,"ToLatitude","To Latitude",.7,-85,85,false);
  color(ps,controls,"Stroke","Stroke Color",.84,.875,.902);
  number(ps,controls,"StrokeWidth","Stroke Width (px)",3,0,32);
  number(ps,controls,"Curvature","Curvature",0,-100,100,false);
  number(ps,controls,"DrawProgress","Draw Progress",1,0,1);
  number(ps,controls,"TrimStart","Trim Start",0,0,1);
  number(ps,controls,"TrimEnd","Trim End",1,0,1);
  boolean(ps,controls,"Arrowhead","Arrowhead",false);
  number(ps,controls,"ArrowheadSize","Arrowhead Size",12,2,64);
  number(ps,controls,"FollowerProgress","Follower Progress",0,0,1);
 }else if(type==Type::Marker){
  number(ps,controls,"PointLongitude","Point Longitude",0,-180,180,false);
  number(ps,controls,"PointLatitude","Point Latitude",0,-85,85,false);
  color(ps,controls,"Fill","Fill",.88,.91,.93);
  color(ps,controls,"Stroke","Stroke",.08,.15,.21);
  number(ps,controls,"Size","Size (px)",14,0,128);
  number(ps,controls,"StrokeWidth","Stroke Width (px)",1.5,0,16);
  number(ps,controls,"OffsetX","Offset X",0,-500,500);
  number(ps,controls,"OffsetY","Offset Y",0,-500,500);
  boolean(ps,controls,"Ring","Ring Symbol",false);
 }else if(type==Type::Camera){
  number(ps,controls,"CenterLongitude","Center Longitude",0,-180,180);
  number(ps,controls,"CenterLatitude","Center Latitude",0,-85,85);
  number(ps,controls,"Zoom","Zoom",1,.1,50);
  number(ps,controls,"Bearing","Bearing",0,-180,180);
  number(ps,controls,"FitPadding","Fit Padding",.08,0,.35,false);
 }
 if(type!=Type::Camera&&type!=Type::Map){
  number(ps,controls,"ObjectOpacity","Object Opacity",1,0,1);
  boolean(ps,controls,"Visible","Visibility",true);
 }
 choice(ps,motion,"MotionPreset","Motion Preset",presetNames(type));
 number(ps,motion,"StartFrame","Start Frame",0,0,1000000,false);
 number(ps,motion,"Delay","Delay (frames)",0,0,100000,false);
 number(ps,motion,"Duration","Duration (frames)",24,1,100000,false);
 choice(ps,motion,"Easing","Easing",{"Ease In/Out","Linear","Hold"});
 choice(ps,motion,"ConflictPolicy","Existing keys",{"Cancel","Replace affected"});
 color(ps,motion,"MotionTargetFill","Target Fill",.83,.69,.22);
 number(ps,motion,"MotionTargetOpacity","Target Opacity",1,0,1,false);
 number(ps,motion,"MotionTargetZoom","Target Zoom",4,.1,50,false);
 number(ps,motion,"MotionTargetLongitude","Target Longitude",0,-180,180,false);
 number(ps,motion,"MotionTargetLatitude","Target Latitude",0,-85,85,false);
 number(ps,motion,"MotionTargetBearing","Target Bearing",0,-180,180,false);
 number(ps,motion,"MotionTargetSize","Target Marker Size",14,0,128,false);
 button(ps,motion,"ApplyMotion","Apply Motion");
 string(ps,motion,"MotionStatus","Motion status");
 page(ps,"ControlPage","Control",controls);
 page(ps,"MotionPage","Motion",motion);
 return kOfxStatOK;
}
OfxParamHandle parameter(OfxImageEffectHandle e,const char*name){
 OfxParamSetHandle ps=nullptr;OfxParamHandle h=nullptr;
 if(fx->getParamSet(e,&ps)!=kOfxStatOK)return nullptr;
 if(param->paramGetHandle(ps,name,&h,nullptr)!=kOfxStatOK)return nullptr;
 return h;
}
double numberAt(OfxImageEffectHandle e,const char*name,double time,double fallback){
 auto h=parameter(e,name);double value=fallback;
 if(h)param->paramGetValueAtTime(h,time,&value);
 return value;
}
bool flagAt(OfxImageEffectHandle e,const char*name,double t,bool fallback){
 auto h=parameter(e,name);int value=fallback?1:0;
 if(h)param->paramGetValueAtTime(h,t,&value);
 return value!=0;
}
std::string textAt(OfxImageEffectHandle e,const char*name,double time){
 auto h=parameter(e,name);char*value=nullptr;
 if(h&&param->paramGetValueAtTime(h,time,&value)==kOfxStatOK&&value)return value;
 return "";
}
Color colorAt(OfxImageEffectHandle e,const char*name,double t,Color fallback){
 auto h=parameter(e,name);
 double components[4]={fallback.r/255.,fallback.g/255.,fallback.b/255.,fallback.a/255.};
 if(h)param->paramGetValueAtTime(h,t,&components[0],&components[1],
                                  &components[2],&components[3]);
 auto byte=[](double x){return static_cast<uint8_t>(std::clamp(std::lround(x*255),0l,255l));};
 return {byte(components[0]),byte(components[1]),byte(components[2]),byte(components[3])};
}
struct HostImage {
 OfxPropertySetHandle p=nullptr;
 OfxImageClipHandle clip=nullptr;
 int x0=0,y0=0,x1=0,y1=0,row=0;
 void*data=nullptr;
 bool isFloat=false;
 void get(OfxImageEffectHandle e,const char*clipName,double time){
  if(fx->clipGetHandle(e,clipName,&clip,nullptr)!=kOfxStatOK||!clip)return;
  if(fx->clipGetImage(clip,time,nullptr,&p)!=kOfxStatOK||!p)return;
  prop->propGetInt(p,kOfxImagePropBounds,0,&x0);
  prop->propGetInt(p,kOfxImagePropBounds,1,&y0);
  prop->propGetInt(p,kOfxImagePropBounds,2,&x1);
  prop->propGetInt(p,kOfxImagePropBounds,3,&y1);
  prop->propGetInt(p,kOfxImagePropRowBytes,0,&row);
  prop->propGetPointer(p,kOfxImagePropData,0,&data);
  char*depth=nullptr;
  prop->propGetString(p,kOfxImageEffectPropPixelDepth,0,&depth);
  isFloat=depth&&std::string(depth)==kOfxBitDepthFloat;
 }
 void release(){if(p)fx->clipReleaseImage(p);p=nullptr;}
 ~HostImage(){release();}
 bool usable()const{return p&&data&&x1>x0&&y1>y0&&row;}
 std::array<double,4> pixel(int x,int y)const{
  if(!usable()||x<x0||x>=x1||y<y0||y>=y1)return {0,0,0,0};
  const auto*bytes=static_cast<const uint8_t*>(data)+(y-y0)*row;
  if(isFloat){
   const float* v=reinterpret_cast<const float*>(bytes)+(x-x0)*4;
   return{v[0],v[1],v[2],v[3]};
  }
  const auto* v=bytes+(x-x0)*4;
  return{v[0]/255.,v[1]/255.,v[2]/255.,v[3]/255.};
 }
 void put(int x,int y,Color rgba)const{
  if(!usable()||x<x0||x>=x1||y<y0||y>=y1)return;
  auto*bytes=static_cast<uint8_t*>(data)+(y-y0)*row;
  if(isFloat){
   float* v=reinterpret_cast<float*>(bytes)+(x-x0)*4;
   v[0]=rgba.r/255.f;v[1]=rgba.g/255.f;v[2]=rgba.b/255.f;v[3]=rgba.a/255.f;
  }else{
   auto*v=bytes+(x-x0)*4;
   v[0]=rgba.r;v[1]=rgba.g;v[2]=rgba.b;v[3]=rgba.a;
  }
 }
};
OfxStatus render(OfxImageEffectHandle effect,OfxPropertySetHandle args,Type type){
 double t=0;if(args)prop->propGetDouble(args,kOfxPropTime,0,&t);
 HostImage output,source;
 output.get(effect,kOfxImageEffectOutputClipName,t);
 require(output.usable(),"OFX output image is unavailable");
 source.get(effect,kOfxImageEffectSimpleSourceClipName,t);
 const int width=output.x1-output.x0,height=output.y1-output.y0;
 Surface canvas(width,height);
 canvas.clear({0,0,0,0});
 for(int y=0;y<height;++y)for(int x=0;x<width;++x){
  auto p=source.pixel(output.x0+x,output.y1-1-y);
  canvas.blend(x,y,{
    static_cast<uint8_t>(std::clamp(std::lround(p[0]*255),0l,255l)),
    static_cast<uint8_t>(std::clamp(std::lround(p[1]*255),0l,255l)),
    static_cast<uint8_t>(std::clamp(std::lround(p[2]*255),0l,255l)),
    static_cast<uint8_t>(std::clamp(std::lround(p[3]*255),0l,255l))});
 }
 Camera camera;
 camera.center={numberAt(effect,"CameraLongitude",t,0),
                numberAt(effect,"CameraLatitude",t,0)};
 camera.zoom=numberAt(effect,"CameraZoom",t,1);
 camera.bearing=numberAt(effect,"CameraBearing",t,0);
 const double opacity=numberAt(effect,"ObjectOpacity",t,1);
 const bool enabled=flagAt(effect,"Visible",t,true);
 if(type==Type::Map){
  int displayMode=0;
  if(auto h=parameter(effect,"DisplayMode"))
   param->paramGetValueAtTime(h,t,&displayMode);
  const double baseOpacity=numberAt(effect,"LayerOpacity",t,1);
  if(displayMode==0&&flagAt(effect,"Visible",t,true)){
   auto ocean=colorAt(effect,"Ocean",t,{16,40,60,255});
   ocean.a=static_cast<uint8_t>(std::lround(ocean.a*baseOpacity*
                       numberAt(effect,"OceanLayerOpacity",t,1)));
   canvas.clear(ocean);
   auto land=colorAt(effect,"Land",t,{57,76,89,255});
   auto coast=colorAt(effect,"Coastline",t,{181,193,204,255});
   auto border=colorAt(effect,"Border",t,{150,170,185,255});
   auto stateBorder=colorAt(effect,"StateBorder",t,{130,149,164,255});
   const double landOpacity=baseOpacity*
       numberAt(effect,"LandLayerOpacity",t,1);
   const double coastOpacity=baseOpacity*
       numberAt(effect,"CoastlineLayerOpacity",t,1);
   const double countryOpacity=baseOpacity*
       numberAt(effect,"CountryBorderLayerOpacity",t,1);
   const double stateOpacity=baseOpacity*
       numberAt(effect,"StateBorderLayerOpacity",t,1);
   const auto&cat=getCatalog();
   const double coastWidth=numberAt(effect,"CoastlineWidth",t,1);
   const double countryWidth=numberAt(effect,"CountryBorderWidth",t,1);
   const double stateWidth=numberAt(effect,"StateBorderWidth",t,.6);
   for(const auto&entry:cat.all("land")){
    auto geometry=getGeometry(entry.id);
    drawGeometry(canvas,*geometry,camera,land,{0,0,0,0},0,landOpacity);
    if(coastWidth>0&&coastOpacity>0)
      drawGeometry(canvas,*geometry,camera,{0,0,0,0},coast,
                   coastWidth,coastOpacity);
   }
   if(countryWidth>0&&countryOpacity>0)
    for(const auto&entry:cat.all("country"))
     drawGeometry(canvas,*getGeometry(entry.id),camera,{0,0,0,0},border,
                   countryWidth,countryOpacity);
   if(flagAt(effect,"StateBorderVisible",t,false) &&
      stateWidth>0&&stateOpacity>0)
    for(const auto&entry:cat.all("state"))
     drawGeometry(canvas,*getGeometry(entry.id),camera,{0,0,0,0},stateBorder,
                   stateWidth,stateOpacity);
  }
 }else if(type==Type::Region&&enabled&&opacity>0){
  auto id=textAt(effect,"FeatureId",t);
  if(id.empty())throw std::invalid_argument("Region source ID is missing");
  const auto geom=getGeometry(id);
  auto fill=colorAt(effect,"Fill",t,{201,42,42,255});
  auto stroke=colorAt(effect,"Stroke",t,{212,175,55,255});
  drawGeometry(canvas,*geom,camera,fill,stroke,
               numberAt(effect,"StrokeWidth",t,1.5),opacity);
 }else if(type==Type::Route&&enabled&&opacity>0){
  RouteOptions r;
  r.from={numberAt(effect,"FromLongitude",t,0),
          numberAt(effect,"FromLatitude",t,0)};
  r.to={numberAt(effect,"ToLongitude",t,0),
        numberAt(effect,"ToLatitude",t,0)};
  r.curvature=numberAt(effect,"Curvature",t,0);
  r.width=numberAt(effect,"StrokeWidth",t,3);
  r.progress=numberAt(effect,"DrawProgress",t,1);
  r.trimStart=numberAt(effect,"TrimStart",t,0);
  r.trimEnd=numberAt(effect,"TrimEnd",t,1);
  r.arrowhead=flagAt(effect,"Arrowhead",t,false);
  r.arrowheadSize=numberAt(effect,"ArrowheadSize",t,12);
  r.stroke=colorAt(effect,"Stroke",t,{214,223,230,255});
  r.opacity=opacity;
  drawRoute(canvas,camera,r);
 }else if(type==Type::Marker&&enabled&&opacity>0){
  MarkerOptions m;
  m.at={numberAt(effect,"PointLongitude",t,0),
        numberAt(effect,"PointLatitude",t,0)};
  m.size=numberAt(effect,"Size",t,14);
  m.strokeWidth=numberAt(effect,"StrokeWidth",t,1.5);
  m.offsetX=numberAt(effect,"OffsetX",t,0);
  m.offsetY=numberAt(effect,"OffsetY",t,0);
  m.fill=colorAt(effect,"Fill",t,{224,232,237,255});
  m.stroke=colorAt(effect,"Stroke",t,{20,38,55,255});
  m.ring=flagAt(effect,"Ring",t,false);m.opacity=opacity;
  drawMarker(canvas,camera,m);
 }
 for(int y=0;y<height;++y)for(int x=0;x<width;++x)
  output.put(output.x0+x,output.y1-1-y,canvas.pixel(x,y));
 return kOfxStatOK;
}

void logFailure(const std::string&reason) noexcept;
struct KeyOperation {
 std::string channel;
 double at=0;
 bool color=false;
 std::array<double,4> rgba{0,0,0,1};
 double value=0;
};
OfxStatus applyInspectorMotion(OfxImageEffectHandle effect,
                              OfxPropertySetHandle input,Type type){
 if(!input)return kOfxStatReplyDefault;
 char *name=nullptr,*reason=nullptr;
 if(prop->propGetString(input,kOfxPropName,0,&name)!=kOfxStatOK
    ||!name||std::string(name)!="ApplyMotion")return kOfxStatReplyDefault;
 if(prop->propGetString(input,kOfxPropChangeReason,0,&reason)!=kOfxStatOK
    ||!reason||std::string(reason)!=kOfxChangeUserEdited)
  return kOfxStatReplyDefault;

 double time=0;
 prop->propGetDouble(input,kOfxPropTime,0,&time);
 int chosen=0,policy=0;
 {
  auto p=parameter(effect,"MotionPreset");
  if(!p||param->paramGetValueAtTime(p,time,&chosen)!=kOfxStatOK)
   throw std::runtime_error("Motion preset not available in Inspector");
  p=parameter(effect,"ConflictPolicy");
  if(p)param->paramGetValueAtTime(p,time,&policy);
 }
 const auto names=presetNames(type);
 require(chosen>=0&&static_cast<std::size_t>(chosen)<names.size(),
         "Invalid Motion selection");
 const auto preset=names[static_cast<std::size_t>(chosen)];
 const int start=static_cast<int>(numberAt(effect,"StartFrame",time,0))
       +static_cast<int>(numberAt(effect,"Delay",time,0));
 const int duration=static_cast<int>(numberAt(effect,"Duration",time,24));
 require(start>=0&&duration>=1&&duration<=100000&&start+duration<1000000000,
         "Invalid Motion timing");
 const double first=static_cast<double>(start),last=first+duration;
 std::vector<KeyOperation> writes;
 auto scalar=[&](const char*id,double startValue,double endValue){
  writes.push_back({id,first,false,{},startValue});
  writes.push_back({id,last,false,{},endValue});
 };
 auto pulse=[&](const char*id,double a,double peak,double b){
  writes.push_back({id,first,false,{},a});
  writes.push_back({id,first+duration*.5,false,{},peak});
  writes.push_back({id,last,false,{},b});
 };
 const auto base=[&](const char*id,double fallback){
  return numberAt(effect,id,time,fallback);
 };
 const auto opacity=base("ObjectOpacity",1.);
 if(type==Type::Map){
  scalar("LayerOpacity",0,base("LayerOpacity",1));
 }else if(type==Type::Region){
  if(chosen==0)scalar("ObjectOpacity",0,opacity);
  else if(chosen==1)scalar("ObjectOpacity",opacity,0);
  else if(chosen==2||chosen==3){
   const auto from=colorAt(effect,"Fill",time,{130,150,164,255});
   const auto target=colorAt(effect,"MotionTargetFill",time,{212,175,55,255});
   auto convert=[](Color c)->std::array<double,4>{
    return {c.r/255.,c.g/255.,c.b/255.,c.a/255.};
   };
   writes.push_back({"Fill",first,true,convert(from),0});
   writes.push_back({"Fill",chosen==3?first+1:last,true,convert(target),0});
  }else if(chosen==4)scalar("StrokeProgress",0,1);
  else if(chosen==5)pulse("HighlightStrength",0,1,0);
 }else if(type==Type::Route){
  if(chosen==0)scalar("DrawProgress",0,1);
  else if(chosen==1)scalar("DrawProgress",1,0);
  else scalar("FollowerProgress",0,1);
 }else if(type==Type::Marker){
  if(chosen==0)scalar("ObjectOpacity",0,opacity);
  else {
   const double size=base("Size",14);
   pulse("Size",0,size*1.12,size);
  }
 }else if(type==Type::Camera){
  const auto channel=[&](const char*id,const char*target){
   scalar(id,base(id,0),base(target,0));
  };
  if(chosen==0||chosen==2){
   channel("CenterLongitude","MotionTargetLongitude");
   channel("CenterLatitude","MotionTargetLatitude");
   channel("Zoom","MotionTargetZoom");
   if(chosen==0)channel("Bearing","MotionTargetBearing");
  }else channel("Zoom","MotionTargetZoom");
 }
 require(!writes.empty(),"Motion preset has no supported channels");

 // Check all affected native OFX channels BEFORE writing any key. This
 // includes manually authored keyframes that CartoRig does not own.
 std::vector<OfxParamHandle> targets;
 for(const auto&write:writes){
  auto handle=parameter(effect,write.channel.c_str());
  require(handle!=nullptr,"Motion parameter is not published");
  targets.push_back(handle);
 }
 std::vector<OfxParamHandle> unique;
 for(auto h:targets)
  if(std::find(unique.begin(),unique.end(),h)==unique.end())
   unique.push_back(h);
 for(auto h:unique){
  unsigned int count=0;
  require(param->paramGetNumKeys(h,&count)==kOfxStatOK,
          "Host cannot inspect existing native spline keys");
  for(unsigned int i=0;i<count;++i){
   OfxTime existingTime=0;
   require(param->paramGetKeyTime(h,i,&existingTime)==kOfxStatOK,
           "Host cannot inspect existing key time");
   if(existingTime>=first&&existingTime<=last&&policy==0){
    logFailure("Motion conflict: existing native keyframes. Cancelled.");
    return kOfxStatFailed;
   }
  }
 }
 OfxParamSetHandle ps=nullptr;
 require(fx->getParamSet(effect,&ps)==kOfxStatOK,"Motion param set missing");
 require(param->paramEditBegin(ps,"CartoRig Apply Motion")==kOfxStatOK,
         "Host cannot start Motion undo group");
 bool good=false;
 try{
  if(policy!=0){
   for(auto h:unique){
    unsigned int count=0;
    require(param->paramGetNumKeys(h,&count)==kOfxStatOK,
            "Cannot enumerate key collisions");
    for(int i=static_cast<int>(count)-1;i>=0;--i){
     OfxTime old=0;
     require(param->paramGetKeyTime(h,static_cast<unsigned int>(i),&old)==kOfxStatOK,
             "Cannot inspect existing spline point");
     if(old>=first&&old<=last)
      require(param->paramDeleteKey(h,old)==kOfxStatOK,
              "Cannot safely remove affected key");
    }
   }
  }
  for(std::size_t i=0;i<writes.size();++i){
   const auto&key=writes[i];
   OfxStatus status;
   if(key.color){
    status=param->paramSetValueAtTime(targets[i],key.at,
       key.rgba[0],key.rgba[1],key.rgba[2],key.rgba[3]);
   }else status=param->paramSetValueAtTime(targets[i],key.at,key.value);
   require(status==kOfxStatOK,"Host rejected Motion spline key");
  }
  good=true;
 }catch(...){
  param->paramEditEnd(ps);
  throw;
 }
 require(param->paramEditEnd(ps)==kOfxStatOK&&good,
         "Failed to close native host Motion undo group");
 return kOfxStatOK;
}
OfxStatus onLoad(){
 if(!host||!host->fetchSuite)return kOfxStatErrMissingHostFeature;
 fx=static_cast<const OfxImageEffectSuiteV1*>(host->fetchSuite(
      host->host,kOfxImageEffectSuite,1));
 prop=static_cast<const OfxPropertySuiteV1*>(host->fetchSuite(
      host->host,kOfxPropertySuite,1));
 param=static_cast<const OfxParameterSuiteV1*>(host->fetchSuite(
      host->host,kOfxParameterSuite,1));
 return fx&&prop&&param?kOfxStatOK:kOfxStatErrMissingHostFeature;
}
void setHost(OfxHost*h){host=h;}
OfxStatus action(Type type,const char*name,const void*handle,
                 OfxPropertySetHandle input,OfxPropertySetHandle){
 try{
  if(!std::strcmp(name,kOfxActionLoad))return onLoad();
  if(!std::strcmp(name,kOfxActionUnload)){
   std::lock_guard<std::mutex> lock(catalogMutex);
   catalogCache.reset();geometries.clear();return kOfxStatOK;
  }
  if(!std::strcmp(name,kOfxActionDescribe))
   return describe((OfxImageEffectHandle)handle,type);
  if(!std::strcmp(name,kOfxImageEffectActionDescribeInContext))
   return describeContext((OfxImageEffectHandle)handle,type);
  if(!std::strcmp(name,kOfxImageEffectActionRender))
   return render((OfxImageEffectHandle)handle,input,type);
  if(!std::strcmp(name,kOfxActionInstanceChanged))
   return applyInspectorMotion((OfxImageEffectHandle)handle,input,type);
  if(!std::strcmp(name,kOfxActionCreateInstance)||
     !std::strcmp(name,kOfxActionDestroyInstance))return kOfxStatOK;
  return kOfxStatReplyDefault;
 }catch(const std::exception&e){
  logFailure(e.what());return kOfxStatFailed;
 }catch(...){logFailure("Unspecified render or host error");return kOfxStatFailed;}
}
OfxStatus mapAction(const char*n,const void*h,OfxPropertySetHandle a,
                    OfxPropertySetHandle b){return action(Type::Map,n,h,a,b);}
OfxStatus regionAction(const char*n,const void*h,OfxPropertySetHandle a,
                       OfxPropertySetHandle b){return action(Type::Region,n,h,a,b);}
OfxStatus routeAction(const char*n,const void*h,OfxPropertySetHandle a,
                      OfxPropertySetHandle b){return action(Type::Route,n,h,a,b);}
OfxStatus markerAction(const char*n,const void*h,OfxPropertySetHandle a,
                       OfxPropertySetHandle b){return action(Type::Marker,n,h,a,b);}
OfxStatus cameraAction(const char*n,const void*h,OfxPropertySetHandle a,
                       OfxPropertySetHandle b){return action(Type::Camera,n,h,a,b);}
OfxPlugin plugins[]={
 {kOfxImageEffectPluginApi,1,"com.cartorig.fusionrc1.map",1,0,setHost,mapAction},
 {kOfxImageEffectPluginApi,1,"com.cartorig.fusionrc1.region",1,0,setHost,regionAction},
 {kOfxImageEffectPluginApi,1,"com.cartorig.fusionrc1.route",1,0,setHost,routeAction},
 {kOfxImageEffectPluginApi,1,"com.cartorig.fusionrc1.marker",1,0,setHost,markerAction},
 {kOfxImageEffectPluginApi,1,"com.cartorig.fusionrc1.camera",1,0,setHost,cameraAction},
};
}
extern "C" {
OfxExport int OfxGetNumberOfPlugins(void){return 5;}
OfxExport OfxPlugin*OfxGetPlugin(int index){
 if(index<0||index>=5)return nullptr;
 return &plugins[index];
}
} // extern "C"
