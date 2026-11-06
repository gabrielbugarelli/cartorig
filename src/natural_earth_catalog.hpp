#pragma once
// Offline read-only Natural Earth search interface, independent of OFX UI.
// The data index is built by tools/natural_earth/build_catalog.py.
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>
#include "natural_earth_geometry.hpp"
namespace cartorig {
struct NaturalEarthRegion {
  std::string featureKey,kind,name,parent,geometryType,sourceLayer,scale;
  std::int64_t sourceRowId=0;
  bool hasGeometry=false;
};
struct NaturalEarthCatalog {
  static std::vector<NaturalEarthRegion> search(const std::filesystem::path &database,
                                                const std::string &text,
                                                const std::string &kind,
                                                int limit=20);
  // Fetch true publisher WKB geometry from the installed GeoPackage by the
  // stable source layer/row reference returned by search(). Read-only and
  // strictly validated. Does not fabricate city administrative boundaries.
  static NaturalEarthGeometry featureGeometry(
      const std::filesystem::path &geoPackage,const NaturalEarthRegion &region);
};
} // namespace cartorig
