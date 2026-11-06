// CartoRig Native: minimal OpenFX 1.x C ABI, no Resolve private SDK.
#include "cartorig.hpp"
#include "ofx_pixel_layout.hpp"
#include "ofxCore.h"
#include "ofxImageEffect.h"
#include "ofxParam.h"
#include "ofxProperty.h"
#include "cartorig_build_info.hpp"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <fstream>
#include <sstream>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace {
OfxHost *host=nullptr;
const OfxImageEffectSuiteV1 *fx=nullptr;
const OfxPropertySuiteV1 *prop=nullptr;
const OfxParameterSuiteV1 *param=nullptr;
struct Instance {
  OfxImageClipHandle output=nullptr,source=nullptr;
  OfxParamHandle sceneFile=nullptr,datasetFile=nullptr,sceneInline=nullptr,datasetInline=nullptr;
  OfxParamHandle useSceneKeys=nullptr,lon=nullptr,lat=nullptr,zoom=nullptr,bearing=nullptr,route=nullptr,opacity=nullptr;
  OfxParamHandle frameOffset=nullptr,timeScale=nullptr,diagnosticMode=nullptr,diagnosticLog=nullptr;
  std::mutex embeddedMutex;
  std::string lastSceneText,lastDatasetText;
  std::shared_ptr<const cartorig::Scene> embeddedScene;
  std::shared_ptr<const cartorig::Dataset> embeddedDataset;
  bool overlay=false;
};
struct CacheEntry {
  std::filesystem::file_time_type modified;
  std::shared_ptr<const cartorig::Dataset> dataset;
  std::shared_ptr<const cartorig::Scene> scene;
};
std::mutex cacheMutex;
std::unordered_map<std::string,CacheEntry> cache;
std::mutex diagnosticsMutex;
std::atomic<unsigned> diagnosticsCount{0};
void writeDiagnostics(const std::string &message) noexcept {
  try {
    if(diagnosticsCount.fetch_add(1,std::memory_order_relaxed)>=300)return;
    std::lock_guard<std::mutex> lock(diagnosticsMutex);
    std::vector<std::filesystem::path> candidates;
#ifdef _WIN32
    wchar_t local[32768]{};
    DWORD localLength=GetEnvironmentVariableW(L"LOCALAPPDATA",local,32768);
    if(localLength>0&&localLength<32768)
      candidates.push_back(std::filesystem::path(local)/"CartoRigNative"/"ofx-diagnostics.log");
    wchar_t temp[32768]{};
    DWORD tempLength=GetTempPathW(32768,temp);
    if(tempLength>0&&tempLength<32768)
      candidates.push_back(std::filesystem::path(temp)/"CartoRigNative"/"ofx-diagnostics.log");
#endif
    std::error_code ec;
    auto fallback=std::filesystem::temp_directory_path(ec);
    if(!ec)candidates.push_back(fallback/"CartoRigNative"/"ofx-diagnostics.log");
    for(const auto &path:candidates) {
      ec.clear();
      std::filesystem::create_directories(path.parent_path(),ec);
      if(ec)continue;
      std::ofstream file(path,std::ios::app);
      if(file) {
        file<<std::chrono::duration_cast<std::chrono::seconds>(
          std::chrono::system_clock::now().time_since_epoch()).count()
          <<" CartoRigNative 0.2.0-dev/"<<CARTORIG_BUILD_SHA<<" "<<message<<"\n";
        file.flush();
        if(file.good())return;
      }
    }
#ifdef _WIN32
    OutputDebugStringA(("CartoRigNative: log file unavailable: "+message+"\n").c_str());
#endif
  }catch(...){
#ifdef _WIN32
    OutputDebugStringA("CartoRigNative: diagnostic logging failed unexpectedly\n");
#endif
  }
}

std::string defaultAsset(const char *filename){
  std::filesystem::path module;
#ifdef _WIN32
  HMODULE handle=nullptr;
  if(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&defaultAsset),&handle)){
    wchar_t buffer[32768];DWORD count=GetModuleFileNameW(handle,buffer,32768);
    if(count>0&&count<32768)module=std::filesystem::path(std::wstring(buffer,count));
  }
#else
  Dl_info info{};if(dladdr(reinterpret_cast<const void*>(&defaultAsset),&info)&&info.dli_fname)module=info.dli_fname;
#endif
  if(module.empty())throw std::runtime_error("Unable to locate CartoRig Native plugin bundle");
  return (module.parent_path().parent_path()/"Resources"/filename).string();
}
std::shared_ptr<const cartorig::Dataset> datasetAt(const std::string &path){
  std::lock_guard<std::mutex> lock(cacheMutex);
  const auto stamp=std::filesystem::last_write_time(path);
  auto it=cache.find("geo:"+path);
  if(it!=cache.end()&&it->second.modified==stamp&&it->second.dataset)return it->second.dataset;
  auto result=std::make_shared<cartorig::Dataset>(cartorig::parseGeoJSON(cartorig::readText(path)));
  if(cache.size()>16)cache.clear();cache["geo:"+path]={stamp,result,nullptr};return result;
}
std::shared_ptr<const cartorig::Scene> sceneAt(const std::string &path){
  std::lock_guard<std::mutex> lock(cacheMutex);
  const auto stamp=std::filesystem::last_write_time(path);
  auto it=cache.find("scene:"+path);
  if(it!=cache.end()&&it->second.modified==stamp&&it->second.scene)return it->second.scene;
  auto result=std::make_shared<cartorig::Scene>(cartorig::parseScene(cartorig::readText(path,2*1024*1024)));
  if(cache.size()>16)cache.clear();cache["scene:"+path]={stamp,nullptr,result};return result;
}
std::shared_ptr<const cartorig::Scene> embeddedSceneAt(Instance &i,const std::string &text){
  std::lock_guard<std::mutex> lock(i.embeddedMutex);
  if(i.embeddedScene&&i.lastSceneText==text)return i.embeddedScene;
  auto parsed=std::make_shared<cartorig::Scene>(cartorig::parseScene(text));
  i.lastSceneText=text;i.embeddedScene=parsed;return parsed;
}
std::shared_ptr<const cartorig::Dataset> embeddedDatasetAt(Instance &i,const std::string &text){
  std::lock_guard<std::mutex> lock(i.embeddedMutex);
  if(i.embeddedDataset&&i.lastDatasetText==text)return i.embeddedDataset;
  auto parsed=std::make_shared<cartorig::Dataset>(cartorig::parseGeoJSON(text));
  i.lastDatasetText=text;i.embeddedDataset=parsed;return parsed;
}
OfxStatus readProp(OfxPropertySetHandle set,const char *name,int index,int &value){return prop->propGetInt(set,name,index,&value);}
OfxStatus readProp(OfxPropertySetHandle set,const char *name,int index,double &value){return prop->propGetDouble(set,name,index,&value);}
Instance *instance(OfxImageEffectHandle e){OfxPropertySetHandle set=nullptr;if(fx->getPropertySet(e,&set)!=kOfxStatOK)return nullptr;Instance *p=nullptr;if(prop->propGetPointer(set,kOfxPropInstanceData,0,reinterpret_cast<void **>(&p))!=kOfxStatOK)return nullptr;return p;}
void defineDouble(OfxParamSetHandle set,const char*name,const char*label,double val,double lo,double hi){OfxPropertySetHandle p=nullptr;if(param->paramDefine(set,kOfxParamTypeDouble,name,&p)!=kOfxStatOK)throw std::runtime_error("param define");prop->propSetString(p,kOfxPropLabel,0,label);prop->propSetDouble(p,kOfxParamPropDefault,0,val);prop->propSetDouble(p,kOfxParamPropMin,0,lo);prop->propSetDouble(p,kOfxParamPropMax,0,hi);prop->propSetDouble(p,kOfxParamPropDisplayMin,0,lo);prop->propSetDouble(p,kOfxParamPropDisplayMax,0,hi);prop->propSetInt(p,kOfxParamPropAnimates,0,1);}
void defineString(OfxParamSetHandle set,const char *name,const char *label){OfxPropertySetHandle p=nullptr;if(param->paramDefine(set,kOfxParamTypeString,name,&p)!=kOfxStatOK)throw std::runtime_error("param define string");prop->propSetString(p,kOfxPropLabel,0,label);prop->propSetString(p,kOfxParamPropDefault,0,"");prop->propSetInt(p,kOfxParamPropAnimates,0,0);prop->propSetString(p,kOfxParamPropStringMode,0,kOfxParamStringIsFilePath);}
void defineMultiline(OfxParamSetHandle set,const char *name,const char *label){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(set,kOfxParamTypeString,name,&props)!=kOfxStatOK)
    throw std::runtime_error("embedded JSON parameter definition failed");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetString(props,kOfxParamPropDefault,0,"");
  prop->propSetString(props,kOfxParamPropStringMode,0,kOfxParamStringIsMultiLine);
  prop->propSetInt(props,kOfxParamPropPersistant,0,1);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
}
void defineBoolean(OfxParamSetHandle set,const char *name,const char *label,bool value){OfxPropertySetHandle p=nullptr;if(param->paramDefine(set,kOfxParamTypeBoolean,name,&p)!=kOfxStatOK)throw std::runtime_error("param define bool");prop->propSetString(p,kOfxPropLabel,0,label);prop->propSetInt(p,kOfxParamPropDefault,0,value?1:0);prop->propSetInt(p,kOfxParamPropAnimates,0,0);}
void defineVersionLabel(OfxParamSetHandle ps){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeString,"CartoRigBuildInfo",&props)!=kOfxStatOK)
    throw std::runtime_error("version label parameter failed");
  prop->propSetString(props,kOfxPropLabel,0,"Installed plugin build");
  prop->propSetString(props,kOfxParamPropStringMode,0,kOfxParamStringIsLabel);
  const std::string info=std::string("0.2.0-dev / ")+CARTORIG_BUILD_SHA;
  prop->propSetString(props,kOfxParamPropDefault,0,info.c_str());
  prop->propSetInt(props,kOfxParamPropPersistant,0,0);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
}
void defineDiagnosticChoice(OfxParamSetHandle ps){
  OfxPropertySetHandle p=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeChoice,"DiagnosticMode",&p)!=kOfxStatOK)
    throw std::runtime_error("cannot create diagnostic choice");
  prop->propSetString(p,kOfxPropLabel,0,"Diagnostic output (test only)");
  prop->propSetInt(p,kOfxParamPropDefault,0,0);
  prop->propSetInt(p,kOfxParamPropAnimates,0,0);
  const char *names[]{"Normal map","RGB bars","Grayscale ramp","Alpha split","Solid white"};
  for(int index=0;index<5;++index)
    prop->propSetString(p,kOfxParamPropChoiceOption,index,names[index]);
}
void stringAt(OfxParamHandle handle,double time,std::string &str){char *value=nullptr;if(param->paramGetValueAtTime(handle,time,&value)==kOfxStatOK&&value)str=value;}
double doubleAt(OfxParamHandle handle,double time,double fallback){double value=fallback;if(handle)param->paramGetValueAtTime(handle,time,&value);return value;}
int intAt(OfxParamHandle handle,double time,int fallback){int value=fallback;if(handle)param->paramGetValueAtTime(handle,time,&value);return value;}
OfxStatus onLoad(){if(!host||!host->fetchSuite)return kOfxStatErrMissingHostFeature;fx=reinterpret_cast<const OfxImageEffectSuiteV1*>(host->fetchSuite(host->host,kOfxImageEffectSuite,1));prop=reinterpret_cast<const OfxPropertySuiteV1*>(host->fetchSuite(host->host,kOfxPropertySuite,1));param=reinterpret_cast<const OfxParameterSuiteV1*>(host->fetchSuite(host->host,kOfxParameterSuite,1));return fx&&prop&&param?kOfxStatOK:kOfxStatErrMissingHostFeature;}
OfxStatus describe(OfxImageEffectHandle e,bool filter){OfxPropertySetHandle p=nullptr;if(fx->getPropertySet(e,&p)!=kOfxStatOK)return kOfxStatFailed;
  prop->propSetString(p,kOfxPropLabel,0,filter?"CartoRig Overlay (Edit)":"CartoRig Map (Edit)");
  prop->propSetString(p,kOfxImageEffectPluginPropGrouping,0,"CartoRig Native");
  prop->propSetString(p,kOfxImageEffectPropSupportedContexts,0,filter?kOfxImageEffectContextFilter:kOfxImageEffectContextGenerator);
  prop->propSetString(p,kOfxImageEffectPropSupportedPixelDepths,0,kOfxBitDepthByte);
  prop->propSetString(p,kOfxImageEffectPropSupportedPixelDepths,1,kOfxBitDepthFloat);
  prop->propSetInt(p,kOfxImageEffectPropSupportsTiles,0,1);
  prop->propSetInt(p,kOfxImageEffectPropTemporalClipAccess,0,0);
  return kOfxStatOK;
}
OfxStatus describeInContext(OfxImageEffectHandle e,bool filter){OfxPropertySetHandle p=nullptr;
 if(filter){if(fx->clipDefine(e,kOfxImageEffectSimpleSourceClipName,&p)!=kOfxStatOK)return kOfxStatFailed;prop->propSetString(p,kOfxImageEffectPropSupportedComponents,0,kOfxImageComponentRGBA);}
 if(fx->clipDefine(e,kOfxImageEffectOutputClipName,&p)!=kOfxStatOK)return kOfxStatFailed;
 prop->propSetString(p,kOfxImageEffectPropSupportedComponents,0,kOfxImageComponentRGBA);
 OfxParamSetHandle ps=nullptr;if(fx->getParamSet(e,&ps)!=kOfxStatOK)return kOfxStatFailed;
 defineString(ps,"SceneFile","Scene .json (blank: bundled sample)");
 defineString(ps,"CatalogFile","GeoJSON (blank: offline countries)");
 defineMultiline(ps,"EmbeddedSceneJSON","Embedded scene JSON (portable)");
 defineMultiline(ps,"EmbeddedCatalogJSON","Embedded GeoJSON (portable)");
 defineBoolean(ps,"UseSceneCamera","Use camera keyframes from scene",true);
 defineDouble(ps,"SceneTimeOffset","Scene offset (host frames)",0,-86400,86400);
 defineDouble(ps,"SceneTimeScale","Scene time scale / reverse",1,-8,8);
 defineDouble(ps,"Longitude","Camera longitude",-61,-180,180);defineDouble(ps,"Latitude","Camera latitude",-12,-85,85);defineDouble(ps,"Zoom","Camera zoom",3.2,0,18);defineDouble(ps,"Bearing","Camera bearing (degrees)",0,-360,360);
 defineDouble(ps,"RouteProgress","Route reveal (-1: scene)",-1,-1,1);defineDouble(ps,"Opacity","Cartography opacity (entire map)",filter?0.7:1,0,1);
 defineVersionLabel(ps);
 defineDiagnosticChoice(ps);defineBoolean(ps,"DiagnosticLog","Write OFX diagnostic log",false);
 return kOfxStatOK;
}
OfxStatus createInstance(OfxImageEffectHandle e,bool filter){auto i=std::make_unique<Instance>();i->overlay=filter;OfxParamSetHandle ps=nullptr;if(fx->getParamSet(e,&ps)!=kOfxStatOK)return kOfxStatFailed;
 if(fx->clipGetHandle(e,kOfxImageEffectOutputClipName,&i->output,nullptr)!=kOfxStatOK)return kOfxStatFailed;
 if(filter&&fx->clipGetHandle(e,kOfxImageEffectSimpleSourceClipName,&i->source,nullptr)!=kOfxStatOK)return kOfxStatFailed;
 for(auto t:std::vector<std::pair<const char*,OfxParamHandle*>>{{"SceneFile",&i->sceneFile},{"CatalogFile",&i->datasetFile},
 {"EmbeddedSceneJSON",&i->sceneInline},{"EmbeddedCatalogJSON",&i->datasetInline},
 {"SceneTimeOffset",&i->frameOffset},{"SceneTimeScale",&i->timeScale},
 {"UseSceneCamera",&i->useSceneKeys},{"Longitude",&i->lon},{"Latitude",&i->lat},{"Zoom",&i->zoom},{"Bearing",&i->bearing},{"RouteProgress",&i->route},{"Opacity",&i->opacity},{"DiagnosticMode",&i->diagnosticMode},{"DiagnosticLog",&i->diagnosticLog}})if(param->paramGetHandle(ps,t.first,t.second,nullptr)!=kOfxStatOK)return kOfxStatFailed;
 OfxPropertySetHandle p=nullptr;fx->getPropertySet(e,&p);if(prop->propSetPointer(p,kOfxPropInstanceData,0,i.get())!=kOfxStatOK)return kOfxStatFailed;i.release();return kOfxStatOK;
}
OfxStatus destroyInstance(OfxImageEffectHandle e){Instance *i=instance(e);if(!i)return kOfxStatOK;OfxPropertySetHandle p=nullptr;fx->getPropertySet(e,&p);prop->propSetPointer(p,kOfxPropInstanceData,0,nullptr);delete i;return kOfxStatOK;}
struct ImageLease {OfxPropertySetHandle image=nullptr;~ImageLease(){if(image)fx->clipReleaseImage(image);}ImageLease(const ImageLease&)=delete;ImageLease& operator=(const ImageLease&)=delete;ImageLease()=default;};
cartorig::Surface surfaceOf(OfxPropertySetHandle image,bool generator){cartorig::Surface s;void *buffer=nullptr;int rect[4]{},rowBytes=0;char *depth=nullptr,*components=nullptr;
 if(prop->propGetPointer(image,kOfxImagePropData,0,&buffer)!=kOfxStatOK||!buffer||prop->propGetIntN(image,kOfxImagePropBounds,4,rect)!=kOfxStatOK||prop->propGetInt(image,kOfxImagePropRowBytes,0,&rowBytes)!=kOfxStatOK||prop->propGetString(image,kOfxImageEffectPropPixelDepth,0,&depth)!=kOfxStatOK||prop->propGetString(image,kOfxImageEffectPropComponents,0,&components)!=kOfxStatOK)throw std::runtime_error("unsupported image properties");
 const auto layout=cartorig::classifyOfxLayout(
   components?components:"",depth?depth:"",rect[0],rect[1],rect[2],rect[3],
   rowBytes,generator);
 if(layout==cartorig::OfxLayout::Reject){
   std::ostringstream detail;
   detail<<"unsupported OFX image: components="<<(components?components:"missing")
         <<" depth="<<(depth?depth:"missing")
         <<" bounds="<<rect[0]<<","<<rect[1]<<","<<rect[2]<<","<<rect[3]
         <<" rowBytes="<<rowBytes;
   throw std::runtime_error(detail.str());
 }
 if(layout==cartorig::OfxLayout::Resolve20FloatRGBAUnspecified){
   static std::atomic<unsigned> warnings{0};
   if(warnings.fetch_add(1,std::memory_order_relaxed)<3)
     writeDiagnostics("COMPAT: Resolve 20 Generator returned ComponentNone with "
       "tight Float4 row. Interpreting as RGBA after validating dimensions.");
 }
 char *premult=nullptr;
 if(prop->propGetString(image,kOfxImageEffectPropPreMultiplication,0,&premult)==kOfxStatOK&&premult)
   s.premultiplied=!std::strcmp(premult,kOfxImagePreMultiplied);
 else s.premultiplied=generator;
 s.data=buffer;s.x1=rect[0];s.y1=rect[1];s.x2=rect[2];s.y2=rect[3];s.rowBytes=rowBytes;
 if(depth&&!strcmp(depth,kOfxBitDepthByte))s.format=cartorig::PixelFormat::ByteRGBA;
 else if(depth&&!strcmp(depth,kOfxBitDepthFloat))s.format=cartorig::PixelFormat::FloatRGBA;
 else throw std::runtime_error("only byte and float RGBA supported");
 const int64_t required=static_cast<int64_t>(s.x2-s.x1)*
   (s.format==cartorig::PixelFormat::ByteRGBA?4:16);
 if(s.x2<=s.x1||s.y2<=s.y1||s.rowBytes==0||
    std::abs(static_cast<int64_t>(s.rowBytes))<required)
   throw std::runtime_error("OFX image row pitch too short for RGBA format");
 return s;
}
OfxStatus render(OfxImageEffectHandle e,OfxPropertySetHandle args){Instance *i=instance(e);if(!i)return kOfxStatFailed;double time=0;if(readProp(args,kOfxPropTime,0,time)!=kOfxStatOK)return kOfxStatFailed;
 const bool diagnosticLogging=intAt(i->diagnosticLog,time,0)!=0;
 const int diagnosticMode=intAt(i->diagnosticMode,time,0);
 if(diagnosticLogging)writeDiagnostics("RENDER_BEGIN t="+std::to_string(time)+
   " mode="+std::to_string(diagnosticMode)+
   " overlay="+std::to_string(static_cast<int>(i->overlay)));
 int gpuFlag=0;
 for(const char *key:{"OfxImageEffectPropOpenCLEnabled","OfxImageEffectPropCudaEnabled","OfxImageEffectPropMetalEnabled"}){
   int enabled=0;if(prop->propGetInt(args,key,0,&enabled)==kOfxStatOK&&enabled)gpuFlag=1;
 }
 if(gpuFlag){
   if(diagnosticLogging)writeDiagnostics("GPU pointer supplied, cannot use CPU pixel writer");
   return kOfxStatErrUnsupported;
 }
 ImageLease output;
 const OfxStatus imageStatus=fx->clipGetImage(i->output,time,nullptr,&output.image);
 if(imageStatus!=kOfxStatOK||!output.image){
   if(diagnosticLogging)writeDiagnostics("ERROR clipGetImage status="+std::to_string(imageStatus));
   return kOfxStatFailed;
 }
 if(diagnosticLogging){
   int rect[4]{},rowBytes=0;char *depth=nullptr,*components=nullptr;
   auto stBounds=prop->propGetIntN(output.image,kOfxImagePropBounds,4,rect);
   auto stStride=prop->propGetInt(output.image,kOfxImagePropRowBytes,0,&rowBytes);
   auto stDepth=prop->propGetString(output.image,kOfxImageEffectPropPixelDepth,0,&depth);
   auto stComp=prop->propGetString(output.image,kOfxImageEffectPropComponents,0,&components);
   std::ostringstream msg;
   msg<<"IMAGE_RAW boundsStatus="<<stBounds<<" strideStatus="<<stStride
      <<" depthStatus="<<stDepth<<" componentsStatus="<<stComp
      <<" rect="<<rect[0]<<","<<rect[1]<<","<<rect[2]<<","<<rect[3]
      <<" rowBytes="<<rowBytes<<" depth="<<(depth?depth:"missing")
      <<" components="<<(components?components:"missing");
   writeDiagnostics(msg.str());
 }
 auto target=surfaceOf(output.image,!i->overlay);
 OfxPropertySetHandle effProps=nullptr;fx->getPropertySet(e,&effProps);double w=0,h=0,scaleX=1,scaleY=1;
 if(prop->propGetDouble(effProps,kOfxImageEffectPropProjectSize,0,&w)!=kOfxStatOK||prop->propGetDouble(effProps,kOfxImageEffectPropProjectSize,1,&h)!=kOfxStatOK) {w=target.x2;h=target.y2;}
 prop->propGetDouble(args,kOfxImageEffectPropRenderScale,0,&scaleX);prop->propGetDouble(args,kOfxImageEffectPropRenderScale,1,&scaleY);
 int width=static_cast<int>(std::round(w*scaleX)),height=static_cast<int>(std::round(h*scaleY));if(width<target.x2)width=target.x2;if(height<target.y2)height=target.y2;
 if(width<=0||height<=0||width>16384||height>16384)return kOfxStatErrValue;
 // The host may allocate a full image but request only a small RenderWindow.
 // Rendering outside that region can race other Resolve render threads.
 int window[4]{};
 if(prop->propGetIntN(args,kOfxImageEffectPropRenderWindow,4,window)!=kOfxStatOK)return kOfxStatErrValue;
 if(diagnosticLogging){
   char *depth=nullptr,*components=nullptr,*premult=nullptr;
   prop->propGetString(output.image,kOfxImageEffectPropPixelDepth,0,&depth);
   prop->propGetString(output.image,kOfxImageEffectPropComponents,0,&components);
   prop->propGetString(output.image,kOfxImageEffectPropPreMultiplication,0,&premult);
   double range[2]{-1,-1};
   const OfxStatus rangeStatus=prop->propGetDoubleN(effProps,kOfxImageEffectPropFrameRange,2,range);
   std::ostringstream msg;
   msg<<"render mode="<<diagnosticMode<<" isFilter="<<i->overlay
      <<" time="<<time<<" rangeStatus="<<rangeStatus
      <<" range="<<range[0]<<","<<range[1]
      <<" project="<<w<<"x"<<h
      <<" scale="<<scaleX<<","<<scaleY
      <<" fullView="<<width<<"x"<<height
      <<" allocationBounds="<<target.x1<<","<<target.y1<<","<<target.x2<<","<<target.y2
      <<" renderWindow="<<window[0]<<","<<window[1]<<","<<window[2]<<","<<window[3]
      <<" pitch="<<target.rowBytes
      <<" depth="<<(depth?depth:"missing")
      <<" components="<<(components?components:"missing")
      <<" premult="<<(premult?premult:"missing");
   writeDiagnostics(msg.str());
 }
 target=cartorig::cropSurface(target,window[0],window[1],window[2],window[3]);
 if(!target.data)return kOfxStatOK;
 if(diagnosticMode>0&&diagnosticMode<=4){
   // This diagnostic path must not load a scene, dataset or geographic cache.
   cartorig::renderDiagnosticPattern(target,width,height,diagnosticMode);
   return kOfxStatOK;
 }
 std::string sceneFile,datasetFile,inlineScene,inlineCatalog;
 stringAt(i->sceneFile,time,sceneFile);stringAt(i->datasetFile,time,datasetFile);
 stringAt(i->sceneInline,time,inlineScene);stringAt(i->datasetInline,time,inlineCatalog);
 if(sceneFile.empty())sceneFile=defaultAsset("brasil-venezuela.cartorig-native.json");
 if(datasetFile.empty())datasetFile=defaultAsset("countries.geojson");
 auto scene=inlineScene.empty()?sceneAt(sceneFile):embeddedSceneAt(*i,inlineScene);
 auto dataset=inlineCatalog.empty()?datasetAt(datasetFile):embeddedDatasetAt(*i,inlineCatalog);
 const double sceneFrame=cartorig::mapSceneFrame(time,
   doubleAt(i->frameOffset,time,0),doubleAt(i->timeScale,time,1));
 cartorig::View view;view.width=width;view.height=height;view.frame=sceneFrame;
 view.camera=evaluateCamera(*scene,sceneFrame);
 view.opacity=std::clamp(doubleAt(i->opacity,time,1),0.0,1.0);
 if(!intAt(i->useSceneKeys,time,1)){view.camera.lon=doubleAt(i->lon,time,view.camera.lon);view.camera.lat=doubleAt(i->lat,time,view.camera.lat);view.camera.zoom=doubleAt(i->zoom,time,view.camera.zoom);view.camera.bearing=doubleAt(i->bearing,time,view.camera.bearing);}
 view.routeProgress=doubleAt(i->route,time,-1);
 auto copy=*scene;
 ImageLease source;
 if(i->overlay){
   const OfxStatus sourceStatus=fx->clipGetImage(i->source,time,nullptr,&source.image);
   if(sourceStatus!=kOfxStatOK||!source.image){
     if(diagnosticLogging)writeDiagnostics("Overlay source unavailable: "+std::to_string(sourceStatus));
     return kOfxStatFailed;
   }
   cartorig::copySurface(surfaceOf(source.image,false),target);
   copy.style.transparent=true;
   view.preserveBackground=true;
 }
 cartorig::render(copy,*dataset,view,target);
 return kOfxStatOK;
}
OfxStatus entry(const char *action,const void *handle,OfxPropertySetHandle args,OfxPropertySetHandle out,bool filter){try {
 if(!std::strcmp(action,kOfxActionLoad))return onLoad();
 if(!std::strcmp(action,kOfxActionUnload)){std::lock_guard<std::mutex> lock(cacheMutex);cache.clear();return kOfxStatOK;}
 if(!std::strcmp(action,kOfxActionDescribe))return describe((OfxImageEffectHandle)handle,filter);
 if(!std::strcmp(action,kOfxImageEffectActionDescribeInContext))return describeInContext((OfxImageEffectHandle)handle,filter);
 if(!std::strcmp(action,kOfxActionInstanceChanged)){
   // Log activation without requiring a successful render or valid OFX image.
   char *changed=nullptr;
   if(args&&prop->propGetString(args,kOfxPropName,0,&changed)==kOfxStatOK&&
      changed&&!std::strcmp(changed,"DiagnosticLog"))
     writeDiagnostics("INSPECTOR DiagnosticLog changed; render may not have started yet");
   return kOfxStatReplyDefault;
 }
 if(!std::strcmp(action,kOfxImageEffectActionGetClipPreferences)){
   // JSON-based camera/route motion changes per frame without animating any OFX parameter.
   if(!out)return kOfxStatFailed;
   if(prop->propSetInt(out,kOfxImageEffectFrameVarying,0,1)!=kOfxStatOK)return kOfxStatFailed;
   // Explicitly request RGBA on the Output clip (OpenFX clip preferences).
   // Some Resolve 20 generator images still expose None despite this request.
   {
     const auto status=prop->propSetString(
       out,"OfxImageClipPropComponents_Output",0,kOfxImageComponentRGBA);
     if(status!=kOfxStatOK)
       writeDiagnostics("GetClipPreferences Output RGBA request not accepted: "+
         std::to_string(status));
     if(filter){
       const auto inputStatus=prop->propSetString(
         out,"OfxImageClipPropComponents_Source",0,kOfxImageComponentRGBA);
       if(inputStatus!=kOfxStatOK)
         writeDiagnostics("GetClipPreferences Source RGBA request not accepted: "+
           std::to_string(inputStatus));
     }
   }
   // Both contexts now produce premultiplied output, including translucent
   // graphics composited onto live video by the Overlay Filter.
   if(prop->propSetString(out,kOfxImageEffectPropPreMultiplication,0,kOfxImagePreMultiplied)!=kOfxStatOK)return kOfxStatFailed;
   return kOfxStatOK;
 }
 if(!std::strcmp(action,kOfxActionCreateInstance))return createInstance((OfxImageEffectHandle)handle,filter);
 if(!std::strcmp(action,kOfxActionDestroyInstance))return destroyInstance((OfxImageEffectHandle)handle);
 if(!std::strcmp(action,kOfxImageEffectActionRender))return render((OfxImageEffectHandle)handle,args);
 return kOfxStatReplyDefault;
 }catch(const std::bad_alloc&){writeDiagnostics("ERROR out-of-memory in OFX callback");return kOfxStatErrMemory;}
 catch(const std::exception &error){
   writeDiagnostics(std::string("ERROR action=")+(action?action:"(null)")+" reason="+error.what());
   std::cerr<<"CartoRig Native: "<<error.what()<<std::endl;
   return kOfxStatFailed;
 }catch(...){writeDiagnostics("ERROR unknown exception in OFX callback");return kOfxStatFailed;}}
OfxStatus generator(const char *action,const void *handle,OfxPropertySetHandle in,OfxPropertySetHandle out){return entry(action,handle,in,out,false);}
OfxStatus overlay(const char *action,const void *handle,OfxPropertySetHandle in,OfxPropertySetHandle out){return entry(action,handle,in,out,true);}
void setHost(OfxHost *h){host=h;}
OfxPlugin plugins[2]={{kOfxImageEffectPluginApi,1,"com.cartorig.native.map",0,1,setHost,generator},{kOfxImageEffectPluginApi,1,"com.cartorig.native.overlay",0,1,setHost,overlay}};
}
extern "C" {
OfxExport int OfxGetNumberOfPlugins(void){return 2;}
OfxExport OfxPlugin *OfxGetPlugin(int n){return n>=0&&n<2?&plugins[n]:nullptr;}
}
