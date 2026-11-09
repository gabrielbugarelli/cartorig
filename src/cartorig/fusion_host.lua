-- CartoRig Fusion host adapter. No UI-specific state, no hidden global Polyline constructor.
-- This code must be host-tested in Resolve Studio 20 before marking a product requirement DONE.
local H={};H.__index=H
-- Source-relative module lookup also works from Resolve's installed Script path.
local module_source=debug.getinfo(1,'S').source
local module_dir=module_source:match('^@(.+)[/\\][^/\\]+$')
if not module_dir then error('CartoRig Fusion host: cannot locate installed geographic module') end
local GeoClip=dofile(module_dir..'/geo_clip.lua')
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
-- Capture an existing MediaOut wire without reading pixel samples or mutating the graph.
-- A connected Output is the only trustworthy source of the upstream Tool.
local function upstream_mediaout(out)
  local input=nil
  local direct_ok,direct=pcall(function() return out.Input end)
  if direct_ok and direct then input=direct end
  if not input and type(out.GetInputList)=='function' then
    local ok,inputs=pcall(function() return out:GetInputList() end)
    if ok and type(inputs)=='table' then input=inputs.Input end
  end
  if not input or type(input.GetConnectedOutput)~='function' then return nil,false end
  local ok,source=pcall(function() return input:GetConnectedOutput() end)
  if not ok then return nil,false end
  if not source then return nil,true end
  if type(source.GetTool)~='function' then return nil,false end
  local worked,tool=pcall(function() return source:GetTool() end)
  if not worked or not tool then return nil,false end
  return tool,true
end
local function toolname(node)
  if not node then return nil end
  return attr(node).TOOLS_Name or node.Name
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
-- Node names are presentation, not stable identity: Resolve users may rename
-- an owned node in the Node Editor. Resolve by persisted ownership tags and
-- reject ambiguous duplicates instead of editing the wrong object.
function H:tool_for(object)
  if not object or not object.id then return nil end
  local candidate=object.hostToolRef and find(self.comp,object.hostToolRef) or nil
  local function valid(t)
    return t and t:GetData('CartoRig.V2.Owned')==true
      and t:GetData('CartoRig.V2.ObjectId')==object.id
      and t:GetData('CartoRig.V2.Kind')==object.kind
  end
  if valid(candidate) then return candidate end
  local match
  for _,tool in pairs(self.comp:GetToolList(false) or {}) do
    if valid(tool) then
      if match then fail('multiple Fusion tools claim object ID '..object.id) end
      match=tool
    end
  end
  return match
end
-- Resolve the scene chain by owned identities. Node names can be changed
-- freely in the Fusion Node Editor without invalidating Scene references.
function H:resolve_camera(scene)
  if not scene or not scene.id or not scene.objects or not scene.objects[2] then fail('scene camera identity missing') end
  local id=scene.objects[2].id
  local match
  for _,tool in pairs(self.comp:GetToolList(false) or {}) do
    if tool:GetData('CartoRig.V2.Owned')==true
      and tool:GetData('CartoRig.V2.SceneId')==scene.id
      and tool:GetData('CartoRig.V2.ObjectId')==id
      and tool:GetData('CartoRig.V2.Kind')=='Camera' then
      if match then fail('duplicate camera tool identity') end
      match=tool
    end
  end
  if not match then fail('CartoRig camera tool missing or detached') end
  return match
end
function H:resolve_last_layer(scene,pending_id)
  if not scene or type(scene.objects)~='table' then fail('scene object list missing') end
  local id,kind
  for i=#scene.objects,1,-1 do
    local object=scene.objects[i]
    if object.id~=pending_id and (object.kind=='Region' or object.kind=='Route' or object.kind=='Marker' or object.kind=='Label') then
      id=object.id;kind='InternalComposite';break
    end
  end
  if not id then id=scene.objects[1] and scene.objects[1].id;kind='BaseMap' end
  local match
  for _,tool in pairs(self.comp:GetToolList(false) or {}) do
    if tool:GetData('CartoRig.V2.Owned')==true
      and tool:GetData('CartoRig.V2.SceneId')==scene.id
      and tool:GetData('CartoRig.V2.ObjectId')==id
      and tool:GetData('CartoRig.V2.Kind')==kind then
      if match then fail('duplicate managed final-layer identity') end
      match=tool
    end
  end
  if not match then fail('managed final layer is missing or disconnected') end
  return match
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
  local foreign=0
  for _,tool in pairs(existing) do
    if tool~=out and tool:GetData('CartoRig.V2.Owned')~=true then foreign=foreign+1 end
  end
  local upstream,can_inspect=upstream_mediaout(out)
  -- Never overwrite a MediaOut wire if its previous source cannot be recovered.
  if foreign>0 and not can_inspect then
    fail('cannot inspect existing MediaOut Input; preserving all user nodes. Use a fresh Composition or a Fusion host with GetConnectedOutput')
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
    local baseStyle=scene.objects[1].style or {}
    local or_,og,ob=hex(baseStyle.ocean or '#10283C')
    base:SetInput('OceanRed',or_);base:SetInput('OceanGreen',og);base:SetInput('OceanBlue',ob)
    base:SetInput('BaseOpacity',(baseStyle.opacity or 100)/100)
    base:SetInput('OceanLayerOpacity',1)
    base:SetInput('DisplayMode',baseStyle.displayMode=='Transparent Overlay' and 1 or 0)
    local camera=new('CartoRigCamera','CR2_CAMERA_'..scene.id,0,0)
    local pose=scene.objects[2].style or {}
    camera:SetInput('CenterLongitude',pose.longitude or 0)
    camera:SetInput('CenterLatitude',pose.latitude or 0)
    camera:SetInput('Zoom',pose.zoom or 1)
    camera:SetInput('Bearing',pose.bearing or 0)
    connect(camera,'Input',base)
    if upstream then
      local overlay=new('Merge','CR2_OUTPUT_COMPOSITE_'..scene.id,1,1)
      self:tag(overlay,scene.id,'CartoRigOutput','InternalOutputComposite')
      connect(overlay,'Background',upstream)
      connect(overlay,'Foreground',camera)
      connect(out,'Input',overlay)
      scene.outputMergeToolRef=toolname(overlay)
      scene.externalSourceToolRef=toolname(upstream)
    else
      connect(out,'Input',camera)
    end
    for _,object in ipairs(scene.objects) do
      if object.kind=='BaseMap' then self:tag(base,scene.id,object.id,object.kind);object.hostToolRef=attr(base).TOOLS_Name or base.Name
      elseif object.kind=='Camera' then self:tag(camera,scene.id,object.id,object.kind);object.hostToolRef=attr(camera).TOOLS_Name or camera.Name end
    end
    scene.hostInitialized=true
    -- Last layer is BaseMap, not camera. It is the input to camera.
    scene.lastLayerRef=attr(base).TOOLS_Name or base.Name
  end,debug.traceback)
  if not ok then
    -- Undo may fail: reconnect the exact pre-existing source before removing nodes.
    pcall(function()out:ConnectInput('Input',upstream)end)
    for i=#created,1,-1 do pcall(function()created[i]:Delete()end) end
    scene.outputMergeToolRef=nil;scene.externalSourceToolRef=nil
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
  local out=self:media_out()
  if out then
    local prior=scene.externalSourceToolRef and find(self.comp,scene.externalSourceToolRef)
    if scene.externalSourceToolRef and not prior then
      fail('cannot roll back: original user MediaOut source has disappeared')
    end
    local ok,result=pcall(function()return out:ConnectInput('Input',prior)end)
    if not ok or result==false then fail('cannot restore original MediaOut wire; preserved managed tools for repair') end
  end
  for _,tool in pairs(self.comp:GetToolList(false) or {}) do
    if tool:GetData('CartoRig.V2.Owned')==true
       and tool:GetData('CartoRig.V2.SceneId')==scene.id then
      pcall(function() tool:Delete() end)
    end
  end
  scene.hostInitialized=false
  scene.lastLayerRef=nil
  scene.externalSourceToolRef=nil;scene.outputMergeToolRef=nil
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
-- Edit a Route in place rather than reconstructing its graph. Keeping the
-- PolylineMask tool preserves native WriteLength/BezierSpline animation.
-- The old native Polyline is saved for recovery if metadata persistence fails.
function H:update_route_mask(scene,object,points)
  if not scene or not object or object.kind~='Route' then fail('Route identity required') end
  if type(points)~='table' or #points<2 or #points>8192 then fail('Route sample budget exceeded') end
  local ring={}
  for i,p in ipairs(points) do
    if type(p)~='table' then fail('invalid geographic route point') end
    ring[i]={p.lon,p.lat}
    if i>1 and math.abs(p.lon-points[i-1].lon)>180 then
      fail('Route crosses the antimeridian; editing refused without safe seam-splitting')
    end
  end
  local polySource=mask_settings(ring,false)
  if not self.bridge or type(self.bridge.readstring)~='function' then fail('Fusion geometry parser unavailable') end
  local ok,newPolyline=pcall(function()return self.bridge.readstring(polySource)end)
  if not ok or not newPolyline then fail('Fusion rejected new Route geometry') end
  local mask=object.maskToolRef and find(self.comp,object.maskToolRef)
  if not mask or mask:GetData('CartoRig.V2.Owned')~=true
    or mask:GetData('CartoRig.V2.SceneId')~=scene.id
    or mask:GetData('CartoRig.V2.ObjectId')~=object.id
    or mask:GetData('CartoRig.V2.Kind')~='InternalMask' then
    fail('Route mask identity is broken; refusing to edit')
  end
  if type(mask.GetInput)~='function' then fail('Fusion cannot snapshot the existing Route geometry') end
  local oldOk,oldPolyline=pcall(function()return mask:GetInput('Polyline')end)
  if not oldOk or oldPolyline==nil then fail('Fusion cannot recover old Route geometry; editing refused') end
  local written,result=pcall(function()return mask:SetInput('Polyline',newPolyline)end)
  if not written or result==false then
    pcall(function()mask:SetInput('Polyline',oldPolyline)end)
    fail('Fusion refused new Route geometry; original geometry restored where supported')
  end
  return function()
    local restored,success=pcall(function()return mask:SetInput('Polyline',oldPolyline)end)
    if not restored or success==false then
      fail('Route rollback failed; stop editing and recover a project copy')
    end
    return true
  end
end
-- Polygon = outer ring + optional interior rings. The Fusion PolygonMask
-- effect-mask chain uses PaintMode=Subtract for each hole. A single result
-- mask represents the whole polygon, including its cutouts.
function H:_make_polygon_mask(rings,name)
  if type(rings)~='table' or #rings<1 or #rings>256 then fail('invalid polygon ring collection') end
  local created={}
  local ok,result=xpcall(function()
    local mask=self:_make_polyline_mask(rings[1],name..'_Outer',true)
    created[#created+1]=mask
    for index=2,#rings do
      local hole=self:_make_polyline_mask(rings[index],name..'_Hole_'..tostring(index-1),true)
      created[#created+1]=hole
      local parser=self.bridge
      local good,subtract=pcall(function()return parser.readstring('FuID { "Subtract" }') end)
      if not good or not subtract then fail('Fusion could not deserialize the Subtract PaintMode') end
      local applied,actual=pcall(function()return hole:SetInput('PaintMode',subtract)end)
      if not applied or actual==false then fail('Fusion rejected mask hole Subtract PaintMode') end
      connect(hole,'EffectMask',mask)
      mask=hole
    end
    return mask
  end,debug.traceback)
  if not ok then
    for i=#created,1,-1 do pcall(function()created[i]:Delete()end)end
    fail('polygon mask chain rolled back: '..tostring(result))
  end
  return result,created
end
function H:add_region(scene,object,feature)
  if object.kind~='Region' then fail('object must be a Region') end
  local polygons=GeoClip.split_polygons(geometry_rings(feature))
  local needed=0
  for _,polygon in ipairs(polygons) do
    if #polygon<1 or #polygon>256 then fail('polygon ring budget exceeded') end
    for _,ring in ipairs(polygon) do
      if type(ring)~='table' or #ring<3 or #ring>10000 then fail('invalid geographic ring') end
      for i=1,#ring do
        local pt=ring[i]
        if type(pt)~='table' or type(pt[1])~='number' or type(pt[2])~='number' or pt[1]~=pt[1] or pt[2]~=pt[2]
            or math.abs(pt[1])>180 or math.abs(pt[2])>90 then fail('invalid geographic ring coordinate') end
        if i>1 and math.abs(pt[1]-ring[i-1][1])>180 then
          fail('region boundary crosses antimeridian; safe seam-splitting required before render')
        end
      end
      needed=needed+1
    end
  end
  if needed>200 then fail('region exceeds safe native mask preview budget') end
  local camera=self:resolve_camera(scene)
  local previous=self:resolve_last_layer(scene,object.id)
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
    -- A separate transparent stroke matte carries all outer and inner ring
    -- contours; one authorial Region Fuse controls its style and opacity.
    local strokeCanvas=new('Background','CR2_STROKE_EMPTY_'..object.id,-3,6)
    strokeCanvas:SetInput('TopLeftRed',0);strokeCanvas:SetInput('TopLeftGreen',0)
    strokeCanvas:SetInput('TopLeftBlue',0);strokeCanvas:SetInput('TopLeftAlpha',0)
    self:tag(strokeCanvas,scene.id,object.id,'InternalStrokeCanvas')
    local strokeMatte=strokeCanvas
    for i,polygon in ipairs(polygons) do
      local mask,maskNodes=self:_make_polygon_mask(polygon,'CR2_MASK_'..object.id..'_'..i)
      for _,part in ipairs(maskNodes) do
        created[#created+1]=part
        self:tag(part,scene.id,object.id,'InternalMask')
      end
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
      for ringIndex,ring in ipairs(polygon) do
        local contour=self:_make_polyline_mask(ring,
          'CR2_STROKE_MASK_'..object.id..'_'..i..'_'..ringIndex,true)
        created[#created+1]=contour
        self:tag(contour,scene.id,object.id,'InternalStrokeMask')
        contour:SetInput('Solid',0)
        contour:SetInput('BorderWidth',(object.style.strokeWidth or 1.5)/1080)
        local strokeWhite=new('Background','CR2_STROKE_WHITE_'..object.id..'_'..i..'_'..ringIndex,-1,i)
        strokeWhite:SetInput('TopLeftRed',1);strokeWhite:SetInput('TopLeftGreen',1)
        strokeWhite:SetInput('TopLeftBlue',1);strokeWhite:SetInput('TopLeftAlpha',1)
        self:tag(strokeWhite,scene.id,object.id,'InternalStrokeFill')
        connect(strokeWhite,'EffectMask',contour)
        local borderPiece=new('Merge','CR2_STROKE_COMPOSITE_'..object.id..'_'..i..'_'..ringIndex,2,i)
        self:tag(borderPiece,scene.id,object.id,'InternalStrokeComposite')
        connect(borderPiece,'Background',strokeMatte)
        connect(borderPiece,'Foreground',strokeWhite)
        strokeMatte=borderPiece
      end
    end
    local region=new('CartoRigRegion','CR2_REGION_'..object.id,3,4)
    self:tag(region,scene.id,object.id,'Region')
    connect(region,'Input',matte)
    connect(region,'StrokeInput',strokeMatte)
    local sr,sg,sb=hex(object.style.stroke or '#D7E0E7')
    region:SetInput('StrokeRed',sr);region:SetInput('StrokeGreen',sg);region:SetInput('StrokeBlue',sb)
    region:SetInput('StrokeAlpha',(object.style.strokeAlpha or 100)/100)
    region:SetInput('StrokeVisible',object.style.strokeVisible==false and 0 or 1)
    local r,g,b=hex(object.style.fill or '#8296A4')
    region:SetInput('FillRed',r);region:SetInput('FillGreen',g);region:SetInput('FillBlue',b)
    region:SetInput('FillAlpha',(object.style.fillAlpha or 100)/100)
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
  -- Hide/Show is structural and must never replace hand-authored Blend keys.
  -- Query the native input whenever the host makes spline inspection available.
  if blend:GetData('CartoRig.V2.Animated.Blend')==true then
    fail('CONFLICT: Fusion composite Blend is animated; Hide/Show would overwrite keyframes')
  end
  if type(blend.GetInputList)=='function' then
    local inspected,inputs=pcall(function()return blend:GetInputList()end)
    if not inspected then fail('could not inspect Fusion composite animation') end
    if type(inputs)=='table' and inputs.Blend and type(inputs.Blend.GetKeyFrames)=='function' then
      local okkeys,keys=pcall(function()return inputs.Blend:GetKeyFrames()end)
      if not okkeys then fail('could not read Fusion composite Blend keyframes') end
      if type(keys)=='table' and next(keys) then
        fail('CONFLICT: Fusion composite Blend has manual keyframes; structural Hide/Show refused')
      end
    end
  end
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

-- Static Control write adapter. Stage all native changes with readback and
-- per-input snapshots. The caller commits Scene JSON only after Fusion accepts
-- every change; if persistence fails, rollback restores original native inputs.
local styleBinding={
  Region={fill={'color','Fill'},fillAlpha={'scalar','FillAlpha',0.01},opacity={'scalar','ObjectOpacity',0.01},
    stroke={'color','Stroke'},strokeAlpha={'scalar','StrokeAlpha',0.01},strokeVisible={'bool','StrokeVisible'}},
  Marker={fill={'color','Fill'},fillAlpha={'scalar','FillAlpha',0.01},opacity={'scalar','ObjectOpacity',0.01},size={'masksize','Width','Height',1/1080}},
  Route={stroke={'color','Stroke'},strokeAlpha={'scalar','StrokeAlpha',0.01},opacity={'scalar','ObjectOpacity',0.01},
    drawProgress={'maskscalar','WriteLength',0.01},strokeWidth={'maskscalar','BorderWidth',1/1080}},
  Label={color={'color','Text'},opacity={'scalar','ObjectOpacity',0.01},fontSize={'textsize','Size',1/1080}},
  Camera={longitude={'scalar','CenterLongitude',1},latitude={'scalar','CenterLatitude',1},zoom={'scalar','Zoom',1},bearing={'scalar','Bearing',1}},
  BaseMap={ocean={'color','Ocean'},opacity={'scalar','BaseOpacity',0.01},displayMode={'enum','DisplayMode'}},
}
local function safe_style_tool(host,scene,object,kind)
  if kind=='object' then return host:tool_for(object) end
  if kind=='mask' then
    local tool=object.maskToolRef and find(host.comp,object.maskToolRef)
    if not tool or tool:GetData('CartoRig.V2.ObjectId')~=object.id
      or tool:GetData('CartoRig.V2.SceneId')~=scene.id
      or tool:GetData('CartoRig.V2.Kind')~='InternalMask' then fail('style mask no longer belongs to selected object') end
    return tool
  end
  if kind=='text' then
    local match=nil
    for _,tool in pairs(host.comp:GetToolList(false) or {}) do
      if tool:GetData('CartoRig.V2.ObjectId')==object.id
        and tool:GetData('CartoRig.V2.SceneId')==scene.id
        and tool:GetData('CartoRig.V2.Kind')=='InternalLabelText' then
        if match then fail('ambiguous Label text renderer') end
        match=tool
      end
    end
    return match
  end
end
local function active_keys(tool,input)
  if tool:GetData('CartoRig.V2.Animated.'..input)==true then return true end
  if type(tool.GetInputList)~='function' then return false end
  local ok,all=pcall(function() return tool:GetInputList() end)
  if not ok or type(all)~='table' then return false end
  local field=all[input]
  if field and type(field.GetKeyFrames)=='function' then
    local good,keys=pcall(function()return field:GetKeyFrames()end)
    if not good then fail('cannot inspect native keyframes for '..input) end
    if type(keys)=='table' and next(keys) then return true end
  end
  if field and type(field.GetConnectedOutput)=='function' then
    local good,src=pcall(function()return field:GetConnectedOutput()end)
    if not good then fail('cannot inspect native input connections for '..input) end
    if src then return true end
  end
  return false
end
-- Read the host composition's real frame dimensions; never fit against an
-- invented 16:9 viewport. Some Fusion versions expose width/height only
-- through GetPrefs, others expose evaluated Composition attributes.
function H:viewport()
  local comp=self.comp
  local w,h
  if type(comp.GetPrefs)=='function' then
    local goodWidth,width=pcall(function()return comp:GetPrefs('Comp.FrameFormat.Width')end)
    local goodHeight,height=pcall(function()return comp:GetPrefs('Comp.FrameFormat.Height')end)
    if goodWidth then w=tonumber(width) end
    if goodHeight then h=tonumber(height) end
  end
  if (not w or not h) and type(comp.GetAttrs)=='function' then
    local ok,attrs=pcall(function()return comp:GetAttrs()end)
    if ok and type(attrs)=='table' then
      w=w or tonumber(attrs.COMPN_RenderWidth)
      h=h or tonumber(attrs.COMPN_RenderHeight)
    end
  end
  if not w or not h or w<16 or h<16 or w>16384 or h>16384 then
    fail('cannot read active Fusion composition resolution; Fit was not applied')
  end
  return w,h
end
function H:prepare_style(scene,object,key,value)
  if not scene or not object or not object.id then fail('style requires a scene and object identity') end
  if object.locked then fail('object is locked') end
  local binding=styleBinding[object.kind] and styleBinding[object.kind][key]
  if not binding then
    fail('Control property '..tostring(key)..' is not yet implemented in native '..object.kind..' renderer')
  end
  local mode=binding[1]
  local kind=(mode=='maskscalar' or mode=='masksize') and 'mask' or (mode=='textsize' and 'text' or 'object')
  local tool=safe_style_tool(self,scene,object,kind)
  if not tool or type(tool.GetInput)~='function' then fail('native Control tool or safe input readback unavailable') end
  local values={}
  if mode=='color' then
    local r,g,b=hex(value)
    local prefix=binding[2]
    values={{prefix..'Red',r},{prefix..'Green',g},{prefix..'Blue',b}}
  elseif mode=='enum' then
    if value~='Full Map' and value~='Transparent Overlay' then fail('invalid display mode') end
    values={{binding[2],value=='Transparent Overlay' and 1 or 0}}
  elseif mode=='bool' then
    if type(value)~='boolean' then fail('expected boolean native Control value') end
    values={{binding[2],value and 1 or 0}}
  elseif mode=='masksize' then
    values={{binding[2],value*binding[4]},{binding[3],value*binding[4]}}
  else
    values={{binding[2],value*(binding[3] or 1)}}
  end
  local snapshot={}
  for _,row in ipairs(values) do
    local id=row[1]
    if active_keys(tool,id) then fail('CONFLICT: '..id..' is animated or connected in Fusion; edit at the playhead') end
    local good,old=pcall(function()return tool:GetInput(id)end)
    if not good or old==nil then fail('cannot snapshot '..id..'; refusing a non-recoverable change') end
    snapshot[#snapshot+1]={id,old}
  end
  local function undo()
    local errors={}
    for i=#snapshot,1,-1 do
      local row=snapshot[i]
      local ok,result=pcall(function()return tool:SetInput(row[1],row[2])end)
      if not ok or result==false then errors[#errors+1]=row[1] end
    end
    if #errors>0 then fail('Control rollback failed on '..table.concat(errors,', ')..'; recover a saved project') end
    return true
  end
  local written={}
  for _,row in ipairs(values) do
    local success,result=pcall(function()return tool:SetInput(row[1],row[2])end)
    if not success or result==false then
      undo()
      fail('Fusion rejected static Control value '..row[1])
    end
    written[#written+1]=row[1]
  end
  return undo
end

return H
