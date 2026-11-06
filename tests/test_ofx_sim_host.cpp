// ABI-level simulated OpenFX host: generator, filter, persistence, RGBA, keyframes.
#include "ofxCore.h"
#include "ofxImageEffect.h"
#include "ofxParam.h"
#include "ofxProperty.h"
#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <variant>
#include <vector>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif
using V=std::variant<int,double,std::string,void*>;
struct Bag {std::map<std::string,std::vector<V>> props;};
struct P {std::string type;Bag properties;V val=0;bool overrideValue=false;std::map<double,double> keys;};
struct PS {std::map<std::string,std::unique_ptr<P>> params;};
struct Clip {std::string name;Bag properties,image;std::vector<float> pixels;};
struct Effect {Bag properties;PS params;std::map<std::string,std::unique_ptr<Clip>> clips;};
static int passed=0,failed=0;
static void check(bool x,const char*label){if(x)++passed;else{++failed;std::cerr<<"FAIL "<<label<<"\n";}}
static Bag *bp(OfxPropertySetHandle h){return reinterpret_cast<Bag*>(h);}
static OfxPropertySetHandle bh(Bag &b){return reinterpret_cast<OfxPropertySetHandle>(&b);}
static OfxStatus put(OfxPropertySetHandle h,const char*n,int k,V v){
 if(!h||!n||k<0||k>1024)return kOfxStatErrBadHandle;
 auto &a=bp(h)->props[n];if(static_cast<int>(a.size())<=k)a.resize(size_t(k+1));
 a[size_t(k)]=std::move(v);return kOfxStatOK;
}
static const V* value(OfxPropertySetHandle h,const char*n,int k){
 if(!h||!n||k<0)return nullptr;
 auto it=bp(h)->props.find(n);
 if(it==bp(h)->props.end()||size_t(k)>=it->second.size())return nullptr;
 return &it->second[size_t(k)];
}
static OfxStatus setP(OfxPropertySetHandle h,const char*n,int k,void*v){return put(h,n,k,v);}
static OfxStatus setS(OfxPropertySetHandle h,const char*n,int k,const char*v){return put(h,n,k,std::string(v?v:""));}
static OfxStatus setD(OfxPropertySetHandle h,const char*n,int k,double v){return put(h,n,k,v);}
static OfxStatus setI(OfxPropertySetHandle h,const char*n,int k,int v){return put(h,n,k,v);}
static OfxStatus setPN(OfxPropertySetHandle h,const char*n,int c,void*const*v){for(int i=0;i<c;i++)setP(h,n,i,v[i]);return kOfxStatOK;}
static OfxStatus setSN(OfxPropertySetHandle h,const char*n,int c,const char*const*v){for(int i=0;i<c;i++)setS(h,n,i,v[i]);return kOfxStatOK;}
static OfxStatus setDN(OfxPropertySetHandle h,const char*n,int c,const double*v){for(int i=0;i<c;i++)setD(h,n,i,v[i]);return kOfxStatOK;}
static OfxStatus setIN(OfxPropertySetHandle h,const char*n,int c,const int*v){for(int i=0;i<c;i++)setI(h,n,i,v[i]);return kOfxStatOK;}
static OfxStatus getP(OfxPropertySetHandle h,const char*n,int k,void**v){
 auto a=value(h,n,k);if(!a||!std::holds_alternative<void*>(*a))return kOfxStatErrUnknown;
 *v=std::get<void*>(*a);return kOfxStatOK;
}
static OfxStatus getS(OfxPropertySetHandle h,const char*n,int k,char**v){
 auto a=value(h,n,k);if(!a||!std::holds_alternative<std::string>(*a))return kOfxStatErrUnknown;
 *v=const_cast<char*>(std::get<std::string>(*a).c_str());return kOfxStatOK;
}
static OfxStatus getD(OfxPropertySetHandle h,const char*n,int k,double*v){
 auto a=value(h,n,k);if(!a)return kOfxStatErrUnknown;
 if(std::holds_alternative<double>(*a))*v=std::get<double>(*a);
 else if(std::holds_alternative<int>(*a))*v=std::get<int>(*a);
 else return kOfxStatErrValue;return kOfxStatOK;
}
static OfxStatus getI(OfxPropertySetHandle h,const char*n,int k,int*v){
 auto a=value(h,n,k);if(!a||!std::holds_alternative<int>(*a))return kOfxStatErrUnknown;
 *v=std::get<int>(*a);return kOfxStatOK;
}
static OfxStatus getPN(OfxPropertySetHandle h,const char*n,int c,void**v){for(int i=0;i<c;i++)if(getP(h,n,i,v+i)!=kOfxStatOK)return kOfxStatErrUnknown;return kOfxStatOK;}
static OfxStatus getSN(OfxPropertySetHandle h,const char*n,int c,char**v){for(int i=0;i<c;i++)if(getS(h,n,i,v+i)!=kOfxStatOK)return kOfxStatErrUnknown;return kOfxStatOK;}
static OfxStatus getDN(OfxPropertySetHandle h,const char*n,int c,double*v){for(int i=0;i<c;i++)if(getD(h,n,i,v+i)!=kOfxStatOK)return kOfxStatErrUnknown;return kOfxStatOK;}
static OfxStatus getIN(OfxPropertySetHandle h,const char*n,int c,int*v){for(int i=0;i<c;i++)if(getI(h,n,i,v+i)!=kOfxStatOK)return kOfxStatErrUnknown;return kOfxStatOK;}
static OfxStatus reset(OfxPropertySetHandle h,const char*n){bp(h)->props.erase(n);return kOfxStatOK;}
static OfxStatus dimension(OfxPropertySetHandle h,const char*n,int*c){
 auto it=bp(h)->props.find(n);if(it==bp(h)->props.end())return kOfxStatErrUnknown;
 *c=int(it->second.size());return kOfxStatOK;
}
static OfxPropertySuiteV1 propertySuite{setP,setS,setD,setI,setPN,setSN,setDN,setIN,getP,getS,getD,getI,getPN,getSN,getDN,getIN,reset,dimension};
static OfxStatus defineParam(OfxParamSetHandle raw,const char*type,const char*name,OfxPropertySetHandle*out){
 auto *ps=reinterpret_cast<PS*>(raw);auto v=std::make_unique<P>();v->type=type;
 auto *p=v.get();ps->params[name]=std::move(v);*out=bh(p->properties);return kOfxStatOK;
}
static OfxStatus getParam(OfxParamSetHandle raw,const char*n,OfxParamHandle*out,OfxPropertySetHandle*properties){
 auto *ps=reinterpret_cast<PS*>(raw);auto it=ps->params.find(n);if(it==ps->params.end())return kOfxStatErrUnknown;
 *out=reinterpret_cast<OfxParamHandle>(it->second.get());
 if(properties)*properties=bh(it->second->properties);return kOfxStatOK;
}
static OfxStatus paramProperties(OfxParamHandle h,OfxPropertySetHandle*out){
 *out=bh(reinterpret_cast<P*>(h)->properties);return kOfxStatOK;
}
static OfxStatus atTime(OfxParamHandle raw,OfxTime time,...){
 auto *p=reinterpret_cast<P*>(raw);
 const V *base=p->overrideValue?&p->val:value(bh(p->properties),kOfxParamPropDefault,0);
 va_list args;va_start(args,time);
 OfxStatus status=kOfxStatOK;
 if(p->type==kOfxParamTypeString){
   auto **out=va_arg(args,char**);
   if(base&&std::holds_alternative<std::string>(*base))
     *out=const_cast<char*>(std::get<std::string>(*base).c_str());
   else status=kOfxStatErrValue;
 }else if(p->type==kOfxParamTypeDouble){
   auto *out=va_arg(args,double*);
   if(!p->keys.empty()){
     auto a=p->keys.lower_bound(time);
     if(a==p->keys.end())*out=p->keys.rbegin()->second;
     else if(a==p->keys.begin())*out=a->second;
     else if(a->first==time)*out=a->second;
     else{auto b=std::prev(a);double f=(time-b->first)/(a->first-b->first);*out=b->second+(a->second-b->second)*f;}
   }else if(base&&std::holds_alternative<double>(*base))*out=std::get<double>(*base);
   else status=kOfxStatErrValue;
 }else{
   auto *out=va_arg(args,int*);
   if(base&&std::holds_alternative<int>(*base))*out=std::get<int>(*base);
   else status=kOfxStatErrValue;
 }
 va_end(args);return status;
}
static OfxParameterSuiteV1 paramSuite{};
static OfxStatus effectProps(OfxImageEffectHandle raw,OfxPropertySetHandle*out){*out=bh(reinterpret_cast<Effect*>(raw)->properties);return kOfxStatOK;}
static OfxStatus effectParams(OfxImageEffectHandle raw,OfxParamSetHandle*out){*out=reinterpret_cast<OfxParamSetHandle>(&reinterpret_cast<Effect*>(raw)->params);return kOfxStatOK;}
static OfxStatus defineClip(OfxImageEffectHandle raw,const char*n,OfxPropertySetHandle*out){
 auto *e=reinterpret_cast<Effect*>(raw);auto c=std::make_unique<Clip>();c->name=n;
 auto *p=c.get();e->clips[n]=std::move(c);*out=bh(p->properties);return kOfxStatOK;
}
static OfxStatus getClip(OfxImageEffectHandle raw,const char*n,OfxImageClipHandle*out,OfxPropertySetHandle*properties){
 auto &clips=reinterpret_cast<Effect*>(raw)->clips;auto it=clips.find(n);
 if(it==clips.end())return kOfxStatErrUnknown;
 *out=reinterpret_cast<OfxImageClipHandle>(it->second.get());
 if(properties)*properties=bh(it->second->properties);return kOfxStatOK;
}
static OfxStatus clipProps(OfxImageClipHandle raw,OfxPropertySetHandle*out){
 *out=bh(reinterpret_cast<Clip*>(raw)->properties);return kOfxStatOK;
}
static OfxStatus getImage(OfxImageClipHandle raw,OfxTime,const OfxRectD*,OfxPropertySetHandle*out){
 auto *c=reinterpret_cast<Clip*>(raw);if(c->pixels.empty())return kOfxStatFailed;
 setP(bh(c->image),kOfxImagePropData,0,c->pixels.data());*out=bh(c->image);return kOfxStatOK;
}
static OfxStatus releaseImage(OfxPropertySetHandle){return kOfxStatOK;}
static OfxImageEffectSuiteV1 effectSuite{};
static const void *fetchSuite(OfxPropertySetHandle,const char*n,int version){
 if(version!=1)return nullptr;
 if(!std::strcmp(n,kOfxImageEffectSuite))return &effectSuite;
 if(!std::strcmp(n,kOfxPropertySuite))return &propertySuite;
 if(!std::strcmp(n,kOfxParameterSuite))return &paramSuite;
 return nullptr;
}
static void boot(){
 paramSuite.paramDefine=defineParam;paramSuite.paramGetHandle=getParam;
 paramSuite.paramGetPropertySet=paramProperties;paramSuite.paramGetValueAtTime=atTime;
 effectSuite.getPropertySet=effectProps;effectSuite.getParamSet=effectParams;
 effectSuite.clipDefine=defineClip;effectSuite.clipGetHandle=getClip;
 effectSuite.clipGetPropertySet=clipProps;effectSuite.clipGetImage=getImage;
 effectSuite.clipReleaseImage=releaseImage;
}
static void configure(Effect&e,int w,int h){
 setD(bh(e.properties),kOfxImageEffectPropProjectSize,0,w);
 setD(bh(e.properties),kOfxImageEffectPropProjectSize,1,h);
 for(auto &pair:e.clips){
   auto &clip=*pair.second;
   clip.pixels.assign(size_t(w)*h*4,0);
   auto img=bh(clip.image);int bounds[]{0,0,w,h};
   setIN(img,kOfxImagePropBounds,4,bounds);setI(img,kOfxImagePropRowBytes,0,w*16);
   setS(img,kOfxImageEffectPropPixelDepth,0,kOfxBitDepthFloat);
   setS(img,kOfxImageEffectPropComponents,0,kOfxImageComponentRGBA);
   setS(img,kOfxImageEffectPropPreMultiplication,0,kOfxImagePreMultiplied);
 }
}
static OfxStatus call(OfxPlugin*p,const char*n,Effect&e,Bag*args=nullptr,Bag*out=nullptr){
 return p->mainEntry(n,&e,args?bh(*args):nullptr,out?bh(*out):nullptr);
}
static void overrideParam(Effect&e,const char*n,V v){
 auto it=e.params.params.find(n);
 if(it==e.params.params.end())throw std::runtime_error(std::string("missing parameter ")+n);
 it->second->val=std::move(v);it->second->overrideValue=true;
}
static OfxStatus render(OfxPlugin*p,Effect&e,int w,int h,double time){
 Bag args;int window[]{0,0,w,h};
 setD(bh(args),kOfxPropTime,0,time);
 setD(bh(args),kOfxImageEffectPropRenderScale,0,1);
 setD(bh(args),kOfxImageEffectPropRenderScale,1,1);
 setIN(bh(args),kOfxImageEffectPropRenderWindow,4,window);
 return call(p,kOfxImageEffectActionRender,e,&args);
}
int main(int argc,char**argv){
 if(argc!=2)return 2;
#ifdef _WIN32
 HMODULE lib=LoadLibraryA(argv[1]);if(!lib)return 3;
 auto get=reinterpret_cast<OfxPlugin*(*)(int)>(GetProcAddress(lib,"OfxGetPlugin"));
#else
 void*lib=dlopen(argv[1],RTLD_NOW);if(!lib){std::cerr<<dlerror()<<"\n";return 3;}
 auto get=reinterpret_cast<OfxPlugin*(*)(int)>(dlsym(lib,"OfxGetPlugin"));
#endif
 if(!get)return 4;
 boot();Bag hostProperties;OfxHost host{bh(hostProperties),fetchSuite};
 auto *generator=get(0),*filter=get(1);
 generator->setHost(&host);filter->setHost(&host);
 check(generator->mainEntry(kOfxActionLoad,nullptr,nullptr,nullptr)==kOfxStatOK,"load generator");
 check(filter->mainEntry(kOfxActionLoad,nullptr,nullptr,nullptr)==kOfxStatOK,"load filter");
 constexpr int W=320,H=180;
 const std::string scene=R"({"schemaVersion":1,"fps":24,"frames":240,"camera":{"lon":-62,"lat":-11,"zoom":2.8},"style":{"ocean":"#A1B2C3","land":"#000000","transparent":false}})";
 const std::string empty=R"({"type":"FeatureCollection","features":[]})";
 auto init=[&](OfxPlugin*p,Effect&e,const char*context){
   check(call(p,kOfxActionDescribe,e)==kOfxStatOK,"describe");
   Bag args;setS(bh(args),kOfxImageEffectPropContext,0,context);
   check(call(p,kOfxImageEffectActionDescribeInContext,e,&args)==kOfxStatOK,"context");
   configure(e,W,H);check(call(p,kOfxActionCreateInstance,e)==kOfxStatOK,"instance");
 };
 Effect g;init(generator,g,kOfxImageEffectContextGenerator);
 Bag preferences;check(call(generator,kOfxImageEffectActionGetClipPreferences,g,nullptr,&preferences)==kOfxStatOK,"clip preference");
 char*assoc=nullptr;check(getS(bh(preferences),kOfxImageEffectPropPreMultiplication,0,&assoc)==kOfxStatOK&&
   !std::strcmp(assoc,kOfxImagePreMultiplied),"premultiplied output requested");
 char*components=nullptr;check(getS(bh(preferences),"OfxImageClipPropComponents_Output",0,&components)==kOfxStatOK&&
   !std::strcmp(components,kOfxImageComponentRGBA),"RGBA requested");
 int varying=0;check(getI(bh(preferences),kOfxImageEffectFrameVarying,0,&varying)==kOfxStatOK&&varying==1,"frame varying");
 overrideParam(g,"EmbeddedSceneJSON",scene);overrideParam(g,"EmbeddedCatalogJSON",empty);
 auto &output=g.clips.at("Output")->pixels;
 check(render(generator,g,W,H,0)==kOfxStatOK,"embedded generator");
 check(std::abs(output[0]-161.f/255)<.00001f&&
   std::abs(output[1]-178.f/255)<.00001f&&output[3]==1,"embedded style wins");
 auto before=output;
 Effect restored;init(generator,restored,kOfxImageEffectContextGenerator);
 for(const auto&pair:g.params.params)if(pair.second->overrideValue){
   auto it=restored.params.params.find(pair.first);
   if(it!=restored.params.params.end()){
      it->second->val=pair.second->val;it->second->overrideValue=true;
   }
 }
 check(render(generator,restored,W,H,0)==kOfxStatOK,"restored generator");
 check(restored.clips.at("Output")->pixels==before,"persisted param roundtrip pixel identical");
 overrideParam(g,"DiagnosticMode",1);
 check(render(generator,g,W,H,42)==kOfxStatOK,"RGB bars frame");
 check(output[0]==1&&output[1]==0&&output[2]==0&&output[3]==1&&
       output[(W-1)*4]==1&&output[(W-1)*4+2]==1,"RGB pattern correct");
 overrideParam(g,"DiagnosticMode",0);
 check(render(generator,g,W,H,0)==kOfxStatOK&&output==before,"random seek repeatability");
 overrideParam(g,"UseSceneCamera",0);
 g.params.params.at("Zoom")->keys={{0,2.8},{60,4.0}};
 check(render(generator,g,W,H,0)==kOfxStatOK,"camera key 0");
 check(render(generator,g,W,H,30)==kOfxStatOK,"camera key 30");
 check(render(generator,g,W,H,60)==kOfxStatOK,"camera key 60");
 Effect o;init(filter,o,kOfxImageEffectContextFilter);
 overrideParam(o,"EmbeddedSceneJSON",scene);overrideParam(o,"EmbeddedCatalogJSON",empty);
 auto &input=o.clips.at("Source")->pixels;
 auto &composite=o.clips.at("Output")->pixels;
 for(size_t j=0;j<input.size();j+=4){input[j]=.1f;input[j+1]=.2f;input[j+2]=.7f;input[j+3]=1;}
 auto inputCopy=input;
 overrideParam(o,"Opacity",0.0);
 check(render(filter,o,W,H,0)==kOfxStatOK,"overlay at opacity zero");
 check(input==inputCopy&&composite==input,"zero opacity video pass-through");
 overrideParam(o,"EmbeddedCatalogJSON",std::string(R"({"type":"FeatureCollection","features":[{"type":"Feature","properties":{"iso3":"TST"},"geometry":{"type":"Polygon","coordinates":[[[-72,-20],[-52,-20],[-52,0],[-72,0],[-72,-20]]]}}]})"));
 overrideParam(o,"Opacity",0.5);
 check(render(filter,o,W,H,0)==kOfxStatOK,"overlay over source");
 check(input==inputCopy,"Source remains immutable");
 const size_t center=(size_t(H/2)*W+W/2)*4;
 check(composite[center+2]<input[center+2]&&composite[center+3]==1.f,
    "source-over territory alpha composite");
 check(call(generator,kOfxActionDestroyInstance,g)==kOfxStatOK,"destroy generator");
 check(call(generator,kOfxActionDestroyInstance,restored)==kOfxStatOK,"destroy restored");
 check(call(filter,kOfxActionDestroyInstance,o)==kOfxStatOK,"destroy overlay");
 check(generator->mainEntry(kOfxActionUnload,nullptr,nullptr,nullptr)==kOfxStatOK,"unload");
#ifdef _WIN32
 FreeLibrary(lib);
#else
 dlclose(lib);
#endif
 std::cout<<passed<<" OFX simulated-host assertions passed, "<<failed<<" failed\n";
 return failed?1:0;
}
