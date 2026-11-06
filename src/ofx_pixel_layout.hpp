#pragma once
#include <cstdint>
#include <string_view>

namespace cartorig {
enum class OfxLayout { Reject, RGBA, Resolve20FloatRGBAUnspecified };

// OpenFX requires valid RGBA component metadata for an RGBA image.
// Resolve Studio 20 was observed to return 'OfxImageComponentNone' on
// a Generator while allocating exactly 4 tightly-packed float channels.
// This narrow compatibility path is NOT a general None-to-RGBA coercion.
inline OfxLayout classifyOfxLayout(
    std::string_view components,std::string_view depth,
    int x1,int y1,int x2,int y2,int rowBytes,bool generator) noexcept {
  const int64_t w=static_cast<int64_t>(x2)-x1;
  const int64_t h=static_cast<int64_t>(y2)-y1;
  if(w<=0||h<=0||w>16384||h>16384||rowBytes==0)return OfxLayout::Reject;
  const int bytes=depth=="OfxBitDepthFloat"?16:
                  depth=="OfxBitDepthByte"?4:0;
  if(!bytes)return OfxLayout::Reject;
  const int64_t pitch=rowBytes<0?-static_cast<int64_t>(rowBytes):rowBytes;
  const int64_t expected=w*bytes;
  if(pitch<expected)return OfxLayout::Reject;
  if(components=="OfxImageComponentRGBA")return OfxLayout::RGBA;
  if(generator&&components=="OfxImageComponentNone"&&
     depth=="OfxBitDepthFloat"&&rowBytes==expected)
    return OfxLayout::Resolve20FloatRGBAUnspecified;
  return OfxLayout::Reject;
}
} // namespace cartorig
