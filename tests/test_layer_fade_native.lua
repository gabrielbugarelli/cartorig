local root=assert(arg[1])
local Scene=dofile(root..'/src/cartorig/scene.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local s=Scene.new('layer-fade-native-1');local base=s.objects[1]
local fields={}
local tool={data={},keys={}}
function tool:GetData(k)return self.data[k]end
function tool:SetData(k,v)self.data[k]=v end
function tool:AddModifier(input,method)self.keys[input]=self.keys[input] or {};return true end
function tool:SetInput(input,value,frame)
 self.keys[input]=self.keys[input]or{};self.keys[input][frame]=value;return true
end
function tool:GetInputList()return fields end
local comp={StartUndo=function()end,EndUndo=function()end}
local host={comp=comp,tool_for=function()return tool end}
local plan=Motion.prepare(base,'MO-MAP-01',{frameCount=100,start=20,layer='Land'}, {})
local ok,msg=pcall(function()Writer.apply(host,base,plan)end)
assert(not ok and tostring(msg):find('Layer Fade',1,true))
assert(next(tool.keys)==nil,'no spline before source validation')
fields.LandInput={GetConnectedOutput=function()return {}end}
fields.LandLayerOpacity={GetKeyFrames=function()return {}end,GetConnectedOutput=function()return nil end}
assert(Writer.apply(host,base,plan))
assert(tool.keys.LandLayerOpacity[20]==0 and tool.keys.LandLayerOpacity[38]==1)
assert(not tool.keys.OceanLayerOpacity,'Land fade cannot affect Ocean')
local state=Motion.prepare(base,'MO-MAP-01',{frameCount=100,start=20,layer='StateBorders'}, {})
assert(not pcall(function()Writer.apply(host,base,state)end),'missing StateBorders mask must block animation')
print('PASS Base Map layer fades: actual native channel, connected-matte gate, independent layers')
