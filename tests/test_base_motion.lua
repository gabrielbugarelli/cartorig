local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local Host=dofile(root..'/src/cartorig/fusion_host.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local tools={};local mt={};mt.__index=mt
function mt:SetAttrs(a)self.Name=a.TOOLS_Name end
function mt:GetAttrs()return {TOOLS_RegID=self.ID,TOOLS_Name=self.Name}end
function mt:GetData(k)return self.data[k]end
function mt:SetData(k,v)self.data[k]=v end
function mt:SetInput(k,v,t)self.inputs[k]=self.inputs[k]or {};self.inputs[k][t or 'static']=v;return true end
function mt:ConnectInput(k,src)self.links[k]=src;return true end
function mt:AddModifier(k,kind)self.mods[k]=kind;return true end
function mt:Delete()self.deleted=true end
local comp={}
function comp:AddTool(id)
 local n=setmetatable({ID=id,Name=id..#tools,data={},inputs={},links={},mods={}},mt)
 tools[#tools+1]=n;return n
end
function comp:FindTool(name)for _,n in ipairs(tools)do if n.Name==name and not n.deleted then return n end end end
function comp:GetToolList()return tools end
comp:AddTool('MediaOut')
local s=Scene.new('basemap-0002','naturalearth-10m')
local host=Host.new(comp,{})
assert(host:init_base(s))
local base=s.objects[1];local tool=host:tool_for(base)
assert(tool and tool.ID=='CartoRigBase')
assert(tool.links.Input.ID=='Background')
local plan=Motion.prepare(base,'MO-MAP-01',{start=50,frameCount=100,layer='Ocean'}, {})
assert(Writer.apply(host,base,plan))
assert(tool.inputs.OceanLayerOpacity[50]==0)
assert(tool.inputs.OceanLayerOpacity[68]==1)
-- Unsupported layer must fail BEFORE a single modifier or key is written.
local land=Motion.prepare(base,'MO-MAP-01',{start=50,frameCount=100,layer='Land'}, {})
local n=0;for _ in pairs(tool.mods) do n=n+1 end
assert(not pcall(function()Writer.apply(host,base,land)end))
local m=0;for _ in pairs(tool.mods) do m=m+1 end
assert(m==n)
print('PASS Base Map authoring: own tool, native Ocean Layer Fade and fail-closed unsupported land layer')
