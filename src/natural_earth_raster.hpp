#pragma once
// Immutable, geographically registered Natural Earth RGBA-tile atlas.
// Image conversion is performed OFFLINE by build_rasters.py, not inside Resolve.
#include "cartorig.hpp"
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>
namespace cartorig {
struct NaturalEarthRasterLevel {
  int z=0,width=0,height=0,tilesX=0,tilesY=0;
};
struct NaturalEarthRasterAsset {
  std::string assetId;
  std::string sourceId;
};
std::vector<NaturalEarthRasterAsset> listNaturalEarthRasterAssets(
    const std::filesystem::path &root);
struct NaturalEarthRaster {
  std::filesystem::path directory;
  std::string assetId;
  bool compressedPng=false; // v2 .png atlas tiles, v1 raw RGBA remains supported
  double west=-180,south=-90,east=180,north=90;
  std::vector<NaturalEarthRasterLevel> levels;
};
// A malformed pack fails closed rather than silently falling back to an
// inaccurate map projection or fetching remote assets.
NaturalEarthRaster loadNaturalEarthRaster(
    const std::filesystem::path &root,const std::string &assetId);
void renderNaturalEarthRaster(const NaturalEarthRaster &raster,
                              const View &view,Surface target,
                              RasterStats *stats=nullptr);
} // namespace cartorig
