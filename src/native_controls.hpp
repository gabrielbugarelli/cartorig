#pragma once
#include "cartorig.hpp"
#include <string>

namespace cartorig {

// Edit page native Inspector settings. No cartographic motion is generated
// unless a user explicitly creates keyframes or enables an imported scene.
struct NativeMapControls {
  std::string countryA, countryB, countryList;
  double highlightStrength=1.0;
  bool customColors=false;
  Color ocean{13,30,50,255}, land{35,59,82,255}, highlight{40,157,192,220};

  bool routeEnabled=false;
  GeoPoint routeStart{-20,0},routeEnd{20,0};
  double routeCurve=20.0,routeWidth=3.0;
  bool routeArrowhead=true;
  Color routeColor{255,200,100,255};
  bool routeMarkers=true;
  std::string startLabel,endLabel;
};

// Normalizes exact ISO 3166-1 alpha-3 identifiers without inventing matches.
// An empty or malformed code returns an empty string.
std::string normalizedISO3(const std::string &raw);

// Creates a per-frame copy without mutating any shared cached scene.
// Native controls are compositional: unused controls leave imported scenes
// untouched; no synthetic route/markers are inserted by default.
Scene sceneWithNativeControls(const Scene &original,const NativeMapControls &controls);
} // namespace cartorig
