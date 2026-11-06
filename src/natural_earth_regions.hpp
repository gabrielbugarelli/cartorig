#pragma once
// Persistent, per-feature style records embedded into the Resolve project.
// Only publisher geometry IDs are retained; actual geometry is reloaded
// offline from the installed Natural Earth GeoPackage on each machine.
#include "cartorig.hpp"
#include <cstdint>
#include <string>
#include <vector>
namespace cartorig {
struct GeographicRegionSelection {
  std::string featureKey,kind,name,parent,sourceLayer,scale;
  std::int64_t sourceRowId=0;
  Color fill{40,157,192,220};
};
std::vector<GeographicRegionSelection> parseGeographicSelections(
    const std::string &json);
std::string saveGeographicSelections(
    const std::vector<GeographicRegionSelection> &selections);
std::string upsertGeographicSelection(
    const std::string &json,const GeographicRegionSelection &selection);
std::string removeGeographicSelection(
    const std::string &json,const std::string &featureKey);
} // namespace cartorig
