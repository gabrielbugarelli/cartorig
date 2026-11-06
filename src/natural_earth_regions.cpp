#include "natural_earth_regions.hpp"
#include "json11.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace cartorig {
namespace {
void validate(const GeographicRegionSelection &region){
  if(region.featureKey.empty()||region.featureKey.size()>255||
     region.name.empty()||region.name.size()>255||
     region.parent.size()>255||region.sourceLayer.empty()||
     region.sourceLayer.size()>128||region.scale.size()>16||
     (region.kind!="continent"&&region.kind!="country"&&
      region.kind!="state"&&region.kind!="city")||
     (region.kind=="continent" ? region.sourceRowId!=0 :
                                 region.sourceRowId<1))
    throw std::invalid_argument("invalid Natural Earth geographic region selection");
}
std::string requiredString(const json11::Json &j,const char* key){
  if(!j[key].is_string())throw std::invalid_argument("invalid geographic region text");
  return j[key].string_value();
}
} // namespace
std::vector<GeographicRegionSelection> parseGeographicSelections(
    const std::string &source){
  if(source.empty())return {};
  if(source.size()>128*1024)
    throw std::invalid_argument("too many persisted geographic regions");
  std::string error;
  const auto root=json11::Json::parse(source,error);
  if(!error.empty()||!root.is_array()||root.array_items().size()>64)
    throw std::invalid_argument("invalid persisted geographic regions JSON");
  std::vector<GeographicRegionSelection> results;
  for(const auto &item:root.array_items()){
    if(!item.is_object())
      throw std::invalid_argument("invalid persisted region record");
    GeographicRegionSelection r;
    r.featureKey=requiredString(item,"feature_key");
    r.kind=requiredString(item,"kind");
    r.name=requiredString(item,"name");
    r.parent=requiredString(item,"parent");
    r.sourceLayer=requiredString(item,"source_layer");
    r.scale=requiredString(item,"scale");
    const auto id=item["rowid"];
    if(!id.is_number()||!std::isfinite(id.number_value())||
       std::floor(id.number_value())!=id.number_value()||
       id.number_value()>9.0e15)
      throw std::invalid_argument("invalid Natural Earth geographic row ID");
    r.sourceRowId=static_cast<std::int64_t>(id.number_value());
    const auto &c=item["fill"].array_items();
    if(c.size()!=4)throw std::invalid_argument("invalid region fill color");
    std::uint8_t rgba[4]{};
    for(int index=0;index<4;++index){
      if(!c[index].is_number()||!std::isfinite(c[index].number_value())||
         c[index].number_value()<0||c[index].number_value()>255||
         std::floor(c[index].number_value())!=c[index].number_value())
        throw std::invalid_argument("invalid region RGBA channel");
      rgba[index]=static_cast<std::uint8_t>(c[index].number_value());
    }
    r.fill={rgba[0],rgba[1],rgba[2],rgba[3]};
    validate(r);
    if(std::any_of(results.begin(),results.end(),[&](const auto &e){
         return e.featureKey==r.featureKey;}))
      throw std::invalid_argument("duplicate Natural Earth geographic region ID");
    results.push_back(std::move(r));
  }
  return results;
}
std::string saveGeographicSelections(
    const std::vector<GeographicRegionSelection> &items){
  if(items.size()>64)
    throw std::invalid_argument("too many Natural Earth selected regions");
  json11::Json::array list;
  for(const auto &r:items){
    validate(r);
    list.push_back(json11::Json::object{
      {"feature_key",r.featureKey},{"kind",r.kind},{"name",r.name},
      {"parent",r.parent},{"source_layer",r.sourceLayer},
      {"scale",r.scale},{"rowid",static_cast<double>(r.sourceRowId)},
      {"fill",json11::Json::array{
        static_cast<int>(r.fill.r),static_cast<int>(r.fill.g),
        static_cast<int>(r.fill.b),static_cast<int>(r.fill.a)}}
    });
  }
  return json11::Json(list).dump();
}
std::string upsertGeographicSelection(
    const std::string &json,const GeographicRegionSelection &selection){
  validate(selection);
  auto items=parseGeographicSelections(json);
  const auto it=std::find_if(items.begin(),items.end(),[&](const auto &entry){
    return entry.featureKey==selection.featureKey;
  });
  if(it!=items.end())*it=selection;else items.push_back(selection);
  return saveGeographicSelections(items);
}
std::string removeGeographicSelection(
    const std::string &json,const std::string &featureKey){
  auto items=parseGeographicSelections(json);
  items.erase(std::remove_if(items.begin(),items.end(),[&](const auto &entry){
    return entry.featureKey==featureKey;
  }),items.end());
  return saveGeographicSelections(items);
}
} // namespace cartorig
