local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local s=Scene.new('camera-bearing-0101');local camera=s.objects[2]
camera.style.bearing=170
local base={start=20,frameCount=200,targetPose={longitude=20,latitude=5,zoom=3,bearing=-170}}
local plain=Motion.prepare(camera,'MO-CAM-01',base,{})
assert(not plain.channels.bearing,'bearing must be opt-in for Fly To')
local requested={start=20,frameCount=200,animateBearing=true,targetPose=base.targetPose}
local fly=Motion.prepare(camera,'MO-CAM-01',requested,{})
assert(fly.channels.bearing[1].value==170 and fly.channels.bearing[2].value==190)
local fit=Motion.prepare(camera,'MO-CAM-03',{start=20,frameCount=200,
  bearingMode='Reset',targetPose=base.targetPose},{})
assert(fit.channels.bearing[1].value==170 and fit.channels.bearing[2].value==0)
assert(not Motion.prepare(camera,'MO-CAM-03',{start=20,frameCount=200,
  bearingMode='Preserve',targetPose=base.targetPose},{}).channels.bearing)
assert(not pcall(function()Motion.prepare(camera,'MO-CAM-01',{start=20,frameCount=200,
  animateBearing=true,targetPose={longitude=0,latitude=0,zoom=1,bearing=math.huge}},{})end))
local tool={data={},keys={},mods={}}
function tool:GetData(k)return self.data[k]end
function tool:SetData(k,v)self.data[k]=v end
function tool:AddModifier(k,method)self.mods[k]=method;return true end
function tool:SetInput(k,v,f)self.keys[k]=self.keys[k]or{};self.keys[k][f]=v;return true end
local host={comp={StartUndo=function()end,EndUndo=function()end},tool_for=function()return tool end}
assert(Writer.apply(host,camera,fly))
assert(tool.keys.Bearing[20]==170 and tool.keys.Bearing[65]==190)
assert(tool.keys.CenterLongitude and tool.keys.Zoom and tool.keys.CenterLatitude)
print('PASS opt-in camera Bearing: shortest arc, native keyframes, reset north and validation')
