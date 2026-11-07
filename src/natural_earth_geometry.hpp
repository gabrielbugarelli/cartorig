#pragma once
// GeoPackage geometry decoding for the native offline geographic engine.
// RFC/OGC: GeoPackage binary header followed by OGC WKB; coordinates EPSG:4326.
#include "cartorig.hpp"
#include <cstddef>
#include <cstdint>
#include <vector>

namespace cartorig {
struct NaturalEarthGeometry {
  std::int32_t srsId=0;
  std::vector<GeoPoint> points;
  std::vector<std::vector<GeoPoint>> lines;
  std::vector<Polygon> polygons;
  bool empty()const{return points.empty()&&lines.empty()&&polygons.empty();}
};
NaturalEarthGeometry decodeGeoPackageGeometry(const void*blob,std::size_t size);
 // Overlay publisher vector data on the already rendered CartoRig image.
 // The layer is not a replacement for the countries baseline.
 void renderNaturalEarthLayer(const std::vector<NaturalEarthGeometry> &geometries,
                              const View &view,Surface target,
                              Color polygonFill,Color lineColor,Color pointColor,
                              RasterStats *stats=nullptr);

} // namespace cartorig
