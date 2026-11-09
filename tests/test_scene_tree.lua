local model=dofile("fusion/CartoRigSupport/scene_tree.lua")
local function check(value,message)if not value then error("FAIL "..message,2)end end
local objects={
 {id="map",role="Base Map",name="Base",z=0,visible=true},
 {id="cam",role="Camera",name="Camera",z=0,visible=true},
 {id="region",role="Region",name="Rio State",z=2,visible=true},
 {id="route",role="Route",name="Brasilia / Amapa",z=1,visible=true},
 {id="group",role="Group",name="My group",z=4,visible=true},
 {id="marker",role="Marker",name="Sao Paulo",z=5,parent="group",visible=false},
 {id="label",role="Label",name="São Paulo",z=6,parent="group",locked=true}
}
local roots=model.build(objects)
check(#roots==7,"all Scene sections present")
check(roots[1].name=="Base Map" and roots[2].name=="Camera",
      "base visual and camera nodes remain first")
check(roots[3].children[1].id=="region","Region bucket")
check(roots[4].children[1].id=="route","Route bucket")
check(#roots[5].children==0 and #roots[6].children==0,
      "grouped authored objects are never duplicated at root")
check(roots[7].children[1].id=="group" and
      #roots[7].children[1].children==2,"hierarchy retained")
check(roots[7].children[1].children[1].id=="marker" and
      roots[7].children[1].children[2].id=="label",
      "grouped children keep stable global order")
local lookup={}
for _,obj in ipairs(objects)do lookup[obj.id]=obj end
local selected=model.eligible({"marker","marker","label"},lookup,"hide")
check(#selected==2,"multi-selection is deduplicated")
local ok=pcall(function()model.eligible({"map"},lookup,"delete")end)
check(not ok,"protected Scene objects cannot be deleted")
ok=pcall(function()model.eligible({"removed"},lookup,"hide")end)
check(not ok,"stale multi-selection fails closed")
local broken={}
for _,obj in ipairs(objects)do broken[#broken+1]=obj end
broken[#broken+1]=objects[1]
ok=pcall(function()model.build(broken)end)
check(not ok,"duplicate object ID rejected")
print("PASS Scene tree: seven buckets, grouped hierarchy, stable Z, multiselect, protected IDs")
