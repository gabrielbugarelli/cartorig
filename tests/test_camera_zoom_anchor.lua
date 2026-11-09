local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local s=Scene.new('camera-zoom-anchor-1')
local camera=s.objects[2]
camera.style.longitude=-46.63;camera.style.latitude=-23.55;camera.style.zoom=1
local native={data={},inputs={},mods={}}
function native:GetData(k)return self.data[k]end
function native:SetData(k,v)self.data[k]=v end
function native:AddModifier(k,v)self.mods[k]=v;return true end
function native:SetInput(k,v,t)
 self.inputs[k]=self.inputs[k]or{};self.inputs[k][t or 'static']=v;return true
end
local comp={}
function comp:StartUndo(n)self.started=n end
function comp:EndUndo(ok)self.ended=ok end
local host={comp=comp}
function host:tool_for(o)return o.id==camera.id and native or nil end
local plan=Motion.prepare(camera,'MO-CAM-02',{start=10,frameCount=200,targetZoom=6},{})
assert(Writer.apply(host,camera,plan))
local x=(camera.style.longitude+180)/360
local y=(camera.style.latitude+90)/180
for _,k in ipairs(plan.channels.zoom)do
 local center=native.inputs.Center[k.frame]
 local zoom=native.inputs.Size[k.frame]
 assert(math.abs(center[1]+(x-0.5)*zoom-0.5)<1e-8,'longitude drift')
 assert(math.abs(center[2]+(y-0.5)*zoom-0.5)<1e-8,'latitude drift')
end
-- Existing animated Center must not receive overwrites from a Zoom-only preset.
local before=native.inputs.Center[40]
native:SetData('CartoRig.V2.Animated.Center',true)
local original=native.inputs.Size[10]
assert(not pcall(function()Writer.apply(host,camera,plan)end))
assert(native.inputs.Size[10]==original)
assert(native.inputs.Center[40]==before)
print('PASS Camera Zoom To: native Size/Center coupled to fixed WGS84 focus; conflict blocks prior animated Center')
