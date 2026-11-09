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
assert(native.inputs.Zoom[10]==1 and native.inputs.Zoom[40]==6)
assert(native.inputs.CenterLongitude==nil and native.inputs.CenterLatitude==nil,
       'zoom-only must never rewrite camera location channels')
assert(native.inputs.Center==nil and native.inputs.Size==nil,
       'old Transform screen-space channels must not exist')
assert(comp.ended==true)
-- Fly To writes independent WGS84 channels; Fuse applies coherent projection at
-- every frame without inventing additional screen-space keyframes.
native.data={};native.inputs={};native.mods={} -- distinct Camera authoring session
local fly=Motion.prepare(camera,'MO-CAM-01',{start=60,frameCount=200,
  targetPose={longitude=-45,latitude=-20,zoom=3}},{})
assert(Writer.apply(host,camera,fly))
assert(math.abs(native.inputs.CenterLongitude[105]+45)<1e-8)
assert(native.inputs.CenterLatitude[105]==-20)
assert(native.inputs.Zoom[105]==3)
print('PASS Camera canonical geographic channels: Zoom independent, Fly To WGS84, no screen-space keyframes')
