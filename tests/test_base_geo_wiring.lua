local root=assert(arg[1])
local Scene=dofile(root..'/src/cartorig/scene.lua')
local Host=dofile(root..'/src/cartorig/fusion_host.lua')
local T={};T.__index=T
function T:SetAttrs(a) self.Name=a.TOOLS_Name end
function T:GetAttrs() return {TOOLS_Name=self.Name,TOOLS_RegID=self.ID} end
function T:SetData(k,v) self.data[k]=v end
function T:GetData(k) return self.data[k] end
function T:SetInput(k,v) self.values[k]=v;return true end
function T:ConnectInput(k,v) self.inputs[k]=v;return true end
function T:Delete() self.deleted=true end
local comp={nodes={}}
function comp:AddTool(kind)
 local n=setmetatable({ID=kind,Name=kind..tostring(#self.nodes),data={},values={},inputs={}},T)
 self.nodes[#self.nodes+1]=n;return n
end
function comp:GetToolList()
 local out={};for _,n in ipairs(self.nodes) do if not n.deleted then out[#out+1]=n end end;return out
end
function comp:FindTool(name)
 for _,n in ipairs(self.nodes) do if not n.deleted and n.Name==name then return n end end
end
comp:AddTool('MediaOut')
local host=Host.new(comp,{})
local scene=Scene.new('offline-matte-integration','offline-fixture')
local before=#comp:GetToolList()
host.dataRoot=root..'/tests/fixtures/layer_index'
assert(not pcall(function()host:init_base(scene)end),'missing layer indexes must fail before any node creation')
assert(#comp:GetToolList()==before)
host.dataRoot=root..'/tests/fixtures/layers_full'
assert(host:init_base(scene))
local base=host:tool_for(scene.objects[1])
assert(base and base.ID=='CartoRigBase')
for socket,id in pairs({LandInput=0,CoastlineInput=1,CountryBordersInput=2}) do
 local matte=base.inputs[socket]
 assert(matte and matte.ID=='CartoRigGeoMatte' and matte.values.Layer==id)
 assert(matte.inputs.Input and matte.inputs.Input.ID=='Background')
 assert(matte:GetData('CartoRig.V2.Kind')=='InternalGeoMatte')
end
assert(host:rollback_base(scene))
assert(#comp:GetToolList()==before)
print('PASS indexed geographic BaseMap: native matte socket wiring, missing-data preflight, rollback')
