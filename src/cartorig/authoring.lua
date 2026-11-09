-- CartoRig Scene command layer: explicit transactional orchestration, no UI widgets.
-- All persistent state is read from the current Fusion Composition before mutation.
local A={};A.__index=A
local function fail(s)error('CartoRig authoring: '..s,2) end
local function gethost(comp)
  if type(comp)~='table' and type(comp)~='userdata' then fail('Fusion Composition required') end
  return comp
end
function A.new(comp,modules,bridge,expected_manifest)
  gethost(comp)
  for _,k in ipairs({'Scene','Repository','Json','Host','Objects','Geo','Motion','Writer'}) do
    if not modules[k] then fail('missing module '..k) end
  end
  return setmetatable({comp=comp,m=modules,host=modules.Host.new(comp,bridge),expectedManifestId=expected_manifest},A)
end
function A:current()
  return self.m.Repository.read(self.comp,self.m.Scene,self.m.Json)
end
function A:initialize(id,manifest)
  if self:current() then fail('scene already initialized') end
  if self.expectedManifestId and manifest~=self.expectedManifestId then fail('initialization requested with a different geographic dataset') end
  local draft=self.m.Scene.new(id,manifest)
  self.host:init_base(draft)
  local ok,err=pcall(function() self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json) end)
  if not ok then
    self.host:rollback_base(draft)
    fail('scene metadata could not be saved, created nodes removed: '..tostring(err))
  end
  return draft
end
local function feature_struct(feature)
  return {id=feature.id,name=feature.name,type=feature.kind,version=feature.source and feature.source.version,
    dataset=feature.source and feature.source.dataset,geometryType=feature.geometryType,point=feature.point}
end
local function rollback_new_owned(host,original,object_id)
  local comp=host.comp
  local camera=host:resolve_camera(original)
  local previous=host:resolve_last_layer(original)
  local ok,worked=pcall(function()return camera:ConnectInput('Input',previous)end)
  if not ok or worked==false then
    error('CartoRig authoring: could not restore original camera connection; stop editing and recover a project copy',2)
  end
  for _,tool in pairs(comp:GetToolList(false) or {}) do
    if tool:GetData('CartoRig.V2.Owned')==true
       and tool:GetData('CartoRig.V2.SceneId')==original.id
       and tool:GetData('CartoRig.V2.ObjectId')==object_id then
      pcall(function()tool:Delete()end)
    end
  end
end
function A:add_location(feature,kind)
  local original=self:current()
  if original and self.expectedManifestId and original.manifestId~=self.expectedManifestId then fail('installed geographic dataset differs from the saved scene; mutation blocked') end
  if not original then fail('initialize map scene first') end
  local draft=self.m.Scene.snapshot(original)
  local object=self.m.Scene.add_location(draft,feature_struct(feature),kind)
  local ok,err=xpcall(function()
    if kind=='Region' then self.host:add_region(draft,object,feature)
    else self.m.Objects.build(self.host,draft,object,kind) end
    self.m.Scene.validate(draft)
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end,debug.traceback)
  if not ok then
    rollback_new_owned(self.host,original,object.id)
    fail('creation not persisted, owned tools rolled back: '..tostring(err))
  end
  return draft,object
end
function A:add_route(from,to)
  local original=self:current()
  if original and self.expectedManifestId and original.manifestId~=self.expectedManifestId then fail('installed geographic dataset differs from the saved scene; mutation blocked') end
  if not original then fail('initialize map scene first') end
  local draft=self.m.Scene.snapshot(original)
  local object=self.m.Scene.add_route(draft,from,to)
  local points=self.m.Geo.route_samples(object.route,48)
  local ok,err=xpcall(function()
    self.m.Objects.build(self.host,draft,object,'Route',points)
    self.m.Scene.validate(draft)
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end,debug.traceback)
  if not ok then
    rollback_new_owned(self.host,original,object.id)
    fail('route not persisted, owned tools rolled back: '..tostring(err))
  end
  return draft,object
end
local function mutation_draft(self)
  local current=self:current()
  if not current then fail('initialize map scene first') end
  if self.expectedManifestId and current.manifestId~=self.expectedManifestId then
    fail('installed geographic dataset differs from saved scene; mutation blocked')
  end
  return current,self.m.Scene.snapshot(current)
end
function A:rename(id,new_name)
  local previous,draft=mutation_draft(self)
  self.m.Scene.rename(draft,id,new_name)
  self.m.Scene.validate(draft)
  self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  return draft
end
function A:set_lock(id,locked)
  local previous,draft=mutation_draft(self)
  self.m.Scene.set_lock(draft,id,locked)
  self.m.Scene.validate(draft)
  self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  return draft
end
function A:set_visible(id,visible)
  local previous,draft=mutation_draft(self)
  local obj=self.m.Scene.get(previous,id)
  if not obj then fail('selected object no longer exists') end
  if obj.kind=='BaseMap' or obj.kind=='Camera' then
    fail('use the native Base Map / Camera controls for structural objects')
  end
  self.m.Scene.set_visible(draft,id,visible)
  if obj.visible==visible then return previous end
  self.host:set_authorial_visibility(previous,obj,visible)
  local ok,err=pcall(function()
    self.m.Scene.validate(draft)
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end)
  if not ok then
    pcall(function()self.host:set_authorial_visibility(previous,obj,obj.visible)end)
    fail('visibility persistence failed; Fusion blend restored: '..tostring(err))
  end
  return draft
end
-- Updating endpoints/waypoints affects the existing native geographic
-- mask; it does NOT remove the mask or overwrite its Draw Progress spline.
function A:update_route(id,changes)
  local previous,draft=mutation_draft(self)
  if type(changes)~='table' then fail('Route changes must be explicit') end
  for key in pairs(changes) do
    if key=='followerId' then fail('Follower reassignment requires a separate validated operation') end
  end
  if not self.m.SceneOps or type(self.m.SceneOps.update_route)~='function' then
    fail('Route geometry editor unavailable')
  end
  local object=self.m.SceneOps.update_route(draft,id,changes)
  self.m.Scene.validate(draft)
  local pts=self.m.Geo.route_samples(object.route,48)
  local prior=self.m.Scene.get(previous,id)
  local undoGeometry=self.host:update_route_mask(previous,prior,pts)
  local ok,err=pcall(function()
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end)
  if not ok then
    local restored,why=pcall(undoGeometry)
    if not restored then fail('Route metadata write failed AND native rollback failed; stop editing: '..tostring(why)) end
    fail('Route update not persisted; prior geometry restored: '..tostring(err))
  end
  return draft
end
-- Draw order changes MUST update the actual native Fusion composite chain,
-- not merely the Scene tree. Persist only after graph rewiring succeeds.
function A:reorder(id,newIndex)
  local previous,draft=mutation_draft(self)
  self.m.Scene.reorder(draft,id,newIndex)
  self.m.Scene.validate(draft)
  local Graph=self.m.GraphOps
  if not Graph or type(Graph.reorder)~='function' then
    fail('managed Fusion graph reorder adapter unavailable')
  end
  Graph.reorder(self.host,previous,draft)
  local ok,err=pcall(function()
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end)
  if not ok then
    local restored,reason=pcall(function()Graph.reorder(self.host,draft,previous)end)
    if not restored then
      fail('reorder metadata save failed AND graph restoration failed; stop editing: '..tostring(reason))
    end
    fail('reorder metadata save failed; original graph restored: '..tostring(err))
  end
  return draft
end
-- Remove the authorial image layer without deleting foreign Fusion tools.
-- Connect/validate first, commit metadata, and only then delete owned tools.
-- Apply a supported Control property on its real Fusion tool, then persist
-- the Scene view. A failed save reverts the exact native input values.
function A:set_style(id,key,value)
  local previous,draft=mutation_draft(self)
  self.m.Scene.set_style(draft,id,key,value)
  self.m.Scene.validate(draft)
  local object=self.m.Scene.get(previous,id)
  local rollback=self.host:prepare_style(previous,object,key,value)
  local ok,err=pcall(function()
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end)
  if not ok then
    local recovered,reason=pcall(rollback)
    if not recovered then fail('Control save failed and native rollback failed: '..tostring(reason)) end
    fail('Control property not saved; restored native values: '..tostring(err))
  end
  return draft
end
function A:delete(id)
  local previous,draft=mutation_draft(self)
  local object=self.m.Scene.get(previous,id)
  if not object then fail('selected object no longer exists') end
  self.m.Scene.remove(draft,id)
  self.m.Scene.validate(draft)
  if not self.m.GraphOps or type(self.m.GraphOps.prepare_remove)~='function' then
    fail('native object deletion is unavailable')
  end
  local tx=self.m.GraphOps.prepare_remove(self.host,previous,draft,id)
  local ok,err=pcall(function()
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end)
  if not ok then
    local recovered,reason=pcall(tx.rollback)
    if not recovered then fail('metadata save failed and graph rollback failed; recover a project copy: '..tostring(reason)) end
    fail('object deletion cancelled, original graph restored: '..tostring(err))
  end
  local clean,reason=pcall(tx.finalize)
  if not clean then
    -- Metadata has already been updated. Do not falsely claim success.
    fail('object removed from scene, but native cleanup needs repair: '..tostring(reason))
  end
  return draft
end
function A:select(id)
  local state=self:current()
  if not state then fail('no scene') end
  local object=self.m.Scene.get(state,id)
  if not object then fail('selected object no longer exists') end
  return self.host:select(object)
end
function A:motion(id,preset,opts)
  local state=self:current()
  if state and self.expectedManifestId and state.manifestId~=self.expectedManifestId then fail('installed geographic dataset differs from the saved scene; mutation blocked') end
  if not state then fail('no scene') end
  local object=self.m.Scene.get(state,id)
  if not object then fail('object missing') end
  local plan=self.m.Motion.prepare(object,preset,opts,object.motion or {})
  self.m.Writer.apply(self.host,object,plan)
  -- Persist only binding *provenance*, not a second evaluatable keyframe timeline.
  -- The real time-dependent value remains the Fusion-native spline.
  local draft=self.m.Scene.snapshot(state)
  local target=self.m.Scene.get(draft,id)
  target.motion=target.motion or {}
  for channel in pairs(plan.channels) do
    target.motion[channel]={{presetId=preset,first=plan.first,last=plan.last,state='ANIMATED_PRESET'}}
  end
  local ok,err=pcall(function()self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)end)
  if not ok then
    local tool=self.host:tool_for(object)
    if tool then pcall(function()tool:SetData('CartoRig.V2.MotionNeedsRepair',true)end) end
    fail('keys were written to Fusion but binding metadata could not be saved; manual repair required: '..tostring(err))
  end
  return plan
end
return A
