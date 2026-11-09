#pragma once
#include "cartorig/geo.hpp"
#include <string>

namespace cartorig::rc1 {
enum class TextAlign{Left,Center,Right};
struct LabelOptions {
  GeoPoint at;
  std::string text;              // valid UTF-8 text
  std::string fontFamily="Sans"; // Windows installed font family
  double fontSize=32;
  double offsetX=0,offsetY=0;
  double haloWidth=2;
  double opacity=1;
  TextAlign alignment=TextAlign::Center;
  bool halo=true;
  Color fill{240,245,248,255},haloColor{11,22,33,255};
};
void drawLabel(Surface&surface,const Camera&camera,const LabelOptions&label);
} // cartorig::rc1
