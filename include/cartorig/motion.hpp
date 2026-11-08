#pragma once
// CartoRig RC1 temporal-domain engine. All motion values remain native-capable
// scalar channels; the Fusion adapter must expose them as Spline keyframes.
#include <map>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace cartorig::rc1 {
enum class Easing { Linear, Smooth, Hold };
enum class Conflict { Reject, ReplaceAffected };
enum class Removal { KeepManual, DeleteOwnedKeys };
struct Key {
  double value=0;
  Easing easing=Easing::Smooth;
  std::string owner; // Empty for manually authored keys
};
struct Track {
  double base=0;
  std::map<int,Key> keys;
  double evaluate(double frame) const;
};
struct Preset {
  std::string id;
  std::string objectType;
  std::vector<std::string> channels;
  int suggestedFrames=24;
};
struct Request {
  int start=0,delay=0,duration=24;
  std::unordered_map<std::string,double> target;
  Conflict conflict=Conflict::Reject;
  Easing easing=Easing::Smooth;
};
class Motion {
public:
  Motion();
  const std::vector<Preset>& catalog() const{return catalog_;}
  const Preset& preset(const std::string&id) const;
  void setBase(const std::string&channel,double value);
  double at(const std::string&channel,double frame) const;
  const Track& track(const std::string&channel) const;
  void apply(const std::string&id,const Request&request);
  void editManualKey(const std::string&channel,int frame,double value,
                     Easing easing=Easing::Smooth);
  void update(const Request&request);
  void remove(Removal mode);
  bool customized() const;
  std::string activePreset() const{return active_;}
  std::vector<std::string> conflicts(const std::string&id,
                                     int first,int last) const;
private:
  std::vector<Preset> catalog_;
  std::unordered_map<std::string,Track> tracks_;
  std::string active_;
  std::unordered_map<std::string,std::map<int,Key>> ownedSnapshot_;
  Request lastRequest_;
  void install(const Preset&,const Request&);
};
} // namespace cartorig::rc1
