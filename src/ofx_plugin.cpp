// CartoRig Native: minimal OpenFX 1.x C ABI, no Resolve private SDK.
#include "cartorig.hpp"
#include "native_controls.hpp"
#include "natural_earth_catalog.hpp"
#include "natural_earth_raster.hpp"
#include "natural_earth_regions.hpp"
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
  OfxParamHandle naturalEarthGpkg=nullptr,naturalEarthDetail=nullptr,naturalEarthLayer=nullptr,naturalEarthLayerFile=nullptr,naturalEarthRasterRoot=nullptr,naturalEarthRasterAsset=nullptr;
  OfxParamHandle regionCatalog=nullptr,regionKind=nullptr,regionQuery=nullptr,regionMatch=nullptr;
  OfxParamHandle regionRed=nullptr,regionGreen=nullptr,regionBlue=nullptr,regionAlpha=nullptr;
  OfxParamHandle regionAdd=nullptr,regionRemove=nullptr,regionSaved=nullptr,regionStatus=nullptr;
  OfxParamHandle useSceneKeys=nullptr,lon=nullptr,lat=nullptr,zoom=nullptr,bearing=nullptr,route=nullptr,opacity=nullptr;
  OfxParamHandle frameOffset=nullptr,timeScale=nullptr,diagnosticMode=nullptr,diagnosticLog=nullptr;
  OfxParamHandle countryA=nullptr,countryB=nullptr,countryList=nullptr,highlightStrength=nullptr;
  OfxParamHandle routeEnabled=nullptr,routeStartLon=nullptr,routeStartLat=nullptr;
  OfxParamHandle routeEndLon=nullptr,routeEndLat=nullptr,routeCurve=nullptr,routeWidth=nullptr;
  OfxParamHandle showRouteMarkers=nullptr,routeStartLabel=nullptr,routeEndLabel=nullptr;
  OfxParamHandle manualColors=nullptr,oceanR=nullptr,oceanG=nullptr,oceanB=nullptr;
  OfxParamHandle landR=nullptr,landG=nullptr,landB=nullptr;
  OfxParamHandle highlightR=nullptr,highlightG=nullptr,highlightB=nullptr;
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
// Optional typed overlay cache; keep it separate from country-only datasets.
struct VectorLayerCache {
  std::filesystem::file_time_type modified;
  std::shared_ptr<const std::vector<cartorig::NaturalEarthGeometry>> features;
};
std::unordered_map<std::string,VectorLayerCache> vectorLayerCache;
struct RasterCacheEntry {
  std::filesystem::file_time_type modified;
  std::shared_ptr<const cartorig::NaturalEarthRaster> raster;
};
std::unordered_map<std::string,RasterCacheEntry> rasterCache;
struct RegionGeometryCacheEntry {
  std::filesystem::file_time_type modified;
  std::shared_ptr<const std::vector<cartorig::NaturalEarthGeometry>> features;
};
std::unordered_map<std::string,RegionGeometryCacheEntry> regionGeometryCache;
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
          <<" CartoRigNative 0.4.0-dev/"<<CARTORIG_BUILD_SHA<<" "<<message<<"\n";
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
std::shared_ptr<const cartorig::Dataset> naturalEarthCountriesAt(
    const std::string &path,const std::string &scale){
  // Cache only immutable geometry, never the mutable per-instance scene.
  // A file update invalidates this entry, matching the existing GeoJSON cache.
  std::lock_guard<std::mutex> lock(cacheMutex);
  const auto stamp=std::filesystem::last_write_time(path);
  const auto key="ne-country:"+scale+":"+path;
  auto it=cache.find(key);
  if(it!=cache.end()&&it->second.modified==stamp&&it->second.dataset)
    return it->second.dataset;
  auto result=std::make_shared<cartorig::Dataset>(
      cartorig::NaturalEarthCatalog::countryPolygons(path,scale));
  if(cache.size()>16)cache.clear();
  cache[key]={stamp,result,nullptr};
  return result;
}
std::shared_ptr<const std::vector<cartorig::NaturalEarthGeometry>>
naturalEarthLayerAt(const std::string &path,const std::string &name){
  std::lock_guard<std::mutex> lock(cacheMutex);
  const auto stamp=std::filesystem::last_write_time(path);
  const auto key=path+":"+name;
  auto it=vectorLayerCache.find(key);
  if(it!=vectorLayerCache.end()&&it->second.modified==stamp)
    return it->second.features;
  auto value=std::make_shared<const std::vector<cartorig::NaturalEarthGeometry>>(
      cartorig::NaturalEarthCatalog::layerGeometries(path,name));
  if(vectorLayerCache.size()>=8)vectorLayerCache.clear();
  vectorLayerCache[key]={stamp,value};
  return value;
}
std::shared_ptr<const cartorig::NaturalEarthRaster> naturalEarthRasterAt(
    const std::string &root,const std::string &assetId){
  std::lock_guard<std::mutex> lock(cacheMutex);
  // Cache immutable source metadata only; all per-render tile buffers remain
  // thread-local, preventing races during asynchronous Resolve frame requests.
  const auto index=std::filesystem::path(root)/assetId/"index.json";
  const auto stamp=std::filesystem::last_write_time(index);
  const auto key=root+":"+assetId;
  const auto it=rasterCache.find(key);
  if(it!=rasterCache.end()&&it->second.modified==stamp)
    return it->second.raster;
  auto value=std::make_shared<const cartorig::NaturalEarthRaster>(
      cartorig::loadNaturalEarthRaster(root,assetId));
  if(rasterCache.size()>=12)rasterCache.clear();
  rasterCache[key]={stamp,value};
  return value;
}
std::shared_ptr<const std::vector<cartorig::NaturalEarthGeometry>>
geographicRegionAt(const std::string &primary,const std::string &supplement,
                   const cartorig::GeographicRegionSelection &r){
  const auto load=[&](const std::string &source){
    const auto stamp=std::filesystem::last_write_time(source);
    const auto key=source+"|"+r.featureKey;
    std::lock_guard<std::mutex> lock(cacheMutex);
    const auto found=regionGeometryCache.find(key);
    if(found!=regionGeometryCache.end()&&found->second.modified==stamp)
      return found->second.features;
    std::vector<cartorig::NaturalEarthGeometry> geometries;
    if(r.kind=="continent"){
      geometries=cartorig::NaturalEarthCatalog::continentGeometries(source,r.name,"10m");
    }else{
      cartorig::NaturalEarthRegion region;
      region.sourceLayer=r.sourceLayer;region.sourceRowId=r.sourceRowId;
      region.geometryType=r.kind=="city"?"POINT":"POLYGON";
      auto geometry=cartorig::NaturalEarthCatalog::featureGeometry(source,region);
      if(!geometry.empty())geometries.push_back(std::move(geometry));
    }
    if(geometries.empty())
      throw std::invalid_argument("Selected geographic region has no publisher geometry");
    auto ptr=std::make_shared<const std::vector<cartorig::NaturalEarthGeometry>>(
        std::move(geometries));
    if(regionGeometryCache.size()>=100)regionGeometryCache.clear();
    regionGeometryCache[key]={stamp,ptr};
    return ptr;
  };
  try{return load(primary);}
  catch(const std::invalid_argument &error){
    if(supplement.empty()||supplement==primary||
       std::string(error.what())!="Natural Earth geometry layer absent from GeoPackage")
      throw;
    return load(supplement);
  }
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
void defineDouble(OfxParamSetHandle set,const char*name,const char*label,double val,double lo,double hi,const char*group=nullptr){OfxPropertySetHandle p=nullptr;if(param->paramDefine(set,kOfxParamTypeDouble,name,&p)!=kOfxStatOK)throw std::runtime_error("param define");prop->propSetString(p,kOfxPropLabel,0,label);prop->propSetDouble(p,kOfxParamPropDefault,0,val);prop->propSetDouble(p,kOfxParamPropMin,0,lo);prop->propSetDouble(p,kOfxParamPropMax,0,hi);prop->propSetDouble(p,kOfxParamPropDisplayMin,0,lo);prop->propSetDouble(p,kOfxParamPropDisplayMax,0,hi);prop->propSetInt(p,kOfxParamPropAnimates,0,1);if(group)prop->propSetString(p,kOfxParamPropParent,0,group);}
void defineString(OfxParamSetHandle set,const char *name,const char *label,const char*group=nullptr){OfxPropertySetHandle p=nullptr;if(param->paramDefine(set,kOfxParamTypeString,name,&p)!=kOfxStatOK)throw std::runtime_error("param define string");prop->propSetString(p,kOfxPropLabel,0,label);prop->propSetString(p,kOfxParamPropDefault,0,"");prop->propSetInt(p,kOfxParamPropAnimates,0,0);prop->propSetString(p,kOfxParamPropStringMode,0,kOfxParamStringIsFilePath);if(group)prop->propSetString(p,kOfxParamPropParent,0,group);}
void defineMultiline(OfxParamSetHandle set,const char *name,const char *label,const char*group=nullptr){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(set,kOfxParamTypeString,name,&props)!=kOfxStatOK)
    throw std::runtime_error("embedded JSON parameter definition failed");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetString(props,kOfxParamPropDefault,0,"");
  prop->propSetString(props,kOfxParamPropStringMode,0,kOfxParamStringIsMultiLine);
  prop->propSetInt(props,kOfxParamPropPersistant,0,1);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
  if(group)prop->propSetString(props,kOfxParamPropParent,0,group);
}
void defineBoolean(OfxParamSetHandle set,const char *name,const char *label,bool value,const char*group=nullptr){OfxPropertySetHandle p=nullptr;if(param->paramDefine(set,kOfxParamTypeBoolean,name,&p)!=kOfxStatOK)throw std::runtime_error("param define bool");prop->propSetString(p,kOfxPropLabel,0,label);prop->propSetInt(p,kOfxParamPropDefault,0,value?1:0);prop->propSetInt(p,kOfxParamPropAnimates,0,0);if(group)prop->propSetString(p,kOfxParamPropParent,0,group);}
void defineNativeGroup(OfxParamSetHandle ps,const char*name,const char*label,bool open){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeGroup,name,&props)!=kOfxStatOK)
    throw std::runtime_error("cannot define native map Inspector group");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetInt(props,kOfxParamPropGroupOpen,0,open?1:0);
}
void defineNativeText(OfxParamSetHandle ps,const char*name,const char*label,const char*group){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeString,name,&props)!=kOfxStatOK)
    throw std::runtime_error("cannot define native text field");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetString(props,kOfxParamPropDefault,0,"");
  prop->propSetString(props,kOfxParamPropStringMode,0,kOfxParamStringIsSingleLine);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
  prop->propSetInt(props,kOfxParamPropPersistant,0,1);
  if(group)prop->propSetString(props,kOfxParamPropParent,0,group);
}
void defineNativeDouble(OfxParamSetHandle ps,const char*name,const char*label,
                        double initial,double lo,double hi,const char*group){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeDouble,name,&props)!=kOfxStatOK)
    throw std::runtime_error("cannot define native numeric field");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetDouble(props,kOfxParamPropDefault,0,initial);
  prop->propSetDouble(props,kOfxParamPropMin,0,lo);
  prop->propSetDouble(props,kOfxParamPropMax,0,hi);
  prop->propSetDouble(props,kOfxParamPropDisplayMin,0,lo);
  prop->propSetDouble(props,kOfxParamPropDisplayMax,0,hi);
  prop->propSetInt(props,kOfxParamPropAnimates,0,1);
  if(group)prop->propSetString(props,kOfxParamPropParent,0,group);
}
void defineNativeToggle(OfxParamSetHandle ps,const char*name,const char*label,bool initial,const char*group){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeBoolean,name,&props)!=kOfxStatOK)
    throw std::runtime_error("cannot define native toggle");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetInt(props,kOfxParamPropDefault,0,initial?1:0);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
  if(group)prop->propSetString(props,kOfxParamPropParent,0,group);
}
void defineNaturalEarthDetailChoice(OfxParamSetHandle ps){
  OfxPropertySetHandle properties=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeChoice,"NaturalEarthDetail",&properties)!=kOfxStatOK)
    throw std::runtime_error("Natural Earth detail choice parameter unavailable");
  prop->propSetString(properties,kOfxPropLabel,0,"Vector detail");
  prop->propSetString(properties,kOfxParamPropParent,0,"AdvancedScene");
  prop->propSetInt(properties,kOfxParamPropDefault,0,0);
  const char* levels[]={"Auto (zoom dependent)","110m (overview)","50m (medium)","10m (detailed)"};
  for(int n=0;n<4;++n)
    prop->propSetString(properties,kOfxParamPropChoiceOption,n,levels[n]);
}
void defineGeographicChoice(OfxParamSetHandle ps,const char*name,
                            const char*label,const char *const *options,
                            int count,int selected){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeChoice,name,&props)!=kOfxStatOK)
    throw std::runtime_error("Geographic region dropdown unavailable");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetString(props,kOfxParamPropParent,0,"GeographicRegion");
  prop->propSetInt(props,kOfxParamPropDefault,0,selected);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
  for(int index=0;index<count;++index)
    prop->propSetString(props,kOfxParamPropChoiceOption,index,options[index]);
}
void defineGeographicButton(OfxParamSetHandle ps,const char *name,
                            const char *label){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypePushButton,name,&props)!=kOfxStatOK)
    throw std::runtime_error("Geographic region action button unavailable");
  prop->propSetString(props,kOfxPropLabel,0,label);
  prop->propSetString(props,kOfxParamPropParent,0,"GeographicRegion");
}
void defineGeographicRegionUI(OfxParamSetHandle ps){
  defineNativeGroup(ps,"GeographicRegion","Geographic region",false);
  defineString(ps,"GeographicCatalog","Offline search index (catalog.sqlite)","GeographicRegion");
  const char *kinds[]={"Continent","Country","State / Province","City"};
  defineGeographicChoice(ps,"GeographicRegionKind","Geographic region",kinds,4,1);
  defineNativeText(ps,"GeographicRegionQuery","Search location","GeographicRegion");
  const char *matches[]={"Result 1","Result 2","Result 3","Result 4","Result 5",
                         "Result 6","Result 7","Result 8","Result 9","Result 10"};
  defineGeographicChoice(ps,"GeographicRegionMatch","Search result",matches,10,0);
  // Native OpenFX text label is best effort: Resolve may not refresh it
  // immediately on InstanceChanged; selected content still persists in JSON.
  OfxPropertySetHandle info=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeString,"GeographicRegionStatus",&info)!=kOfxStatOK)
    throw std::runtime_error("Geographic result label unavailable");
  prop->propSetString(info,kOfxPropLabel,0,"Matches / selected");
  prop->propSetString(info,kOfxParamPropStringMode,0,kOfxParamStringIsLabel);
  prop->propSetString(info,kOfxParamPropDefault,0,"Choose type and search a location");
  prop->propSetInt(info,kOfxParamPropAnimates,0,0);
  prop->propSetString(info,kOfxParamPropParent,0,"GeographicRegion");
  defineNativeDouble(ps,"GeographicRegionRed","Region red",40,0,255,"GeographicRegion");
  defineNativeDouble(ps,"GeographicRegionGreen","Region green",157,0,255,"GeographicRegion");
  defineNativeDouble(ps,"GeographicRegionBlue","Region blue",192,0,255,"GeographicRegion");
  defineNativeDouble(ps,"GeographicRegionAlpha","Region opacity (0-255)",220,0,255,"GeographicRegion");
  defineGeographicButton(ps,"GeographicRegionAdd","Add / update selected region");
  defineGeographicButton(ps,"GeographicRegionRemove","Remove selected region");
  defineMultiline(ps,"GeographicRegionSaved",
                  "Selected regions (persistent project state)","GeographicRegion");
}
void defineVersionLabel(OfxParamSetHandle ps){
  OfxPropertySetHandle props=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeString,"CartoRigBuildInfo",&props)!=kOfxStatOK)
    throw std::runtime_error("version label parameter failed");
  prop->propSetString(props,kOfxPropLabel,0,"Installed plugin build");
  prop->propSetString(props,kOfxParamPropStringMode,0,kOfxParamStringIsLabel);
  const std::string info=std::string("0.4.0-dev / ")+CARTORIG_BUILD_SHA;
  prop->propSetString(props,kOfxParamPropDefault,0,info.c_str());
  prop->propSetInt(props,kOfxParamPropPersistant,0,0);
  prop->propSetInt(props,kOfxParamPropAnimates,0,0);
}
void defineDiagnosticChoice(OfxParamSetHandle ps,const char*group=nullptr){
  OfxPropertySetHandle p=nullptr;
  if(param->paramDefine(ps,kOfxParamTypeChoice,"DiagnosticMode",&p)!=kOfxStatOK)
    throw std::runtime_error("cannot create diagnostic choice");
  prop->propSetString(p,kOfxPropLabel,0,"Diagnostic output (test only)");
  prop->propSetInt(p,kOfxParamPropDefault,0,0);
  prop->propSetInt(p,kOfxParamPropAnimates,0,0);
  const char *names[]{"Normal map","RGB bars","Grayscale ramp","Alpha split","Solid white"};
  for(int index=0;index<5;++index)
    prop->propSetString(p,kOfxParamPropChoiceOption,index,names[index]);
  if(group)prop->propSetString(p,kOfxParamPropParent,0,group);
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
OfxStatus describeInContext(OfxImageEffectHandle e,bool filter){
 OfxPropertySetHandle p=nullptr;
 if(filter){
   if(fx->clipDefine(e,kOfxImageEffectSimpleSourceClipName,&p)!=kOfxStatOK)
     return kOfxStatFailed;
   prop->propSetString(p,kOfxImageEffectPropSupportedComponents,0,kOfxImageComponentRGBA);
 }
 if(fx->clipDefine(e,kOfxImageEffectOutputClipName,&p)!=kOfxStatOK)return kOfxStatFailed;
 prop->propSetString(p,kOfxImageEffectPropSupportedComponents,0,kOfxImageComponentRGBA);
 OfxParamSetHandle ps=nullptr;
 if(fx->getParamSet(e,&ps)!=kOfxStatOK)return kOfxStatFailed;
 defineVersionLabel(ps);
 // Every new instance begins with user-controlled static camera parameters.
 // The Brazil/Venezuela example is an optional imported scene, never auto-loaded.
 defineBoolean(ps,"UseSceneCamera","Use camera animation from imported scene",false);
 defineDouble(ps,"Longitude","Camera longitude",0,-180,180);
 defineDouble(ps,"Latitude","Camera latitude",0,-85,85);
 defineDouble(ps,"Zoom","Camera zoom",1.3,0,18);
 defineDouble(ps,"Bearing","Camera bearing (degrees)",0,-360,360);
 defineDouble(ps,"Opacity","Cartography opacity (entire map)",filter?0.7:1,0,1);
 defineDouble(ps,"SceneTimeOffset","Scene offset (host frames)",0,-86400,86400);
 defineDouble(ps,"SceneTimeScale","Scene time scale / reverse",1,-8,8);

 defineNativeGroup(ps,"CountryControls","Territories / highlight",true);
 defineNativeText(ps,"CountryA","Country 1 (ISO3, e.g. BRA)","CountryControls");
 defineNativeText(ps,"CountryB","Country 2 (ISO3, e.g. VEN)","CountryControls");
 defineNativeText(ps,"CountryList","More countries (ISO3 list)","CountryControls");
 defineNativeDouble(ps,"HighlightStrength","Highlight opacity",1,0,1,"CountryControls");

 defineGeographicRegionUI(ps);
 defineNativeGroup(ps,"RouteControls","Manual geographic route",true);
 defineNativeToggle(ps,"NativeRouteEnabled","Enable manual route",false,"RouteControls");
 defineNativeDouble(ps,"RouteStartLongitude","Start longitude",-20,-180,180,"RouteControls");
 defineNativeDouble(ps,"RouteStartLatitude","Start latitude",0,-85,85,"RouteControls");
 defineNativeDouble(ps,"RouteEndLongitude","End longitude",20,-180,180,"RouteControls");
 defineNativeDouble(ps,"RouteEndLatitude","End latitude",0,-85,85,"RouteControls");
 defineDouble(ps,"RouteProgress","Route reveal (animate 0 to 1)",1,-1,1,"RouteControls");
 defineNativeDouble(ps,"NativeRouteCurve","Route curvature",-20,-100,100,"RouteControls");
 defineNativeDouble(ps,"NativeRouteWidth","Route width",3,.5,30,"RouteControls");
 defineNativeToggle(ps,"RouteMarkers","Show route endpoints",true,"RouteControls");
 defineNativeText(ps,"RouteFromLabel","Origin label","RouteControls");
 defineNativeText(ps,"RouteToLabel","Destination label","RouteControls");

 defineNativeGroup(ps,"MapColors","Map colors (optional override)",false);
 defineNativeToggle(ps,"CustomMapColors","Override imported map colors",false,"MapColors");
 defineNativeDouble(ps,"OceanR","Ocean red",13,0,255,"MapColors");
 defineNativeDouble(ps,"OceanG","Ocean green",30,0,255,"MapColors");
 defineNativeDouble(ps,"OceanB","Ocean blue",50,0,255,"MapColors");
 defineNativeDouble(ps,"LandR","Land red",35,0,255,"MapColors");
 defineNativeDouble(ps,"LandG","Land green",59,0,255,"MapColors");
 defineNativeDouble(ps,"LandB","Land blue",82,0,255,"MapColors");
 defineNativeDouble(ps,"HighlightR","Highlight red",40,0,255,"MapColors");
 defineNativeDouble(ps,"HighlightG","Highlight green",157,0,255,"MapColors");
 defineNativeDouble(ps,"HighlightB","Highlight blue",192,0,255,"MapColors");

 defineNativeGroup(ps,"AdvancedScene","Advanced: import custom scenes",false);
 defineString(ps,"NaturalEarthVectorGpkg","Vector GeoPackage","AdvancedScene");
 defineNaturalEarthDetailChoice(ps);
 // Optional raw publisher table name. Never changes existing map clips unless set.
 defineString(ps,"NaturalEarthLayer","Additional vector layer (ne_...)","AdvancedScene");
 defineString(ps,"NaturalEarthLayerGpkg","Additional layer GeoPackage (optional)","AdvancedScene");
 defineString(ps,"NaturalEarthRasterRoot","Raster tiles directory (offline)","AdvancedScene");
 defineNativeText(ps,"NaturalEarthRasterAsset","Raster asset ID (blank: disabled)","AdvancedScene");
 defineString(ps,"SceneFile","Scene .json (blank: empty map)","AdvancedScene");
 defineString(ps,"CatalogFile","GeoJSON (blank: offline countries)","AdvancedScene");
 defineMultiline(ps,"EmbeddedSceneJSON","Embedded scene JSON (portable)","AdvancedScene");
 defineMultiline(ps,"EmbeddedCatalogJSON","Embedded GeoJSON (portable)","AdvancedScene");
 defineDiagnosticChoice(ps,"AdvancedScene");
 defineBoolean(ps,"DiagnosticLog","Write OFX diagnostic log",false,"AdvancedScene");
 return kOfxStatOK;
}
OfxStatus createInstance(OfxImageEffectHandle e,bool filter){auto i=std::make_unique<Instance>();i->overlay=filter;OfxParamSetHandle ps=nullptr;if(fx->getParamSet(e,&ps)!=kOfxStatOK)return kOfxStatFailed;
 if(fx->clipGetHandle(e,kOfxImageEffectOutputClipName,&i->output,nullptr)!=kOfxStatOK)return kOfxStatFailed;
 if(filter&&fx->clipGetHandle(e,kOfxImageEffectSimpleSourceClipName,&i->source,nullptr)!=kOfxStatOK)return kOfxStatFailed;
 for(auto t:std::vector<std::pair<const char*,OfxParamHandle*>>{{"SceneFile",&i->sceneFile},{"CatalogFile",&i->datasetFile},
 {"NaturalEarthVectorGpkg",&i->naturalEarthGpkg},{"NaturalEarthDetail",&i->naturalEarthDetail},
 {"NaturalEarthLayer",&i->naturalEarthLayer},
 {"NaturalEarthLayerGpkg",&i->naturalEarthLayerFile},
 {"NaturalEarthRasterRoot",&i->naturalEarthRasterRoot},
 {"NaturalEarthRasterAsset",&i->naturalEarthRasterAsset},
 {"GeographicCatalog",&i->regionCatalog},
 {"GeographicRegionKind",&i->regionKind},{"GeographicRegionQuery",&i->regionQuery},
 {"GeographicRegionMatch",&i->regionMatch},{"GeographicRegionStatus",&i->regionStatus},
 {"GeographicRegionRed",&i->regionRed},{"GeographicRegionGreen",&i->regionGreen},
 {"GeographicRegionBlue",&i->regionBlue},{"GeographicRegionAlpha",&i->regionAlpha},
 {"GeographicRegionAdd",&i->regionAdd},{"GeographicRegionRemove",&i->regionRemove},
 {"GeographicRegionSaved",&i->regionSaved},
 {"EmbeddedSceneJSON",&i->sceneInline},{"EmbeddedCatalogJSON",&i->datasetInline},
 {"SceneTimeOffset",&i->frameOffset},{"SceneTimeScale",&i->timeScale},
 {"UseSceneCamera",&i->useSceneKeys},{"Longitude",&i->lon},{"Latitude",&i->lat},{"Zoom",&i->zoom},
 {"Bearing",&i->bearing},{"RouteProgress",&i->route},{"Opacity",&i->opacity},
 {"CountryA",&i->countryA},{"CountryB",&i->countryB},{"CountryList",&i->countryList},{"HighlightStrength",&i->highlightStrength},
 {"NativeRouteEnabled",&i->routeEnabled},{"RouteStartLongitude",&i->routeStartLon},
 {"RouteStartLatitude",&i->routeStartLat},{"RouteEndLongitude",&i->routeEndLon},
 {"RouteEndLatitude",&i->routeEndLat},{"NativeRouteCurve",&i->routeCurve},
 {"NativeRouteWidth",&i->routeWidth},{"RouteMarkers",&i->showRouteMarkers},
 {"RouteFromLabel",&i->routeStartLabel},{"RouteToLabel",&i->routeEndLabel},
 {"CustomMapColors",&i->manualColors},{"OceanR",&i->oceanR},{"OceanG",&i->oceanG},
 {"OceanB",&i->oceanB},{"LandR",&i->landR},{"LandG",&i->landG},{"LandB",&i->landB},
 {"HighlightR",&i->highlightR},{"HighlightG",&i->highlightG},{"HighlightB",&i->highlightB},
 {"DiagnosticMode",&i->diagnosticMode},{"DiagnosticLog",&i->diagnosticLog}})if(param->paramGetHandle(ps,t.first,t.second,nullptr)!=kOfxStatOK)return kOfxStatFailed;
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
 std::string sceneFile,datasetFile,inlineScene,inlineCatalog,naturalEarthPath;
 stringAt(i->sceneFile,time,sceneFile);stringAt(i->datasetFile,time,datasetFile);
 stringAt(i->sceneInline,time,inlineScene);stringAt(i->datasetInline,time,inlineCatalog);
 stringAt(i->naturalEarthGpkg,time,naturalEarthPath);
 if(sceneFile.empty())sceneFile=defaultAsset("default-map.cartorig-native.json");
 auto scene=inlineScene.empty()?sceneAt(sceneFile):embeddedSceneAt(*i,inlineScene);
 // Priority: Embedded GeoJSON > explicit GeoJSON filename > local Natural
 // Earth GeoPackage > bundled neutral GeoJSON. Existing clips stay unchanged.
 std::shared_ptr<const cartorig::Dataset> dataset;
 if(!inlineCatalog.empty())dataset=embeddedDatasetAt(*i,inlineCatalog);
 else if(!datasetFile.empty())dataset=datasetAt(datasetFile);
 else if(!naturalEarthPath.empty()){
   const int detail=intAt(i->naturalEarthDetail,time,0);
   const double zoom=doubleAt(i->zoom,time,1.3);
   const char *scale=detail==1?"110m":detail==2?"50m":detail==3?"10m":
                      (zoom<3.5?"110m":zoom<7?"50m":"10m");
   dataset=naturalEarthCountriesAt(naturalEarthPath,scale);
 }else dataset=datasetAt(defaultAsset("countries.geojson"));
 const double sceneFrame=cartorig::mapSceneFrame(time,
   doubleAt(i->frameOffset,time,0),doubleAt(i->timeScale,time,1));
 cartorig::View view;view.width=width;view.height=height;view.frame=sceneFrame;
 view.camera=evaluateCamera(*scene,sceneFrame);
 view.opacity=std::clamp(doubleAt(i->opacity,time,1),0.0,1.0);
 if(!intAt(i->useSceneKeys,time,0)){view.camera.lon=doubleAt(i->lon,time,view.camera.lon);view.camera.lat=doubleAt(i->lat,time,view.camera.lat);view.camera.zoom=doubleAt(i->zoom,time,view.camera.zoom);view.camera.bearing=doubleAt(i->bearing,time,view.camera.bearing);}
 view.routeProgress=doubleAt(i->route,time,1);
 cartorig::NativeMapControls controls;
 stringAt(i->countryA,time,controls.countryA);
 stringAt(i->countryB,time,controls.countryB);
 stringAt(i->countryList,time,controls.countryList);
 controls.highlightStrength=doubleAt(i->highlightStrength,time,1);
 controls.routeEnabled=intAt(i->routeEnabled,time,0)!=0;
 controls.routeStart.lon=doubleAt(i->routeStartLon,time,-20);
 controls.routeStart.lat=doubleAt(i->routeStartLat,time,0);
 controls.routeEnd.lon=doubleAt(i->routeEndLon,time,20);
 controls.routeEnd.lat=doubleAt(i->routeEndLat,time,0);
 controls.routeCurve=doubleAt(i->routeCurve,time,-20);
 controls.routeWidth=doubleAt(i->routeWidth,time,3);
 controls.routeMarkers=intAt(i->showRouteMarkers,time,1)!=0;
 stringAt(i->routeStartLabel,time,controls.startLabel);
 stringAt(i->routeEndLabel,time,controls.endLabel);
 controls.customColors=intAt(i->manualColors,time,0)!=0;
 const auto byteAt=[&](OfxParamHandle h,double fallback){
   return static_cast<uint8_t>(std::lround(
     std::clamp(doubleAt(h,time,fallback),0.0,255.0)));
 };
 if(controls.customColors){
   controls.ocean={byteAt(i->oceanR,13),byteAt(i->oceanG,30),byteAt(i->oceanB,50),255};
   controls.land={byteAt(i->landR,35),byteAt(i->landG,59),byteAt(i->landB,82),255};
   controls.highlight={byteAt(i->highlightR,40),byteAt(i->highlightG,157),byteAt(i->highlightB,192),220};
 }
 auto copy=cartorig::sceneWithNativeControls(*scene,controls);
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
 std::string rasterRoot,rasterAsset;
 stringAt(i->naturalEarthRasterRoot,time,rasterRoot);
 stringAt(i->naturalEarthRasterAsset,time,rasterAsset);
 if(!rasterAsset.empty()){
   if(rasterRoot.empty())
     throw std::invalid_argument("Natural Earth raster asset requires offline tile directory");
   const auto atlas=naturalEarthRasterAt(rasterRoot,rasterAsset);
   cartorig::renderNaturalEarthRaster(*atlas,view,target);
 }
 std::string extraLayer,extraLayerPath;
 stringAt(i->naturalEarthLayer,time,extraLayer);
 stringAt(i->naturalEarthLayerFile,time,extraLayerPath);
 if(!extraLayer.empty()){
   const auto &source=extraLayerPath.empty()?naturalEarthPath:extraLayerPath;
   if(source.empty())
     throw std::invalid_argument("Additional vector layer requires a local GeoPackage");
   const auto geometry=naturalEarthLayerAt(source,extraLayer);
   // Selected non-country geometries are drawn over the existing map; no
   // implicit geographic claims or fabricated city/municipal polygons.
   cartorig::renderNaturalEarthLayer(
       *geometry,view,target,
       cartorig::Color{76,144,110,155},
       cartorig::Color{96,193,231,235},
       cartorig::Color{255,207,115,245});
 }
 return kOfxStatOK;
}
OfxStatus entry(const char *action,const void *handle,OfxPropertySetHandle args,OfxPropertySetHandle out,bool filter){try {
 if(!std::strcmp(action,kOfxActionLoad))return onLoad();
 if(!std::strcmp(action,kOfxActionUnload)){std::lock_guard<std::mutex> lock(cacheMutex);cache.clear();vectorLayerCache.clear();rasterCache.clear();return kOfxStatOK;}
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
