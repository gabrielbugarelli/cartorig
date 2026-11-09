local root=assert(arg[1]);local function load(n)return dofile(root..'/src/cartorig/'..n..'.lua')end
local m={Scene=load('scene'),Repository=load('repository'),Json=load('json'),Host=load('fusion_host'),
 Objects=load('fusion_objects'),Geo=load('geo'),Motion=load('motion'),Writer=load('motion_apply')}
local A=load('authoring')
local comp={nodes={},data={},metadataFail=false}
local T={};T.__index=T
function T:SetAttrs(x)self.Name=x.TOOLS_Name end
function T:GetAttrs()return {TOOLS_RegID=self.ID,TOOLS_Name=self.Name}end
function T:SetData(k,v)self.data[k]=v end
function T:GetData(k)return self.data[k]end
function T:SetInput(k,v,f)self.inputs[k]=self.inputs[k]or{};self.inputs[k][f or 'static']=v;return true end
function T:ConnectInput(k,v)self.links[k]=v;return true end
function T:AddModifier(k,v)self.mods[k]=v;return true end
function T:Delete()self.deleted=true end
function comp:AddTool(kind)
 local n=setmetatable({ID=kind,Name=kind..#self.nodes,data={},inputs={},links={},mods={}},T)
 self.nodes[#self.nodes+1]=n;return n
end
function comp:GetToolList()return self.nodes end
function comp:FindTool(name)for _,n in ipairs(self.nodes)do if n.Name==name and not n.deleted then return n end end end
function comp:SetData(k,v)if self.metadataFail then return false end;self.data[k]=v;return true end
function comp:GetData(k)return self.data[k]end
function comp:StartUndo()end;function comp:EndUndo()end
comp:AddTool('MediaOut')
local engine=A.new(comp,m,{readstring=function(s)return s end})
engine:initialize('test-commands-scene','NE')
local city={id='c1',kind='City',name='São Paulo',point={lat=-23.5,lon=-46.6},geometryType='Point',source={dataset='NE'}}
local state,marker=engine:add_location(city,'Marker')
local id=marker.id
local composite=comp:FindTool(marker.compositeToolRef)
assert(composite and composite:GetData('CartoRig.V2.ObjectId')==id)
assert(engine:set_visible(id,false));assert(composite.inputs.Blend.static==0)
assert(m.Scene.get(engine:current(),id).visible==false)
-- Metadata rejection after render-state change must restore the host blend.
comp.metadataFail=true
assert(not pcall(function()engine:set_visible(id,true)end))
assert(composite.inputs.Blend.static==0)
assert(m.Scene.get(engine:current(),id).visible==false)
comp.metadataFail=false
assert(engine:set_visible(id,true));assert(composite.inputs.Blend.static==1)
assert(engine:rename(id,'São Paulo — Pin'))
assert(m.Scene.get(engine:current(),id).name=='São Paulo — Pin')
assert(engine:current().objects[3].hostToolRef==marker.hostToolRef)
assert(engine:set_lock(id,true))
assert(not pcall(function()engine:rename(id,'Forbidden')end))
assert(not pcall(function()engine:set_visible(id,false)end))
assert(engine:set_lock(id,false))
assert(engine:set_visible(id,false));assert(composite.inputs.Blend.static==0)
-- Attacker can't mutate an unrelated/foreign node by spoofing an object ref.
composite:SetData('CartoRig.V2.ObjectId','foreign')
assert(not pcall(function()engine:set_visible(id,true)end))
assert(composite.inputs.Blend.static==0)
print('PASS authorial Scene commands: Rename, Hide/Show, Lock, mock Fusion blend, rollback, ownership')
