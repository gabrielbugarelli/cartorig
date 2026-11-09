// OpenFX descriptor and parameter-event integration, with a strict mock host.
// This is NOT the DaVinci Resolve Studio 20 host certification.
#include <ofxCore.h>
#include <ofxImageEffect.h>
#include <ofxParam.h>
#include <ofxProperty.h>
#include <cstdarg>
#include <cmath>
#include <iostream>
#include <memory>
#include <map>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#include <filesystem>
#include <fstream>
#include <cstdint>
#include <cstdlib>
#include <array>

extern "C" int OfxGetNumberOfPlugins(void);
extern "C" OfxPlugin* OfxGetPlugin(int);

namespace {
void check(bool ok,const std::string&msg){if(!ok)throw std::runtime_error(msg);}
struct Props {
 std::unordered_map<std::string,std::vector<std::string>> strings;
 std::unordered_map<std::string,std::vector<int>> integers;
 std::unordered_map<std::string,std::vector<double>> doubles;
 std::unordered_map<std::string,std::vector<void*>> pointers;
};
template<typename V>void put(std::unordered_map<std::string,std::vector<V>>&m,
                             const char*key,int index,V v){
 if(!key||index<0||index>10000)throw std::runtime_error("Invalid host property dimension");
 auto&values=m[key];if(values.size()<=static_cast<std::size_t>(index))
  values.resize(static_cast<std::size_t>(index)+1);
 values[static_cast<std::size_t>(index)]=std::move(v);
}
template<typename V>const V*find(const std::unordered_map<std::string,std::vector<V>>&m,
                                const char*key,int index){
 auto it=m.find(key?key:"");if(it==m.end()||index<0||
    static_cast<std::size_t>(index)>=it->second.size())return nullptr;
 return &it->second[static_cast<std::size_t>(index)];
}
OfxStatus setString(OfxPropertySetHandle h,const char*k,int i,const char*v){
 try{put(reinterpret_cast<Props*>(h)->strings,k,i,std::string(v?v:""));return kOfxStatOK;}
 catch(...){return kOfxStatFailed;}
}
OfxStatus setInt(OfxPropertySetHandle h,const char*k,int i,int v){
 try{put(reinterpret_cast<Props*>(h)->integers,k,i,v);return kOfxStatOK;}
 catch(...){return kOfxStatFailed;}
}
OfxStatus setDouble(OfxPropertySetHandle h,const char*k,int i,double v){
 try{put(reinterpret_cast<Props*>(h)->doubles,k,i,v);return kOfxStatOK;}
 catch(...){return kOfxStatFailed;}
}
OfxStatus getString(OfxPropertySetHandle h,const char*k,int i,char**out){
 if(auto v=find(reinterpret_cast<Props*>(h)->strings,k,i)){
  *out=const_cast<char*>(v->c_str());return kOfxStatOK;
 }return kOfxStatErrUnknown;
}
OfxStatus getInt(OfxPropertySetHandle h,const char*k,int i,int*out){
 if(auto v=find(reinterpret_cast<Props*>(h)->integers,k,i)){
  *out=*v;return kOfxStatOK;
 }return kOfxStatErrUnknown;
}
OfxStatus getDouble(OfxPropertySetHandle h,const char*k,int i,double*out){
 if(auto v=find(reinterpret_cast<Props*>(h)->doubles,k,i)){
  *out=*v;return kOfxStatOK;
 }return kOfxStatErrUnknown;
}
OfxStatus getPointer(OfxPropertySetHandle h,const char*k,int i,void**out){
 if(auto v=find(reinterpret_cast<Props*>(h)->pointers,k,i)){
  *out=*v;return kOfxStatOK;
 }return kOfxStatErrUnknown;
}

struct TestParam {
 std::string type;
 Props props;
 std::map<double,std::vector<double>> keys;
};
struct TestParams {
 Props props;
 std::unordered_map<std::string,std::unique_ptr<TestParam>> params;
};
struct TestImage {
 Props props;
 std::vector<uint8_t> pixels;
 int width=0,height=0;
 TestImage(int w,int h,uint8_t alpha=0):pixels(static_cast<std::size_t>(w)*h*4,0),
         width(w),height(h){
  for(std::size_t i=3;i<pixels.size();i+=4)pixels[i]=alpha;
  for(int i=0;i<4;++i){
   put(props.integers,kOfxImagePropBounds,i,
       i==2?width:i==3?height:0);
  }
  put(props.integers,kOfxImagePropRowBytes,0,w*4);
  put(props.pointers,kOfxImagePropData,0,static_cast<void*>(pixels.data()));
  put(props.strings,kOfxImageEffectPropPixelDepth,0,std::string(kOfxBitDepthByte));
  put(props.strings,kOfxImageEffectPropPreMultiplication,0,
      std::string(kOfxImageUnPreMultiplied));
 }
};
struct TestEffect {
 Props props;
 TestParams params;
 std::unordered_map<std::string,std::unique_ptr<Props>> clips;
 std::unordered_map<std::string,std::unique_ptr<TestImage>> images;
};
OfxStatus define(OfxParamSetHandle h,const char*type,const char*name,
                 OfxPropertySetHandle*out){
 auto&ps=*reinterpret_cast<TestParams*>(h);
 auto p=std::make_unique<TestParam>();p->type=type;
 auto*raw=p.get();ps.params[name]=std::move(p);
 *out=reinterpret_cast<OfxPropertySetHandle>(&raw->props);
 return kOfxStatOK;
}
OfxStatus paramSetProps(OfxParamSetHandle h,OfxPropertySetHandle*out){
 *out=reinterpret_cast<OfxPropertySetHandle>(
     &reinterpret_cast<TestParams*>(h)->props);return kOfxStatOK;
}
OfxStatus paramHandle(OfxParamSetHandle h,const char*name,OfxParamHandle*out,
                       OfxPropertySetHandle*properties){
 auto&map=reinterpret_cast<TestParams*>(h)->params;
 auto it=map.find(name);
 if(it==map.end())return kOfxStatErrBadHandle;
 *out=reinterpret_cast<OfxParamHandle>(it->second.get());
 if(properties)*properties=reinterpret_cast<OfxPropertySetHandle>(
     &it->second->props);
 return kOfxStatOK;
}
std::vector<double> defaultValue(const TestParam&p){
 const auto&d=p.props;
 if(p.type==kOfxParamTypeRGBA){
  std::vector<double> out(4,0);
  for(int i=0;i<4;++i)if(auto v=find(d.doubles,kOfxParamPropDefault,i))out[i]=*v;
  return out;
 }
 if(p.type==kOfxParamTypeDouble){
  if(auto v=find(d.doubles,kOfxParamPropDefault,0))return {*v};
 }
 if(p.type==kOfxParamTypeChoice||p.type==kOfxParamTypeBoolean){
  if(auto v=find(d.integers,kOfxParamPropDefault,0))return {static_cast<double>(*v)};
 }
 return {0};
}
std::vector<double> valueAt(const TestParam&p,double time){
 auto it=p.keys.upper_bound(time);
 if(it!=p.keys.begin())return std::prev(it)->second;
 return defaultValue(p);
}
OfxStatus getParamAt(OfxParamHandle h,OfxTime time,...){
 auto&p=*reinterpret_cast<TestParam*>(h);
 auto values=valueAt(p,time);
 va_list ap;va_start(ap,time);
 if(p.type==kOfxParamTypeDouble){
  auto*out=va_arg(ap,double*);*out=values[0];
 }else if(p.type==kOfxParamTypeRGBA){
  for(int i=0;i<4;++i){
   auto*out=va_arg(ap,double*);*out=values[static_cast<std::size_t>(i)];
  }
 }else if(p.type==kOfxParamTypeBoolean||p.type==kOfxParamTypeChoice){
  auto*out=va_arg(ap,int*);*out=static_cast<int>(values[0]);
 }else if(p.type==kOfxParamTypeString){
  auto*out=va_arg(ap,char**);
  const auto*v=find(p.props.strings,kOfxParamPropDefault,0);
  *out=const_cast<char*>(v?v->c_str():"");
 }else return kOfxStatFailed;
 va_end(ap);return kOfxStatOK;
}
OfxStatus setParamAt(OfxParamHandle h,OfxTime time,...){
 auto&p=*reinterpret_cast<TestParam*>(h);
 va_list ap;va_start(ap,time);
 if(p.type==kOfxParamTypeDouble){
  p.keys[time]={va_arg(ap,double)};
 }else if(p.type==kOfxParamTypeRGBA){
  std::vector<double> values;
  for(int i=0;i<4;++i)values.push_back(va_arg(ap,double));
  p.keys[time]=std::move(values);
 }else if(p.type==kOfxParamTypeBoolean||p.type==kOfxParamTypeChoice){
  p.keys[time]={static_cast<double>(va_arg(ap,int))};
 }else return kOfxStatFailed;
 va_end(ap);return kOfxStatOK;
}
OfxStatus numKeys(OfxParamHandle h,unsigned int*n){
 *n=static_cast<unsigned int>(reinterpret_cast<TestParam*>(h)->keys.size());
 return kOfxStatOK;
}
OfxStatus keyTime(OfxParamHandle h,unsigned int n,OfxTime*t){
 const auto&keys=reinterpret_cast<TestParam*>(h)->keys;
 if(n>=keys.size())return kOfxStatErrBadIndex;
 auto it=keys.begin();std::advance(it,n);
 *t=it->first;return kOfxStatOK;
}
OfxStatus deleteKey(OfxParamHandle h,OfxTime t){
 auto&keys=reinterpret_cast<TestParam*>(h)->keys;
 return keys.erase(t)?kOfxStatOK:kOfxStatFailed;
}
OfxStatus editBegin(OfxParamSetHandle,const char*){return kOfxStatOK;}
OfxStatus editEnd(OfxParamSetHandle){return kOfxStatOK;}
OfxStatus effectProps(OfxImageEffectHandle h,OfxPropertySetHandle*out){
 *out=reinterpret_cast<OfxPropertySetHandle>(
    &reinterpret_cast<TestEffect*>(h)->props);return kOfxStatOK;
}
OfxStatus effectParams(OfxImageEffectHandle h,OfxParamSetHandle*out){
 *out=reinterpret_cast<OfxParamSetHandle>(
    &reinterpret_cast<TestEffect*>(h)->params);return kOfxStatOK;
}
OfxStatus clipDefine(OfxImageEffectHandle h,const char*name,OfxPropertySetHandle*out){
 auto&e=*reinterpret_cast<TestEffect*>(h);
 auto v=std::make_unique<Props>();auto*raw=v.get();
 e.clips[name]=std::move(v);*out=reinterpret_cast<OfxPropertySetHandle>(raw);
 return kOfxStatOK;
}
OfxStatus clipHandle(OfxImageEffectHandle h,const char*name,
                     OfxImageClipHandle*out,OfxPropertySetHandle*props){
 auto&images=reinterpret_cast<TestEffect*>(h)->images;
 auto it=images.find(name?name:"");
 if(it==images.end())return kOfxStatErrBadHandle;
 *out=reinterpret_cast<OfxImageClipHandle>(it->second.get());
 if(props)*props=reinterpret_cast<OfxPropertySetHandle>(&it->second->props);
 return kOfxStatOK;
}
OfxStatus clipImage(OfxImageClipHandle h,OfxTime,const OfxRectD*,
                    OfxPropertySetHandle*out){
 *out=reinterpret_cast<OfxPropertySetHandle>(
       &reinterpret_cast<TestImage*>(h)->props);
 return kOfxStatOK;
}
OfxStatus clipRelease(OfxPropertySetHandle){return kOfxStatOK;}
OfxStatus clipProps(OfxImageClipHandle h,OfxPropertySetHandle*out){
 *out=reinterpret_cast<OfxPropertySetHandle>(
       &reinterpret_cast<TestImage*>(h)->props);
 return kOfxStatOK;
}
OfxPropertySuiteV1 properties{};
OfxParameterSuiteV1 parameters{};
OfxImageEffectSuiteV1 effects{};
Props hostProps;
const void*fetchSuite(OfxPropertySetHandle,const char*name,int version){
 if(version!=1)return nullptr;
 const std::string wanted=name;
 if(wanted==kOfxPropertySuite)return &properties;
 if(wanted==kOfxParameterSuite)return &parameters;
 if(wanted==kOfxImageEffectSuite)return &effects;
 return nullptr;
}
OfxHost host{};
void setup(){
 properties.propSetString=&setString;properties.propSetInt=&setInt;
 properties.propSetDouble=&setDouble;
 properties.propGetString=&getString;properties.propGetInt=&getInt;
 properties.propGetDouble=&getDouble;
 properties.propGetPointer=&getPointer;
 parameters.paramDefine=&define;
 parameters.paramSetGetPropertySet=&paramSetProps;
 parameters.paramGetHandle=&paramHandle;
 parameters.paramGetValueAtTime=&getParamAt;
 parameters.paramSetValueAtTime=&setParamAt;
 parameters.paramGetNumKeys=&numKeys;
 parameters.paramGetKeyTime=&keyTime;
 parameters.paramDeleteKey=&deleteKey;
 parameters.paramEditBegin=&editBegin;
 parameters.paramEditEnd=&editEnd;
 effects.getPropertySet=&effectProps;
 effects.getParamSet=&effectParams;
 effects.clipDefine=&clipDefine;
 effects.clipGetHandle=&clipHandle;
 effects.clipGetImage=&clipImage;
 effects.clipReleaseImage=&clipRelease;
 effects.clipGetPropertySet=&clipProps;
 host.host=reinterpret_cast<OfxPropertySetHandle>(&hostProps);
 host.fetchSuite=&fetchSuite;
}
TestParam&get(TestEffect&e,const char*name){
 return *e.params.params.at(name);
}
void select(TestEffect&e,const char*name,int index){
 auto&p=get(e,name);
 put(p.props.integers,kOfxParamPropDefault,0,index);
}
void chooseValue(TestEffect&e,const char*name,double v){
 auto&p=get(e,name);
 put(p.props.doubles,kOfxParamPropDefault,0,v);
}
void event(OfxPlugin*plugin,TestEffect&effect,int frame){
 Props args;
 put(args.strings,kOfxPropName,0,std::string("ApplyMotion"));
 put(args.strings,kOfxPropChangeReason,0,std::string(kOfxChangeUserEdited));
 put(args.doubles,kOfxPropTime,0,static_cast<double>(frame));
 auto st=plugin->mainEntry(kOfxActionInstanceChanged,&effect,reinterpret_cast<OfxPropertySetHandle>(&args),nullptr);
 check(st==kOfxStatOK,std::string(plugin->pluginIdentifier)+" ApplyMotion failed");
}
void assertKey(const TestEffect&e,const char*channel,double time,double expected){
 const auto&keys=e.params.params.at(channel)->keys;
 auto it=keys.find(time);
 check(it!=keys.end(),std::string(channel)+" missing native key at frame "+
       std::to_string(static_cast<int>(time)));
 check(std::abs(it->second.at(0)-expected)<1e-8,
       std::string(channel)+" key value disagrees with product contract");
}
void assertPage(const TestEffect&e){
 const auto&order=e.params.props.strings.at(kOfxPluginPropParamPageOrder);
 check(order.size()==2&&order[0]=="ControlPage"&&order[1]=="MotionPage",
       "Inspector Control/Motion page order is not explicit");
 const auto&control=e.params.params.at("ControlPage")->props.strings.at(
                      kOfxParamPropPageChild);
 const auto&motion=e.params.params.at("MotionPage")->props.strings.at(
                      kOfxParamPropPageChild);
 check(!control.empty()&&!motion.empty(),"Both Inspector pages must have children");
}
} // namespace
int main(){
 try{
  setup();
  check(OfxGetNumberOfPlugins()==6,"six native CartoRig Fusion effect types");
  std::unordered_map<std::string,OfxPlugin*> pluginByName;
  for(int i=0;i<OfxGetNumberOfPlugins();++i){
   auto*p=OfxGetPlugin(i);
   check(p!=nullptr,"missing plugin descriptor");
   p->setHost(&host);
   check(p->mainEntry(kOfxActionLoad,nullptr,nullptr,nullptr)==kOfxStatOK,
         "host must load original OFX plugin");
   TestEffect effect;
   check(p->mainEntry(kOfxActionDescribe,&effect,nullptr,nullptr)==kOfxStatOK,
         "describe plugin and supported contexts");
   check(p->mainEntry(kOfxImageEffectActionDescribeInContext,
                      &effect,nullptr,nullptr)==kOfxStatOK,
         "define type-specific Control/Motion pages");
   assertPage(effect);
   Props preferences;
   check(p->mainEntry(kOfxImageEffectActionGetClipPreferences,
                      &effect,nullptr,
                      reinterpret_cast<OfxPropertySetHandle>(&preferences))==kOfxStatOK,
         "OFX clip preferences action must declare transparent RGBA");
   check(preferences.strings.at(kOfxImageEffectPropPreMultiplication).at(0)
         ==kOfxImageUnPreMultiplied,
         "OFX output must explicitly advertise straight alpha for antialias");
   pluginByName[p->pluginIdentifier]=p;
  }
  auto*region=pluginByName.at("com.cartorig.fusionrc1.region");
  TestEffect r;
  check(region->mainEntry(kOfxImageEffectActionDescribeInContext,
                          &r,nullptr,nullptr)==kOfxStatOK,"region controls");
  select(r,"MotionPreset",5);  // Highlight Pulse
  event(region,r,100);
  assertKey(r,"HighlightStrength",100,0);
  assertKey(r,"HighlightStrength",109,.35);
  assertKey(r,"HighlightStrength",118,0);
  assertKey(r,"HighlightStrength",127,.35);
  assertKey(r,"HighlightStrength",136,0);
  const auto count=r.params.params.at("HighlightStrength")->keys.size();
  Props args;put(args.strings,kOfxPropName,0,std::string("ApplyMotion"));
  put(args.strings,kOfxPropChangeReason,0,std::string(kOfxChangeUserEdited));
  put(args.doubles,kOfxPropTime,0,100.);
  check(region->mainEntry(kOfxActionInstanceChanged,&r,reinterpret_cast<OfxPropertySetHandle>(&args),nullptr)==
        kOfxStatFailed,"second Apply must detect collision");
  check(r.params.params.at("HighlightStrength")->keys.size()==count,
        "conflicting Apply cannot erase prior native keys");
  TestEffect categorical;
  check(region->mainEntry(kOfxImageEffectActionDescribeInContext,
                          &categorical,nullptr,nullptr)==kOfxStatOK,
        "categorical region setup");
  select(categorical,"MotionPreset",3);
  event(region,categorical,330);
  assertKey(categorical,"Fill",329,130./255);
  assertKey(categorical,"Fill",330,212./255);
  auto*map=pluginByName.at("com.cartorig.fusionrc1.map");
  TestEffect m;
  check(map->mainEntry(kOfxImageEffectActionDescribeInContext,
                       &m,nullptr,nullptr)==kOfxStatOK,"map controls");
  select(m,"LayerFadeTarget",3);
  event(map,m,100);
  assertKey(m,"CountryBorderLayerOpacity",100,0);
  assertKey(m,"CountryBorderLayerOpacity",118,1);
  check(m.params.params.at("OceanLayerOpacity")->keys.empty()&&
        m.params.params.at("LandLayerOpacity")->keys.empty()&&
        m.params.params.at("LayerOpacity")->keys.empty(),
        "Layer Fade must not change other base layers (QA-40)");
  auto*camera=pluginByName.at("com.cartorig.fusionrc1.camera");
  TestEffect flight;
  check(camera->mainEntry(kOfxImageEffectActionDescribeInContext,
                          &flight,nullptr,nullptr)==kOfxStatOK,"camera controls");
  select(flight,"MotionPreset",0);
  chooseValue(flight,"CenterLongitude",179);
  chooseValue(flight,"MotionTargetLongitude",-179);
  chooseValue(flight,"MotionTargetLatitude",0);
  chooseValue(flight,"MotionTargetZoom",4);
  event(camera,flight,100);
  assertKey(flight,"CenterLongitude",145,181);
  check(flight.params.params.at("Bearing")->keys.empty(),
        "Fly To preserves Camera Bearing unless user opts into rotation");
  std::cout<<"PASS OpenFX mock: all 6 host plugin descriptors, pages, "
           <<"native Highlight Pulse, Instant Color, Layer Fade and conflicts\n";
  return 0;
 }catch(const std::exception&e){
  std::cerr<<"FAIL OFX MOCK: "<<e.what()<<"\n";return 1;
 }
}
