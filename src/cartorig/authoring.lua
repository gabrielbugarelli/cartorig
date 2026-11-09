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
-- Organizational groups are persistent Scene entities, not image passes.
-- Their creation/removal must not change the Fusion render graph or timeline.
function A:create_group(name,ids)
  local previous,draft=mutation_draft(self)
  if not self.m.SceneOps or type(self.m.SceneOps.create_group)~='function' then
    fail('Scene grouping module is unavailable')
  end
  local group=self.m.SceneOps.create_group(draft,self.m.Scene,name,ids)
  self.m.Scene.validate(draft)
  self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  return draft,group
end
function A:ungroup(id)
  local previous,draft=mutation_draft(self)
  if not self.m.SceneOps or type(self.m.SceneOps.ungroup)~='function' then
    fail('Scene grouping module is unavailable')
  end
  self.m.SceneOps.ungroup(draft,id)
  self.m.Scene.validate(draft)
  self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  return draft
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
local function effective_visibility(scene,object)
  if object.visible==false then return false end
  local parent=object.groupId
  local seen={[object.id]=true}
  while parent do
    if seen[parent] then fail('cyclic visibility hierarchy') end
    seen[parent]=true
    local group=nil
    for _,candidate in ipairs(scene.objects) do
      if candidate.id==parent then group=candidate;break end
    end
    if not group or group.kind~='Group' then fail('invalid visibility parent group') end
    if group.visible==false then return false end
    parent=group.groupId
  end
  return true
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
  self.m.Scene.validate(draft)
  -- Group visibility is inherited but never overwrites a child's own flag.
  -- Stage every affected Merge and roll back in reverse order if the host
  -- rejects an input or saving scene JSON fails.
  local changed={}
  for _,old in ipairs(previous.objects) do
    if old.kind=='Region' or old.kind=='Route' or old.kind=='Marker' or old.kind=='Label' then
      local nextObject=self.m.Scene.get(draft,old.id)
      local before=effective_visibility(previous,old)
      local after=effective_visibility(draft,nextObject)
      if before~=after then
        changed[#changed+1]={object=old,before=before,after=after}
      end
    end
  end
  local applied={}
  local ok,err=xpcall(function()
    for _,entry in ipairs(changed) do
      self.host:set_authorial_visibility(previous,entry.object,entry.after)
      applied[#applied+1]=entry
    end
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end,debug.traceback)
  if not ok then
    local recovery={}
    for i=#applied,1,-1 do
      local entry=applied[i]
      local restored,reason=pcall(function()
        self.host:set_authorial_visibility(previous,entry.object,entry.before)
      end)
      if not restored then recovery[#recovery+1]=tostring(reason) end
    end
    if #recovery>0 then
      fail('visibility update failed AND native rollback failed; recover a project copy: '..table.concat(recovery,'; '))
    end
    fail('visibility not saved; native Fusion layers restored: '..tostring(err))
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
-- A camera pose is one logical edit. No keyframe is inserted by Focus/Fit.
-- Every native input is restored if any later channel or metadata write fails.
function A:set_camera_pose(values)
  if type(values)~='table' then fail('camera pose must contain explicit fields') end
  local previous,draft=mutation_draft(self)
  local camera=previous.objects[2]
  if not camera or camera.kind~='Camera' then fail('structural camera missing') end
  local fields={'longitude','latitude','zoom','bearing'}
  local changes={};local count=0
  for _,key in ipairs(fields) do
    local value=values[key]
    if value~=nil then
      self.m.Scene.set_style(draft,camera.id,key,value)
      if camera.style[key]~=value then changes[#changes+1]={key=key,value=value};count=count+1 end
    end
  end
  for key in pairs(values) do
    if key~='longitude' and key~='latitude' and key~='zoom' and key~='bearing' then
      fail('unsupported camera field '..tostring(key))
    end
  end
  if count==0 then return previous end
  self.m.Scene.validate(draft)
  local rollbacks={}
  local function rollback()
    local errors={}
    for i=#rollbacks,1,-1 do
      local ok,err=pcall(rollbacks[i])
      if not ok then errors[#errors+1]=tostring(err) end
    end
    if #errors>0 then fail('native camera rollback failed; recover a saved project copy: '..table.concat(errors,'; ')) end
  end
  local ok,err=xpcall(function()
    for _,change in ipairs(changes) do
      rollbacks[#rollbacks+1]=self.host:prepare_style(previous,camera,change.key,change.value)
    end
    self.m.Repository.write(self.comp,draft,self.m.Scene,self.m.Json)
  end,debug.traceback)
  if not ok then
    local restored,why=pcall(rollback)
    if not restored then fail('camera edit failed AND rollback failed: '..tostring(why)) end
    fail('camera edit not applied; native inputs restored: '..tostring(err))
  end
  return draft
end
function A:focus_camera(point)
  if not self.m.Geo.valid_point(point) then fail('Focus requires a real geographic point') end
  if point.lat>85 or point.lat< -85 then fail('Focus latitude exceeds supported equirectangular camera range') end
  return self:set_camera_pose({longitude=point.lon,latitude=point.lat})
end
local function fit_points(feature)
  if type(feature)~='table' then fail('Fit requires a geographic location') end
  if feature.geometryType=='Point' then
    if not feature.point then fail('point location has no WGS84 anchor') end
    return {feature.point}
  end
  local geometry=feature.geometry
  if type(geometry)~='table' then fail('Fit requires available polygon geometry') end
  local coordinates=geometry.coordinates
  if type(coordinates)~='table' then fail('Fit polygon has no vertices') end
  local polys
  if geometry.type=='Polygon' then polys={coordinates}
  elseif geometry.type=='MultiPolygon' then polys=coordinates
  else fail('Fit requires a Point, Polygon or MultiPolygon') end
  local points={}
  for _,poly in ipairs(polys) do
    for _,ring in ipairs(poly) do
      for _,v in ipairs(ring) do
        if type(v)~='table' then fail('invalid fit vertex') end
        points[#points+1]={lon=v[1],lat=v[2]}
        if #points>1000000 then fail('Fit geometry exceeds safe vertex budget') end
      end
    end
  end
  if #points==0 then fail('Fit polygon has no vertices') end
  return points
end
function A:fit_location(feature,width,height)
  local current=self:current()
  if not current then fail('initialize map scene first') end
  local pad=current.objects[2].style.fitPadding or 8
  local pose=self.m.Geo.fit(fit_points(feature),width,height,pad)
  if pose.latitude>85 or pose.latitude< -85 then fail('Fit requires an unsupported camera latitude') end
  -- Fit does not reset bearing; the user may have explicitly rotated the map.
  return self:set_camera_pose({longitude=pose.longitude,latitude=pose.latitude,zoom=pose.zoom})
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
  if object.kind=='Group' then return nil end -- organization-only, not a renderer node
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
