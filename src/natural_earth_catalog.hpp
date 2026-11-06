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
  // Directly convert the offline Natural Earth country layer at a chosen
  // scale to the existing proven CPU map renderer's country Dataset. The
  // GeoPackage is opened READ-ONLY; no network or import-time mutations.
  static Dataset countryPolygons(const std::filesystem::path &geoPackage,
                                 const std::string &scale);
  // Read one explicitly selected official vector table, including Point,
  // LineString and Polygon features. Bounded, read-only, and fail-closed;
  // a separate large-data-pack renderer will eventually stream by viewport.
  static std::vector<NaturalEarthGeometry> layerGeometries(
      const std::filesystem::path &geoPackage,const std::string &table,
      std::size_t maxFeatures=20000);

};
} // namespace cartorig
