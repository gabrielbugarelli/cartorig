-- End-to-end mocked Fusion host verification for managed Z-order operations.
-- Tests actual socket links, not only the Scene JSON ordering.
local root=assert(arg[1])
local function load(n)return dofile(root..'/src/cartorig/'..n..'.lua')end
local m={Scene=load('scene'),Repository=load('repository'),Json=load('json'),
 Host=load('fusion_host'),Objects=load('fusion_objects'),Geo=load('geo'),
 Motion=load('motion'),Writer=load('motion_apply'),GraphOps=load('graph_ops'),SceneOps=load('scene_ops')}
local Author=load('authoring')
local comp={nodes={},data={},refuse=nil,fail_store=false}
local T={};T.__index=T
function T:SetAttrs(a)self.Name=a.TOOLS_Name end
function T:GetAttrs()return {TOOLS_Name=self.Name,TOOLS_RegID=self.ID}end
function T:SetData(k,v)self.data[k]=v end
function T:GetData(k)return self.data[k]end
function T:SetInput(k,v,t)self.inputs[k]=self.inputs[k] or {};self.inputs[k][t or 'static']=v;return true end
function T:GetInput(k,t)return self.inputs[k] and self.inputs[k][t or 'static']end
function T:ConnectInput(k,source)
 if comp.refuse==self and source then comp.refuse=nil;return false end
 self.links[k]=source;return true
end
function T:GetInputList()
 local r={}
 for _,key in ipairs({'Input','Background','Foreground'}) do
  r[key]={GetConnectedOutput=function()
   local node=self.links[key]
   return node and {GetTool=function()return node end} or nil
  end}
 end
 return r
end
function T:Delete()self.deleted=true end
function T:AddModifier(k,method)self.modifiers[k]=method;return true end
function comp:AddTool(kind)
 local n=setmetatable({ID=kind,Name=kind..tostring(#self.nodes+1),data={},links={},inputs={},modifiers={}},T)
 self.nodes[#self.nodes+1]=n;return n
end
function comp:GetToolList()
 local list={};for _,node in ipairs(self.nodes) do if not node.deleted then list[#list+1]=node end end
 return list
end
function comp:FindTool(name)
 for _,node in ipairs(self.nodes) do if not node.deleted and node.Name==name then return node end end
end
function comp:GetData(key)return self.data[key]end
function comp:SetData(key,value)
 if self.fail_store then error('storage refused') end
 self.data[key]=value;return true
end
function comp:StartUndo()end
function comp:EndUndo()end
function comp:SetActiveTool(tool)self.active=tool end
comp.CurrentFrame={FlowView={Select=function(_,node)comp.selected=node end}}
local external=comp:AddTool('MediaIn')
local output=comp:AddTool('MediaOut');output:ConnectInput('Input',external)
local bridge={readstring=function(src)
 if src:find('FuID',1,true) then return {source=src} end
 assert(src:find('Polyline {',1,true));return {source=src}
end}
local author=Author.new(comp,m,bridge,'fixture-bundle')
local scene=author:initialize('draw-order-scene-0001','fixture-bundle')
local polygon={id='br',name='Brazil',kind='Country',geometryType='Polygon',
 geometry={type='Polygon',coordinates={{{-60,-20},{-40,-20},{-40,0},{-60,0}}}}}
local _,r=author:add_location(polygon,'Region')
local city={id='sp',name='São Paulo',kind='City',geometryType='Point',point={lon=-47,lat=-23}}
local _,mark=author:add_location(city,'Marker')
local _,lbl=author:add_location(city,'Label')
local base=comp:FindTool(scene.objects[1].hostToolRef)
local camera=comp:FindTool(scene.objects[2].hostToolRef)
local function merge(o)return comp:FindTool(o.compositeToolRef) end
local function order(a,b,c)
 assert(merge(a).links.Background==base)
 assert(merge(b).links.Background==merge(a))
 assert(merge(c).links.Background==merge(b))
 assert(camera.links.Input==merge(c))
 assert(output.links.Input.ID=='Merge' and output.links.Input.links.Background==external)
end
order(r,mark,lbl)
-- Real rewiring changes pixels' composition order, and is persisted by identity.
local draft=author:reorder(lbl.id,3)
assert(draft.objects[3].id==lbl.id and draft.lastLayerRef==mark.compositeToolRef)
order(lbl,r,mark)
assert(author:current().objects[3].id==lbl.id)
-- A user may rename an authorial node in native Fusion; stable tags still select it.
local labelTool=comp:FindTool(lbl.hostToolRef)
labelTool:SetAttrs({TOOLS_Name='Renamed by Fusion User'})
assert(author:select(lbl.id)==labelTool and comp.selected==labelTool)
-- If a user manually rewires a managed Merge, fail BEFORE any further mutation.
merge(r):ConnectInput('Background',external)
local previous=author:current()
assert(not pcall(function()author:reorder(mark.id,3)end))
assert(author:current().objects[3].id==lbl.id)
assert(merge(r).links.Background==external)
merge(r):ConnectInput('Background',merge(lbl))
order(lbl,r,mark)
-- Host rejects a connection halfway through: GraphOps must restore the old chain.
comp.refuse=merge(mark)
assert(not pcall(function()author:reorder(mark.id,3)end))
order(lbl,r,mark)
assert(author:current().objects[3].id==lbl.id)
-- Persistence fails after rewiring: authoring must restore the original order.
comp.fail_store=true
assert(not pcall(function()author:reorder(mark.id,3)end))
comp.fail_store=false
order(lbl,r,mark)
assert(author:current().objects[3].id==lbl.id)
-- Objects do not multiply during reorders. Foreign footage remains unchanged.
assert(#comp:GetToolList()>=12 and not external.deleted)
-- A new object must attach by stable owned ID even if a user renamed the
-- Camera AND the final Merge node in the native Fusion flow.
local renamedLast=merge(mark)
renamedLast:SetAttrs({TOOLS_Name='User Renamed Final Composite'})
camera:SetAttrs({TOOLS_Name='User Renamed Camera'})
local _,newMark=author:add_location(city,'Marker')
assert(merge(newMark).links.Background==renamedLast)
assert(camera.links.Input==merge(newMark))
assert(author:select(newMark.id)==comp:FindTool(newMark.hostToolRef))
-- Post-insertion failure must restore the renamed upstream, not a stale ref.
comp.fail_store=true
local count=#comp:GetToolList()
assert(not pcall(function()author:add_location(city,'Marker')end))
comp.fail_store=false
assert(camera.links.Input==merge(newMark))
assert(#comp:GetToolList()==count)
assert(external.deleted~=true and output.links.Input.links.Background==external)
-- Editing a Route must change its existing native mask, not re-create its
-- authorial object or discard a hand-edited WriteLength animation curve.
local _,route=author:add_route({lon=-47.9,lat=-15.8},{lon=-51.1,lat=0.8})
local routeMask=comp:FindTool(route.maskToolRef)
local originalGeometry=routeMask:GetInput('Polyline')
assert(originalGeometry)
routeMask:SetInput('WriteLength',0.4,100)
local updated=author:update_route(route.id,{
 to={lon=-52.0,lat=2.0},waypoints={{lon=-50.0,lat=-7.0}},pathType='Curved',curvature=20
})
assert(updated and updated.objects[#updated.objects].id==route.id)
assert(routeMask:GetInput('Polyline')~=originalGeometry)
assert(routeMask:GetInput('WriteLength',100)==0.4)
assert(comp:FindTool(route.maskToolRef)==routeMask)
local acceptedGeometry=routeMask:GetInput('Polyline')
-- Geometry outside the supported projection is rejected before modification.
assert(not pcall(function()author:update_route(route.id,{from={lon=179,lat=0},to={lon=-179,lat=5}})end))
assert(routeMask:GetInput('Polyline')==acceptedGeometry)
-- Failed persistence is rolled back on the existing mask and Scene JSON.
comp.fail_store=true
assert(not pcall(function()author:update_route(route.id,{to={lon=-60,lat=10}})end))
comp.fail_store=false
assert(routeMask:GetInput('Polyline')==acceptedGeometry)
assert(author:current().objects[#author:current().objects].route.to.lon==-52.0)
assert(routeMask:GetInput('WriteLength',100)==0.4)
assert(not external.deleted and not output.deleted)
print('PASS native draw order: true Merge rewiring, stable IDs, renamed tool, external-graph guard, failed reconnect and persistence rollback')
