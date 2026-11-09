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
local function merge(o)return comp:FindTool(o.compositeToolRef)end
local original_tool=comp:FindTool(mark.hostToolRef)
local original_merge=merge(mark)
local rmerge=merge(r)
local lblmerge=merge(lbl)
assert(camera.links.Input==lblmerge and lblmerge.links.Background==original_merge)
-- An authorial Fuse may be used by an unrelated Fusion node. Refuse
-- deletion instead of breaking that foreign dependency invisibly.
local userEffect=comp:AddTool('BrightnessContrast')
userEffect:ConnectInput('Input',original_tool)
assert(not pcall(function()author:delete(mark.id)end))
assert(not original_tool.deleted and userEffect.links.Input==original_tool)
assert(m.Scene.get(author:current(),mark.id))
userEffect:ConnectInput('Input',nil)
-- Deleting a middle object bypasses exactly that Merge and removes only tools
-- tagged with the deleted authorial object ID.
local after=author:delete(mark.id)
assert(not m.Scene.get(after,mark.id))
assert(lblmerge.links.Background==rmerge)
assert(camera.links.Input==lblmerge)
assert(original_tool.deleted and original_merge.deleted)
assert(not external.deleted and not output.deleted)
assert(output.links.Input.links.Background==external)
assert(comp:FindTool(lbl.hostToolRef))
-- Delete the final top layer: Camera.Input must now point directly to Region.
after=author:delete(lbl.id)
assert(camera.links.Input==rmerge)
assert(not m.Scene.get(author:current(),lbl.id))
-- Saving a pending deletion fails: original graph must be put back, no nodes deleted.
local _,mark2=author:add_location(city,'Marker')
local mark2merge=merge(mark2)
local mark2tool=comp:FindTool(mark2.hostToolRef)
assert(mark2merge.links.Background==rmerge and camera.links.Input==mark2merge)
comp.fail_store=true
assert(not pcall(function()author:delete(mark2.id)end))
comp.fail_store=false
assert(camera.links.Input==mark2merge and mark2merge.links.Background==rmerge)
assert(mark2tool.deleted~=true and mark2merge.deleted~=true)
assert(m.Scene.get(author:current(),mark2.id))
-- External user rewires the image chain: deletion refuses to touch anything.
mark2merge:ConnectInput('Background',external)
assert(not pcall(function()author:delete(mark2.id)end))
assert(mark2tool.deleted~=true and mark2merge.links.Background==external)
mark2merge:ConnectInput('Background',rmerge)
-- A Fusion connection fails during stage: rollback is complete.
comp.refuse=camera
assert(not pcall(function()author:delete(mark2.id)end))
assert(camera.links.Input==mark2merge and mark2merge.links.Background==rmerge)
assert(m.Scene.get(author:current(),mark2.id))
-- Deletion of a locked object is refused before any native edits.
author:set_lock(mark2.id,true)
assert(not pcall(function()author:delete(mark2.id)end))
assert(comp:FindTool(mark2.hostToolRef)==mark2tool)
author:set_lock(mark2.id,false)
-- Finally delete all authorial objects: the Base Map must feed the camera.
author:delete(mark2.id)
author:delete(r.id)
assert(camera.links.Input==base)
assert(not external.deleted and not output.deleted)
assert(#author:current().objects==2)
print('PASS native deletion: middle/last links, metadata rollback, user-graph guard, connection failure, locks and foreign nodes')
