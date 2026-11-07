#include "native_controls.hpp"
#include <algorithm>
#include <cctype>
#include <cmath>
#include <utility>
#include <stdexcept>

namespace cartorig {
namespace {
void requireFinite(double value,const char *what) {
  if(!std::isfinite(value))throw std::invalid_argument(what);
}
void requireGeo(GeoPoint p) {
  requireFinite(p.lon,"longitude must be finite");
  requireFinite(p.lat,"latitude must be finite");
  if(p.lat< -85.0511287798066||p.lat>85.0511287798066||
     p.lon< -540||p.lon>540)
    throw std::invalid_argument("native route coordinates outside geographic limits");
}
} // namespace

std::string normalizedISO3(const std::string &raw) {
  const auto start=raw.find_first_not_of(" \t\r\n");
  if(start==std::string::npos)return {};
  const auto end=raw.find_last_not_of(" \t\r\n");
  if(end-start+1!=3)return {};
  std::string iso;
  for(size_t i=start;i<=end;++i){
    const unsigned char c=static_cast<unsigned char>(raw[i]);
    if(c<'A'||c>'Z') {
      if(c<'a'||c>'z')return {};
      iso.push_back(static_cast<char>(c-'a'+'A'));
    }else iso.push_back(static_cast<char>(c));
  }
  return iso;
}

Scene sceneWithNativeControls(const Scene &original,const NativeMapControls &n) {
  requireFinite(n.highlightStrength,"invalid highlight strength");
  requireFinite(n.routeCurve,"invalid route curvature");
  requireFinite(n.routeWidth,"invalid route width");
  if(n.highlightStrength<0||n.highlightStrength>1||n.routeWidth<.5||
     n.routeWidth>30||n.routeCurve< -100||n.routeCurve>100)
    throw std::invalid_argument("native control out of range");
  Scene s=original;
  if(n.customColors){
    s.style.ocean=n.ocean;s.style.land=n.land;s.style.highlight=n.highlight;
  }
  s.style.highlight.a=static_cast<uint8_t>(
    std::lround(s.style.highlight.a*n.highlightStrength));
  auto addCountry=[&](const std::string &raw){
    const auto iso=normalizedISO3(raw);
    if(!iso.empty()&&std::find(s.highlighted.begin(),s.highlighted.end(),iso)==s.highlighted.end())
      s.highlighted.push_back(iso);
  };
  addCountry(n.countryA);addCountry(n.countryB);
  if(n.countryList.size()>4096)
    throw std::invalid_argument("native country list exceeds size limit");
  std::string token;size_t tokenCount=0;
  for(size_t i=0;i<=n.countryList.size();++i){
    const char ch=i<n.countryList.size()?n.countryList[i]:',';
    if(ch==','||ch==';'||ch==' '||ch=='\t'||ch=='\r'||ch=='\n'){
      if(!token.empty()){
        if(++tokenCount>256)throw std::invalid_argument("too many native country IDs");
        addCountry(token);
        token.clear();
      }
    }else{
      if(token.size()<=12)token.push_back(ch);
    }
  }
  if(n.routeEnabled){
    requireGeo(n.routeStart);requireGeo(n.routeEnd);
    if(n.startLabel.size()>48||n.endLabel.size()>48)
      throw std::invalid_argument("native route label too long");
    const std::string fromId="__cartorig_native_route_from__";
    const std::string toId="__cartorig_native_route_to__";
    for(const auto &m:s.markers)
      if(m.id==fromId||m.id==toId)
        throw std::invalid_argument("reserved native marker identifier");
    Marker start;start.id=fromId;start.at=n.routeStart;start.label=n.startLabel;
    start.visible=n.routeMarkers;
    Marker end;end.id=toId;end.at=n.routeEnd;end.label=n.endLabel;
    end.visible=n.routeMarkers;
    s.markers.push_back(std::move(start));
    s.markers.push_back(std::move(end));
    Route route;route.id="__cartorig_native_route__";route.from=fromId;route.to=toId;
    route.curve=n.routeCurve;route.width=n.routeWidth;route.arrowhead=n.routeArrowhead;route.color=n.routeColor;
    route.start=0;route.end=1;
    s.routes.push_back(std::move(route));
  }
  return s;
}
} // namespace cartorig
