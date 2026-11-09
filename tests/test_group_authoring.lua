local root=assert(arg[1]);local function load(n)return dofile(root..'/src/cartorig/'..n..'.lua')end
local Scene=load('scene');local Ops=load('scene_ops');local A=load('authoring')
local Repository=load('repository');local Json=load('json')
local comp={data={},saveFail=false}
function comp:AddTool()return nil end
function comp:GetData(k)return self.data[k]end
function comp:SetData(k,v)if self.saveFail then return false end;self.data[k]=v;return true end
local modules={Scene=Scene,SceneOps=Ops,Repository=Repository,Json=Json,Host=load('fusion_host'),
 Objects=load('fusion_objects'),Geo=load('geo'),Motion=load('motion'),Writer=load('motion_apply')}
local draft=Scene.new('authoring-groups-0001','NE')
local marker=Scene.add_location(draft,{id='city:br',name='Brasília',type='City',point={lon=-47.9,lat=-15.8}},'Marker')
Repository.write(comp,draft,Scene,Json)
local engine=A.new(comp,modules,nil,'NE')
local first,group=engine:create_group('Locations',{marker.id})
assert(Scene.get(first,marker.id).groupId==group.id)
assert(Scene.validate(first))
assert(engine:select(group.id)==nil,'group must not try to select nonexistent Fusion node')
assert(not pcall(function()engine:create_group('Duplicate',{marker.id})end))
comp.saveFail=true
assert(not pcall(function()engine:ungroup(group.id)end),'failed write must not remove persisted group')
comp.saveFail=false
assert(Scene.get(engine:current(),marker.id).groupId==group.id)
assert(Scene.get(engine:ungroup(group.id),marker.id).groupId==nil)
assert(not Scene.get(engine:current(),group.id))
assert(Scene.validate(engine:current()))
-- Every group command must fail before persistence if an ancestor is locked.
local _,g1=engine:create_group('First',{marker.id})
local snapshot=engine:current();Scene.set_lock(snapshot,g1.id,true)
Repository.write(comp,snapshot,Scene,Json)
assert(not pcall(function()engine:ungroup(g1.id)end))
print('PASS Group authoring: create, select, ungroup, save failure and locked group protection')
