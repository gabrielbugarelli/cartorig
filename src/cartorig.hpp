#pragma once
#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace cartorig {
struct GeoPoint { double lon=0,lat=0; };
struct ScreenPoint { double x=0,y=0; };
struct Camera { double lon=-60, lat=-12, zoom=3.1, bearing=0; };
struct CameraKey { int frame=0; Camera camera; std::string easing="smoothstep"; };
struct Color { uint8_t r=0,g=0,b=0,a=255; };
struct Polygon { std::vector<std::vector<GeoPoint>> rings; };
struct Feature { std::string id,name; std::vector<Polygon> polygons; };
struct Dataset { std::vector<Feature> features; std::map<std::string,size_t> byId; };
struct Marker { std::string id,label; GeoPoint at; Color color{255,200,100,255}; double size=6; };
struct Route { std::string id,from,to; Color color{255,200,100,255}; double width=3,curve=0; int start=0,end=120; };
struct Style { Color ocean{13,30,50,255},land{35,59,82,255},border{90,120,147,255},highlight{40,157,192,220}; bool transparent=false; };
struct Scene {
  int schemaVersion=1,frames=240,fps=24;
  std::string title="CartoRig Map";
  Camera camera; Style style;
  std::vector<CameraKey> cameraKeys;
  std::vector<std::string> highlighted;
  std::vector<Marker> markers;
  std::vector<Route> routes;
};
struct View { int width=1920,height=1080; Camera camera; double frame=0, routeProgress=-1; bool preserveBackground=false; };
enum class PixelFormat { ByteRGBA, FloatRGBA };
struct Surface {
  void *data=nullptr; int x1=0,y1=0,x2=0,y2=0,rowBytes=0; PixelFormat format=PixelFormat::ByteRGBA;
  // Pixel coordinates use the OpenFX convention (origin at bottom-left).
};
struct RasterStats { uint64_t written=0; };
std::string readText(const std::string &path, size_t limit=16*1024*1024);
Dataset parseGeoJSON(const std::string &json);
Scene parseScene(const std::string &json);
Camera evaluateCamera(const Scene &s, double frame);
double routeFraction(const Route &r, double frame);
double normalizeLon(double lon);
ScreenPoint project(GeoPoint p, const Camera &camera, int width, int height);
GeoPoint unproject(ScreenPoint p, const Camera &camera, int width, int height);
Camera fitBounds(const std::vector<GeoPoint>& points, int width,int height,double padding=0.08);
// Intersect an OFX image allocation with the RenderWindow without copying pixels.
// The returned data pointer is rebased to (x1,y1) and supports negative rowBytes.
// An empty intersection returns data=nullptr.
Surface cropSurface(Surface image,int x1,int y1,int x2,int y2);
// Pure pixel-pattern diagnostics. Intentionally bypasses all geography, caching, blending
// and OFX host code to isolate output pixel packing, stride, bounds, and alpha.
// 1=red/green/blue/white bars; 2=gray ramp; 3=alpha split; 4=solid white.
void renderDiagnosticPattern(Surface target,int width,int height,int mode);
void render(const Scene &scene,const Dataset &data,const View &view,Surface dst, RasterStats *stats=nullptr);
}
