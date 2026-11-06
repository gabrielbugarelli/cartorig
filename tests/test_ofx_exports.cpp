// ABI smoke test: validates that the compiled OFX module can be dynamically loaded
// and advertises the two intended OpenFX Image Effect descriptors. No Resolve host.
#include "ofxCore.h"
#include "ofxImageEffect.h"
#include <cstring>
#include <iostream>
#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif

int main(int argc,char **argv){
 if(argc!=2){std::cerr<<"Expected absolute path of OFX module\n";return 2;}
#ifdef _WIN32
 HMODULE lib=LoadLibraryA(argv[1]);
 if(!lib){std::cerr<<"LoadLibrary failed: "<<GetLastError()<<"\n";return 3;}
 auto count=reinterpret_cast<int (*)()>(GetProcAddress(lib,"OfxGetNumberOfPlugins"));
 auto get=reinterpret_cast<OfxPlugin* (*)(int)>(GetProcAddress(lib,"OfxGetPlugin"));
#else
 void*lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
 if(!lib){std::cerr<<"dlopen failed: "<<dlerror()<<"\n";return 3;}
 auto count=reinterpret_cast<int (*)()>(dlsym(lib,"OfxGetNumberOfPlugins"));
 auto get=reinterpret_cast<OfxPlugin* (*)(int)>(dlsym(lib,"OfxGetPlugin"));
#endif
 bool ok=count&&get&&count()==2;
 if(ok){
   auto a=get(0),b=get(1);
   ok=a&&b&&get(-1)==nullptr&&get(2)==nullptr;
   ok=ok&&std::strcmp(a->pluginApi,kOfxImageEffectPluginApi)==0;
   ok=ok&&std::strcmp(b->pluginApi,kOfxImageEffectPluginApi)==0;
   ok=ok&&std::strcmp(a->pluginIdentifier,"com.cartorig.native.map")==0;
   ok=ok&&std::strcmp(b->pluginIdentifier,"com.cartorig.native.overlay")==0;
   ok=ok&&a->mainEntry&&b->mainEntry&&a->setHost&&b->setHost;
   // Graceful missing-host response: must not access a suite before setHost.
   if(ok)ok=a->mainEntry(kOfxActionLoad,nullptr,nullptr,nullptr)==kOfxStatErrMissingHostFeature;
 }
#ifdef _WIN32
 FreeLibrary(lib);
#else
 dlclose(lib);
#endif
 if(!ok){std::cerr<<"Native OpenFX exports failed smoke test\n";return 1;}
 std::cout<<"OpenFX ABI: generator and overlay discoverable; missing-host path safe\n";
 return 0;
}
