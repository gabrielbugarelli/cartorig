-- CartoRig Fusion host adapter. No UI-specific state, no hidden global Polyline constructor.
-- This code must be host-tested in Resolve Studio 20 before marking a product requirement DONE.
local H={};H.__index=H
local function fail(message)error('CartoRig Fusion host: '..message,2)end
local function attr(tool)
  local ok,a=pcall(function()return tool:GetAttrs()end)
  return ok and a or {}
end
local function find(comp,name)
  if type(comp.FindTool)~='function' then fail('FindTool unavailable') end
  return comp:FindTool(name)
end
local function add(comp,id,name,x,y)
  local result=comp:AddTool(id,false,x or -32768,y or -32768)
  if not result then fail('Resolve did not create Fusion node: '..id) end
  result:SetAttrs({TOOLS_Name=name})
  result:SetData('CartoRig.V2.Owned',true)
  return result
end
local function connect(dst,input,src)
  if not dst or not src then fail('cannot connect a missing node') end
  local ok,result=pcall(function()return dst:ConnectInput(input,src)end)
  if not ok or result==false then fail('Fusion connection failed: '..tostring(input)..': '..tostring(result)) end
end
local function hex(color)
  if type(color)~='string' or not color:match('^#%x%x%x%x%x%x$') then fail('expected #RRGGBB') end
  return tonumber(color:sub(2,3),16)/255,tonumber(color:sub(4,5),16)/255,tonumber(color:sub(6,7),16)/255
end
function H.new(comp,bridge)
  if not comp or type(comp.AddTool)~='function' then fail('no active Fusion Composition') end
  return setmetatable({comp=comp,bridge=bridge or rawget(_G,'bmd')},H)
end
function H:media_out()
  for _,node in pairs(self.comp:GetToolList(false) or {}) do
    local a=attr(node)
    if a.TOOLS_RegID=='MediaOut' or node.ID=='MediaOut' then return node end
  end
  return nil
end
function H:tag(node,scene_id,object_id,kind)
  node:SetData('CartoRig.V2.SceneId',scene_id)
  node:SetData('CartoRig.V2.ObjectId',object_id)
  node:SetData('CartoRig.V2.Kind',kind)
  return node
end
function H:tool_for(object)
  if not object or not object.hostToolRef then return nil end
  local tool=find(self.comp,object.hostToolRef)
  if not tool then return nil end
  if tool:GetData('CartoRig.V2.ObjectId')~=object.id then return nil end
  return tool
end
function H:select(object)
  local tool=self:tool_for(object)
  if not tool then fail('selected object is not linked to its Fusion tool') end
  local flow=self.comp.CurrentFrame and self.comp.CurrentFrame.FlowView
  if not flow or type(flow.Select)~='function' then fail('Fusion Node Editor FlowView unavailable') end
  flow:Select()
  flow:Select(tool,true)
  if type(self.comp.SetActiveTool)=='function' then self.comp:SetActiveTool(tool) end
  return tool
end
function H:init_base(scene)
  if scene.hostInitialized then return false end
  local out=self:media_out()
  if not out then fail('Fusion Composition needs a MediaOut node') end
  local existing=self.comp:GetToolList(false) or {}
  for _,tool in pairs(existing) do
    if tool~=out and tool:GetData('CartoRig.V2.Owned')~=true then
      fail('composition already has non-CartoRig nodes: initialize with an empty Fusion Composition; no existing node was modified')
    end
  end
  local created={}
  local function new(id,name,x,y)
    local node=add(self.comp,id,name,x,y);created[#created+1]=node;return node
  end
  local begun=false
  if self.comp.StartUndo then self.comp:StartUndo('CartoRig: initialize scene');begun=true end
  local ok,err=xpcall(function()
    local white=new('Background','CR2_BASE_SOURCE_'..scene.id,-5,0)
    white:SetInput('TopLeftRed',1);white:SetInput('TopLeftGreen',1)
    white:SetInput('TopLeftBlue',1);white:SetInput('TopLeftAlpha',1)
    self:tag(white,scene.id,scene.objects[1].id,'InternalBaseSurface')
    local base=new('CartoRigBase','CR2_BASE_'..scene.id,-4,0)
    connect(base,'Input',white)
    local camera=new('Transform','CR2_CAMERA_'..scene.id,0,0)
    connect(camera,'Input',base)
    connect(out,'Input',camera)
    for _,object in ipairs(scene.objects) do
      if object.kind=='BaseMap' then self:tag(base,scene.id,object.id,object.kind);object.hostToolRef=attr(base).TOOLS_Name or base.Name
      elseif object.kind=='Camera' then self:tag(camera,scene.id,object.id,object.kind);object.hostToolRef=attr(camera).TOOLS_Name or camera.Name end
    end
    scene.hostInitialized=true
    -- Last layer is BaseMap, not camera. It is the input to camera.
    scene.lastLayerRef=attr(base).TOOLS_Name or base.Name
  end,debug.traceback)
  if not ok then
    for i=#created,1,-1 do pcall(function()created[i]:Delete()end) end
  end
  if begun and self.comp.EndUndo then self.comp:EndUndo(ok) end
  if not ok then fail('initialization rolled back: '..tostring(err)) end
  return true
end
-- Used only when persistence fails immediately after a new, empty-scene initialization.
-- All nodes removed MUST carry this exact CartoRig scene identity.
function H:rollback_base(scene)
  if not scene or not scene.id then fail('scene identity required for rollback') end
  if not scene.hostInitialized then return false end
  for _,tool in pairs(self.comp:GetToolList(false) or {}) do
    if tool:GetData('CartoRig.V2.Owned')==true
       and tool:GetData('CartoRig.V2.SceneId')==scene.id then
      pcall(function() tool:Delete() end)
    end
  end
  scene.hostInitialized=false
  scene.lastLayerRef=nil
  for _,o in ipairs(scene.objects or {}) do o.hostToolRef=nil end
  return true
end
local function geometry_rings(feature)
  if not feature or type(feature.geometry)~='table' then fail('missing geographic polygon') end
  local geom=feature.geometry
  if geom.type=='Polygon' then return {geom.coordinates} end
  if geom.type=='MultiPolygon' then return geom.coordinates end
  fail('location has no polygon geometry')
end
local function mask_settings(ring,closed)
  -- Fusion's native .setting syntax; does not require `_G.Polyline` constructor.
  if type(ring)~='table' or #ring<(closed==false and 2 or 3) or #ring>10000 then fail('invalid polyline vertex count') end
  local fragments={}
  for i,pt in ipairs(ring) do
    if type(pt)~='table' or type(pt[1])~='number' or type(pt[2])~='number' or pt[1]~=pt[1] or pt[2]~=pt[2] then fail('invalid polygon coordinate') end
    if pt[1] < -180 or pt[1] >180 or pt[2]<-90 or pt[2]>90 then fail('polygon coordinate out of WGS84 range') end
    fragments[#fragments+1]=string.format('[%d] = { Linear = true, X = %.9f, Y = %.9f }',i,pt[1]/360,pt[2]/180)
  end
  return 'Polyline { Closed = '..tostring(closed~=false)..', Points = { '..table.concat(fragments,', ')..' } }'
end
function H:_make_polyline_mask(ring,name,closed)
  local bmd=self.bridge
  if not bmd or type(bmd.readstring)~='function' then fail('bmd.readstring is required for native polygon mask serialization') end
  local src=mask_settings(ring,closed)
  local ok,poly=pcall(function()return bmd.readstring(src)end)
  if not ok or not poly then fail('Fusion could not deserialize Polygon geometry: '..tostring(poly)) end
  local mask=add(self.comp,'PolylineMask',name,-2,4)
  local set_ok,result=pcall(function()return mask:SetInput('Polyline',poly)end)
  if not set_ok or result==false then
    pcall(function()mask:Delete()end)
    fail('Fusion rejected native Polygon geometry input; see host diagnostics')
  end
  return mask
end
function H:_make_polygon_mask(ring,name)
  return self:_make_polyline_mask(ring,name,true)
end
function H:add_region(scene,object,feature)
  if object.kind~='Region' then fail('object must be a Region') end
  local polygons=geometry_rings(feature)
  local needed=0
  for _,polygon in ipairs(polygons) do
    if #polygon~=1 then fail('region contains internal rings; topology-safe rasterizer required (no incorrect fill fallback)') end
    for i=2,#polygon[1] do
      if math.abs(polygon[1][i][1]-polygon[1][i-1][1])>180 then
        fail('region boundary crosses antimeridian; safe seam-splitting required before render')
      end
    end
    needed=needed+1
  end
  if needed>200 then fail('polygon too fragmented for native mask preview') end
  local camera=find(self.comp,'CR2_CAMERA_'..scene.id)
  local previous=find(self.comp,scene.lastLayerRef or '')
  if not previous or not camera then fail('CartoRig scene is not initialized') end
  local created={}
  local function new(id,name,x,y)
    local node=add(self.comp,id,name,x,y);created[#created+1]=node;return node
  end
  local begun=false
  if self.comp.StartUndo then self.comp:StartUndo('CartoRig: add Region');begun=true end
  local ok,err=xpcall(function()
    -- Compose all island fragments into a SINGLE white premultiplied matte.
    -- That matte is then shaded by one CartoRigRegion Fuse, which is the
    -- authorial Inspector tool; no fragment carries separate style keys.
    local blank=new('Background','CR2_REGION_EMPTY_'..object.id,-3,3)
    blank:SetInput('TopLeftRed',0)
    blank:SetInput('TopLeftGreen',0)
    blank:SetInput('TopLeftBlue',0)
    blank:SetInput('TopLeftAlpha',0)
    self:tag(blank,scene.id,object.id,'InternalRegionCanvas')
    local matte=blank
    for i,polygon in ipairs(polygons) do
      local mask=self:_make_polygon_mask(polygon[1],'CR2_MASK_'..object.id..'_'..i)
      created[#created+1]=mask
      self:tag(mask,scene.id,object.id,'InternalMask')
      local white=new('Background','CR2_WHITE_'..object.id..'_'..i,-1,i)
      white:SetInput('TopLeftRed',1);white:SetInput('TopLeftGreen',1)
      white:SetInput('TopLeftBlue',1);white:SetInput('TopLeftAlpha',1)
      self:tag(white,scene.id,object.id,'InternalRegionFill')
      connect(white,'EffectMask',mask)
      local piece=new('Merge','CR2_PIECE_'..object.id..'_'..i,1,i)
      self:tag(piece,scene.id,object.id,'InternalRegionComposite')
      connect(piece,'Background',matte)
      connect(piece,'Foreground',white)
      matte=piece
    end
    local region=new('CartoRigRegion','CR2_REGION_'..object.id,3,4)
    self:tag(region,scene.id,object.id,'Region')
    connect(region,'Input',matte)
    local r,g,b=hex(object.style.fill or '#8296A4')
    region:SetInput('FillRed',r);region:SetInput('FillGreen',g);region:SetInput('FillBlue',b)
    region:SetInput('ObjectOpacity',(object.style.opacity or 100)/100)
    region:SetInput('HighlightStrength',0)
    local merge=new('Merge','CR2_COMPOSITE_'..object.id,5,4)
    self:tag(merge,scene.id,object.id,'InternalComposite')
    connect(merge,'Background',previous)
    connect(merge,'Foreground',region)
    connect(camera,'Input',merge)
    object.hostToolRef=attr(region).TOOLS_Name or region.Name
    object.compositeToolRef=attr(merge).TOOLS_Name or merge.Name
    scene.lastLayerRef=object.compositeToolRef
  end,debug.traceback)
  if not ok then
    pcall(function()connect(camera,'Input',previous)end)
    for i=#created,1,-1 do pcall(function()created[i]:Delete()end) end
  end
  if begun and self.comp.EndUndo then self.comp:EndUndo(ok) end
  if not ok then fail('Region creation rolled back: '..tostring(err)) end
  return true
end
function H:set_authorial_visibility(scene,object,visible)
  if type(visible)~='boolean' then fail('visibility must be boolean') end
  if not scene or not object or object.kind=='BaseMap' or object.kind=='Camera' then
    fail('visibility adapter supports authored visual objects only')
  end
  if not self:tool_for(object) then fail('authorial Fusion object no longer exists') end
  local ref=object.compositeToolRef
  local blend=ref and find(self.comp,ref)
  if not blend or blend:GetData('CartoRig.V2.Owned')~=true
    or blend:GetData('CartoRig.V2.SceneId')~=scene.id
    or blend:GetData('CartoRig.V2.ObjectId')~=object.id
  then fail('authorial compositing node is missing or not owned by this object') end
  local ok,result=pcall(function()return blend:SetInput('Blend',visible and 1 or 0)end)
  if not ok or result==false then fail('Fusion refused authorial visibility change') end
  return true
end
function H:set_region_fill(object,color,frame,animate)
  local node=self:tool_for(object)
  if not node or object.kind~='Region' then fail('Region has no Fusion color tool') end
  local r,g,b=hex(color)
  local channels={FillRed=r,FillGreen=g,FillBlue=b}
  for channel,value in pairs(channels) do
    if animate then
      if type(node.AddModifier)~='function' then fail('Fusion AddModifier unavailable') end
      if not node:GetData('CartoRig.V2.Animated.'..channel) then
        local ok,result=pcall(function()return node:AddModifier(channel,'BezierSpline')end)
        if not ok or result==false then fail('could not create native spline for '..channel) end
        node:SetData('CartoRig.V2.Animated.'..channel,true)
      end
      node:SetInput(channel,value,frame)
    else
      if node:GetData('CartoRig.V2.Animated.'..channel) then fail('this color has keyframes; edit at playhead') end
      node:SetInput(channel,value)
    end
  end
end
function H:apply_color_plan(object,plan)
  if not plan.channels.fill then fail('Motion plan does not affect Fill') end
  for _,keyframe in ipairs(plan.channels.fill) do
    self:set_region_fill(object,keyframe.value,keyframe.frame,true)
  end
end

return H
