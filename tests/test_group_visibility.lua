local root=assert(arg[1]);local function load(n)return dofile(root..'/src/cartorig/'..n..'.lua')end
local Scene=load('scene');local A=load('authoring');local Repository=load('repository');local Json=load('json')
local modules={Scene=Scene,Repository=Repository,Json=Json,Host=load('fusion_host'),Objects=load('fusion_objects'),Geo=load('geo'),Motion=load('motion'),Writer=load('motion_apply')}
local comp={nodes={},data={},failSave=false}
local T={};T.__index=T
function T:SetAttrs(a)self.Name=a.TOOLS_Name end
function T:GetAttrs()return {TOOLS_RegID=self.ID,TOOLS_Name=self.Name} end
function T:SetData(k,v)self.data[k]=v end
function T:GetData(k)return self.data[k] end
function T:SetInput(k,v,f)if self.failBlend and k=='Blend' then return false end;self.inputs[k]=self.inputs[k]or{};self.inputs[k][f or 'static']=v;return true end
function T:ConnectInput(k,v)self.links[k]=v;return true end
function T:Delete()self.deleted=true end
function comp:AddTool(kind)
 local n=setmetatable({ID=kind,Name=kind..#self.nodes,data={},inputs={},links={}},T)
 self.nodes[#self.nodes+1]=n;return n
end
function comp:GetToolList()return self.nodes end
function comp:FindTool(name)for _,n in ipairs(self.nodes)do if n.Name==name and not n.deleted then return n end end end
function comp:SetData(k,v)if self.failSave then return false end;self.data[k]=v;return true end
function comp:GetData(k)return self.data[k]end
function comp:StartUndo()end;function comp:EndUndo()end
comp:AddTool('MediaOut')
local engine=A.new(comp,modules,{readstring=function(s)return s end})
engine:initialize('group-visibility-001','test-ne')
local function add(name,lon)
  local _,o=engine:add_location({id='city:'..name,kind='City',name=name,point={lon=lon,lat=-20},geometryType='Point',source={dataset='NE'}},'Marker')
  return o
end
local first=add('First',-45);local second=add('Second',-40)
local third=add('Third',-35)
engine:set_visible(second.id,false)
local scene=engine:current()
local outer=Scene.add_group(scene,'Outer')
local inner=Scene.add_group(scene,'Inner')
inner.groupId=outer.id
Scene.get(scene,first.id).groupId=inner.id
Scene.get(scene,second.id).groupId=inner.id
Scene.validate(scene)
Repository.write(comp,scene,Scene,Json)
local function blend(o)local v=comp:FindTool(o.compositeToolRef).inputs.Blend;return v and v.static or nil end
local s=engine:set_visible(outer.id,false)
assert(blend(first)==0 and blend(third)==nil,'only group descendant should change')
assert(Scene.get(s,second.id).visible==false,'child flag is not overwritten')
assert(engine:set_visible(outer.id,true))
assert(blend(first)==1 and blend(second)==0,'hidden child must remain hidden')
assert(Scene.get(engine:current(),second.id).visible==false)
-- Persisted nested group hide must propagate through multiple ancestors.
assert(engine:set_visible(inner.id,false))
assert(blend(first)==0)
-- Saving fails after the native connection changes: restore exact prior Blend.
comp.failSave=true
assert(not pcall(function()engine:set_visible(inner.id,true)end))
assert(blend(first)==0 and Scene.get(engine:current(),inner.id).visible==false)
comp.failSave=false
assert(engine:set_visible(inner.id,true));assert(blend(first)==1)
-- Native tool failure during a multi-object update reverts earlier layers.
assert(engine:set_visible(outer.id,false));assert(blend(first)==0)
-- Change second's own flag while group is invisible: no native write is needed.
assert(engine:set_visible(second.id,true))
local secondBlend=comp:FindTool(second.compositeToolRef)
secondBlend.failBlend=true
assert(not pcall(function()engine:set_visible(outer.id,true)end))
assert(blend(first)==0 and Scene.get(engine:current(),outer.id).visible==false)
secondBlend.failBlend=false
assert(engine:set_visible(outer.id,true));assert(blend(first)==1 and blend(second)==1)
assert(Scene.validate(engine:current()))
print('PASS Group visibility: inherited, nested, preserves child state, transactional host rollback')
