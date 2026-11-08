#include "cartorig/motion.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace cartorig::rc1 {
namespace {
void valid(bool condition,const char*message){
 if(!condition)throw std::invalid_argument(message);
}
bool inRange(int a,int b){return a>=0&&b>=0&&a<=1000000000&&b<=1000000000;}
double interpolate(double a,double b,double u,Easing ease){
 u=std::clamp(u,0.,1.);
 if(ease==Easing::Hold)return a;
 if(ease==Easing::Smooth)u=u*u*(3-2*u);
 return a+(b-a)*u;
}
bool equal(const Key&a,const Key&b){
 return a.value==b.value&&a.easing==b.easing&&a.owner==b.owner;
}
}
double Track::evaluate(double frame) const{
 if(keys.empty())return base;
 auto right=keys.upper_bound(static_cast<int>(std::floor(frame)));
 if(right==keys.begin())return right->second.value;
 auto left=std::prev(right);
 if(right==keys.end())return left->second.value;
 double duration=right->first-left->first;
 return interpolate(left->second.value,right->second.value,
                    (frame-left->first)/duration,left->second.easing);
}
Motion::Motion(){
 const auto add=[&](const char*id,const char*type,std::vector<std::string>channels,
                    int defaultFrames=24){
  catalog_.push_back({id,type,std::move(channels),defaultFrames});
 };
 add("MO-REG-01","Region",{"ObjectOpacity"});
 add("MO-REG-02","Region",{"ObjectOpacity"});
 add("MO-REG-03","Region",{"FillR","FillG","FillB"});
 add("MO-REG-04","Region",{"FillR","FillG","FillB"},1);
 add("MO-REG-05","Region",{"StrokeProgress"});
 add("MO-REG-06","Region",{"HighlightStrength"},32);
 add("MO-RTE-01","Route",{"DrawProgress"});
 add("MO-RTE-02","Route",{"DrawProgress"});
 add("MO-RTE-03","Route",{"FollowerProgress"});
 add("MO-MRK-01","Marker",{"ObjectOpacity"});
 add("MO-MRK-02","Marker",{"Size"});
 add("MO-CAM-01","Camera",{"Longitude","Latitude","Zoom","Bearing"});
 add("MO-CAM-02","Camera",{"Zoom"});
 add("MO-CAM-03","Camera",{"Longitude","Latitude","Zoom"});
 add("MO-LBL-01","Label",{"ObjectOpacity"});
 add("MO-MAP-01","Base Map",{"LayerOpacity"});
}
const Preset& Motion::preset(const std::string&id)const{
 auto it=std::find_if(catalog_.begin(),catalog_.end(),
   [&](const auto&p){return p.id==id;});
 if(it==catalog_.end())throw std::invalid_argument("Unknown Motion preset");
 return *it;
}
void Motion::setBase(const std::string&channel,double value){
 valid(!channel.empty()&&std::isfinite(value),"Invalid base channel");
 tracks_[channel].base=value;
}
double Motion::at(const std::string&channel,double frame)const{
 valid(std::isfinite(frame),"Invalid evaluation frame");
 auto it=tracks_.find(channel);
 return it==tracks_.end()?0:it->second.evaluate(frame);
}
const Track& Motion::track(const std::string&channel)const{
 auto it=tracks_.find(channel);
 if(it==tracks_.end())throw std::invalid_argument("Unknown animation channel");
 return it->second;
}
std::vector<std::string> Motion::conflicts(const std::string&id,int first,int last)const{
 valid(inRange(first,last)&&first<=last,"Invalid animation interval");
 std::vector<std::string> result;
 for(const auto&name:preset(id).channels){
  auto it=tracks_.find(name);
  if(it==tracks_.end())continue;
  auto a=it->second.keys.lower_bound(first);
  if(a!=it->second.keys.end()&&a->first<=last)result.push_back(name);
 }
 return result;
}
void Motion::install(const Preset&p,const Request&req){
 const int start=req.start+req.delay;
 const int end=start+(p.id=="MO-REG-04"?1:req.duration);
 const auto put=[&](const std::string&channel,int frame,double value,Easing easing){
  valid(std::isfinite(value),"Invalid Motion key value");
  tracks_[channel].keys[frame]={value,easing,p.id};
 };
 const auto value=[&](const std::string&channel){
  auto it=tracks_.find(channel);
  return it==tracks_.end()?0:it->second.evaluate(start);
 };
 const auto requested=[&](const std::string&channel,double fallback,bool required=false){
  auto it=req.target.find(channel);
  valid(it!=req.target.end()||!required,"Motion target missing");
  return it==req.target.end()?fallback:it->second;
 };
 const bool fadeIn=p.id=="MO-REG-01"||p.id=="MO-MRK-01"||
                   p.id=="MO-LBL-01"||p.id=="MO-MAP-01";
 const bool fadeOut=p.id=="MO-REG-02";
 const bool draw=p.id=="MO-RTE-01"||p.id=="MO-REG-05"||
                 p.id=="MO-RTE-03";
 const bool erase=p.id=="MO-RTE-02";
 if(fadeIn||fadeOut||draw||erase){
  const auto&channel=p.channels[0];
  const double existing=value(channel);
  double lo=0,hi=requested(channel,existing==0?1:existing);
  if(fadeOut){lo=existing;hi=0;}
  else if(erase){lo=1;hi=0;}
  else if(draw){lo=0;hi=1;}
  put(channel,start,lo,req.easing);
  put(channel,end,hi,req.easing);
 }else if(p.id=="MO-REG-06"){
  double peak=requested("HighlightStrength",1);
  valid(peak>=0&&peak<=1,"Highlight pulse strength outside [0,1]");
  put("HighlightStrength",start,0,req.easing);
  put("HighlightStrength",start+req.duration/2,peak,req.easing);
  put("HighlightStrength",end,0,req.easing);
 }else if(p.id=="MO-MRK-02"){
  double target=requested("Size",value("Size"));
  valid(target>=0&&target<=128,"Marker target size outside limits");
  put("Size",start,0,req.easing);
  put("Size",start+std::max(1,req.duration*3/4),target*1.12,req.easing);
  put("Size",end,target,req.easing);
 }else{
  // Camera and color transitions are channel-wise; RGB channels and
  // geography are authored as native individual splines.
  for(const auto&channel:p.channels){
   double base=value(channel);
   bool required=(p.id=="MO-CAM-01"||p.id=="MO-CAM-03"||
                  p.id=="MO-REG-03"||p.id=="MO-REG-04");
   double finish=requested(channel,base,required);
   if(channel=="Longitude"){
    finish=base+std::remainder(finish-base,360.);
   }
   put(channel,start,base,p.id=="MO-REG-04"?Easing::Hold:req.easing);
   put(channel,end,finish,req.easing);
  }
 }
}
void Motion::apply(const std::string&id,const Request&req){
 const auto&p=preset(id);
 valid(req.duration>=1&&req.duration<=100000&&req.delay>=0&&
       inRange(req.start,req.start+req.delay+req.duration+1),
       "Invalid Motion time window");
 valid(active_.empty(),"Remove or update the existing Motion preset first");
 auto conflict=conflicts(id,req.start+req.delay,
                              req.start+req.delay+req.duration+1);
 valid(conflict.empty()||req.conflict==Conflict::ReplaceAffected,
       "Existing animated channel conflicts with preset");
 auto previous=tracks_;
 try{
  if(req.conflict==Conflict::ReplaceAffected){
   for(const auto&name:p.channels){
    auto&keys=tracks_[name].keys;
    auto first=keys.lower_bound(req.start+req.delay);
    auto last=keys.upper_bound(req.start+req.delay+req.duration+1);
    keys.erase(first,last);
   }
  }
  install(p,req);
 }catch(...){tracks_=std::move(previous);throw;}
 active_=id;lastRequest_=req;
 ownedSnapshot_.clear();
 for(const auto&name:p.channels)ownedSnapshot_[name]=tracks_[name].keys;
}
void Motion::editManualKey(const std::string&channel,int frame,double v,Easing e){
 valid(inRange(frame,frame)&&std::isfinite(v),"Invalid manual key");
 tracks_[channel].keys[frame]={v,e,""};
}
bool Motion::customized()const{
 if(active_.empty())return false;
 for(const auto&[name,snapshot]:ownedSnapshot_){
  auto it=tracks_.find(name);
  if(it==tracks_.end()||it->second.keys.size()!=snapshot.size())return true;
  auto jt=it->second.keys.begin();
  for(auto kt=snapshot.begin();kt!=snapshot.end();++kt,++jt){
   if(jt==it->second.keys.end()||jt->first!=kt->first||
      !equal(jt->second,kt->second))return true;
  }
 }
 return false;
}
void Motion::update(const Request&request){
 valid(!active_.empty(),"No active Motion preset");
 valid(!customized(),"Preset is Customized; choose an explicit recovery policy");
 const auto id=active_;
 const auto previous=*this;
 try{
  remove(Removal::DeleteOwnedKeys);
  apply(id,request);
 }catch(...){*this=previous;throw;}
}
void Motion::remove(Removal mode){
 if(active_.empty())return;
 for(auto&[name,track]:tracks_){
  for(auto it=track.keys.begin();it!=track.keys.end();){
   if(it->second.owner==active_){
    if(mode==Removal::DeleteOwnedKeys)it=track.keys.erase(it);
    else {it->second.owner.clear();++it;}
   }else ++it;
  }
 }
 active_.clear();ownedSnapshot_.clear();
}
} // namespace cartorig::rc1
