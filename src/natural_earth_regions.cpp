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
  if(region.colorKeys.size()>64)
    throw std::invalid_argument("too many animation keys for region");
  double previous=-1.0e10;
  for(const auto &key:region.colorKeys){
    if(!std::isfinite(key.frame)||std::abs(key.frame)>1.0e9||
       key.frame<=previous||
       (key.easing!="linear"&&key.easing!="smoothstep"&&key.easing!="hold"))
      throw std::invalid_argument("invalid geographic region animation timeline");
    previous=key.frame;
  }
}
std::string requiredString(const json11::Json &j,const char* key){
  if(!j[key].is_string())throw std::invalid_argument("invalid geographic region text");
  return j[key].string_value();
}
} // namespace
std::vector<GeographicRegionSelection> parseGeographicSelections(
    const std::string &source){
  if(source.empty())return {};
  if(source.size()>512*1024)
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
    if(item["color_keys"].is_array()){
      for(const auto &key:item["color_keys"].array_items()){
        if(!key.is_object()||!key["frame"].is_number())
          throw std::invalid_argument("malformed region animation key");
        GeographicRegionColorKey stored;
        stored.frame=key["frame"].number_value();
        stored.easing=requiredString(key,"easing");
        const auto colors=key["color"].array_items();
        if(colors.size()!=4)
          throw std::invalid_argument("malformed geographic region keyframe RGBA");
        std::uint8_t v[4]{};
        for(int i=0;i<4;++i){
          const auto &ch=colors[static_cast<std::size_t>(i)];
          if(!ch.is_number()||!std::isfinite(ch.number_value())||
             ch.number_value()<0||ch.number_value()>255||
             std::floor(ch.number_value())!=ch.number_value())
            throw std::invalid_argument("invalid keyed region color channel");
          v[i]=static_cast<std::uint8_t>(ch.number_value());
        }
        stored.color={v[0],v[1],v[2],v[3]};
        r.colorKeys.push_back(std::move(stored));
      }
    }else if(!item["color_keys"].is_null()){
      throw std::invalid_argument("geographic color keys must be array");
    }
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
    json11::Json::array keys;
    for(const auto &key:r.colorKeys){
      keys.push_back(json11::Json::object{
        {"frame",key.frame},{"easing",key.easing},
        {"color",json11::Json::array{
          static_cast<int>(key.color.r),static_cast<int>(key.color.g),
          static_cast<int>(key.color.b),static_cast<int>(key.color.a)}}
      });
    }
    list.push_back(json11::Json::object{
      {"feature_key",r.featureKey},{"kind",r.kind},{"name",r.name},
      {"parent",r.parent},{"source_layer",r.sourceLayer},
      {"scale",r.scale},{"rowid",static_cast<double>(r.sourceRowId)},
      {"fill",json11::Json::array{
        static_cast<int>(r.fill.r),static_cast<int>(r.fill.g),
        static_cast<int>(r.fill.b),static_cast<int>(r.fill.a)}},
      {"color_keys",std::move(keys)}
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
  if(it!=items.end()){
    auto replacement=selection;
    if(replacement.colorKeys.empty())replacement.colorKeys=it->colorKeys;
    *it=std::move(replacement);
  }else items.push_back(selection);
  return saveGeographicSelections(items);
}
std::string upsertGeographicColorKey(
    const std::string &json,const std::string &featureKey,double frame,
    Color color,const std::string &easing){
  if(!std::isfinite(frame)||std::abs(frame)>1.0e9||
     (easing!="linear"&&easing!="smoothstep"&&easing!="hold"))
    throw std::invalid_argument("invalid geographic keyframe time or easing");
  auto items=parseGeographicSelections(json);
  const auto found=std::find_if(items.begin(),items.end(),[&](const auto &item){
    return item.featureKey==featureKey;
  });
  if(found==items.end())
    throw std::invalid_argument("cannot animate nonselected geographic region");
  auto &keys=found->colorKeys;
  const auto key=std::lower_bound(keys.begin(),keys.end(),frame,
       [](const auto &existing,double at){return existing.frame<at;});
  const GeographicRegionColorKey value{frame,color,easing};
  if(key!=keys.end()&&key->frame==frame)*key=value;
  else keys.insert(key,value);
  return saveGeographicSelections(items);
}
Color evaluateGeographicRegionColor(const GeographicRegionSelection &region,
                                    double frame){
  if(!std::isfinite(frame))
    throw std::invalid_argument("invalid geographic animation evaluation time");
  const auto &keys=region.colorKeys;
  if(keys.empty())return region.fill;
  if(frame<=keys.front().frame)return keys.front().color;
  if(frame>=keys.back().frame)return keys.back().color;
  const auto after=std::upper_bound(keys.begin(),keys.end(),frame,
       [](double at,const auto &key){return at<key.frame;});
  const auto &a=*(after-1),&b=*after;
  double progress=(frame-a.frame)/(b.frame-a.frame);
  if(a.easing=="hold")progress=0;
  else if(a.easing=="smoothstep")progress=progress*progress*(3-2*progress);
  const auto blend=[&](std::uint8_t lhs,std::uint8_t rhs){
    return static_cast<std::uint8_t>(std::lround(
        lhs+(static_cast<double>(rhs)-lhs)*progress));
  };
  return {blend(a.color.r,b.color.r),blend(a.color.g,b.color.g),
          blend(a.color.b,b.color.b),blend(a.color.a,b.color.a)};
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
