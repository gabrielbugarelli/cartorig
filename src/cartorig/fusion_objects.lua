-- CartoRig Fusion native object authoring adapter (engineering preview).
-- The owning composition, not this module or the UI, stores all rendering tools.
-- Each insertion is fail-closed: validate first, then roll back only newly-owned tools.
local O={}
local function fail(message) error('CartoRig objects: '..message,2) end
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function point(value)
  if type(value)~='table' or not finite(value.lon) or not finite(value.lat) or math.abs(value.lon)>180 or math.abs(value.lat)>90 then
    fail('expected explicit WGS84 point')
  end
  -- Native Fusion coordinates are bottom-up; geo.lua screen() uses top-down pixels.
  return {(value.lon+180)/360,(value.lat+90)/180}
end
O.normalized=point
local function safe_name(node)
  local ok,attrs=pcall(function()return node:GetAttrs()end)
  return ok and attrs and attrs.TOOLS_Name or node.Name
end
local function color(value)
  if type(value)~='string' or not value:match('^#%x%x%x%x%x%x$') then fail('expected #RRGGBB') end
  return tonumber(value:sub(2,3),16)/255,tonumber(value:sub(4,5),16)/255,tonumber(value:sub(6,7),16)/255
end
local function assign_rgba(node,value,alpha,prefix)
  local r,g,b=color(value)
  prefix=prefix or 'TopLeft'
  node:SetInput(prefix..'Red',r)
  node:SetInput(prefix..'Green',g)
  node:SetInput(prefix..'Blue',b)
  if alpha~=nil then node:SetInput(prefix..'Alpha',alpha) end
end
local function add(comp,created,reg,name)
  local tool=comp:AddTool(reg,false,-32768,-32768)
  if not tool then fail('Fusion refused to create '..reg) end
  created[#created+1]=tool
  tool:SetAttrs({TOOLS_Name=name})
  tool:SetData('CartoRig.V2.Owned',true)
  return tool
end
local function link(dst,input,src)
  local ok,result=pcall(function()return dst:ConnectInput(input,src)end)
  if not ok or result==false then fail('Fusion refused '..input..' connection: '..tostring(result)) end
end
local function validate_route(route)
  if type(route)~='table' or not route.from or not route.to then fail('Route has no endpoints') end
  point(route.from);point(route.to)
  local pts={route.from}
  if type(route.waypoints)~='table' then fail('Route waypoints must be an array') end
  for _,p in ipairs(route.waypoints) do point(p);pts[#pts+1]=p end
  pts[#pts+1]=route.to
  if #pts>102 then fail('Route exceeds waypoint limit') end
  return pts
end
function O.build(host,scene,object,kind,points)
  if not host or not scene or not object or not object.id then fail('object/scene required') end
  local comp=host.comp
  if type(comp.AddTool)~='function' then fail('Fusion Composition not available') end
  if object.hostToolRef then fail('object already has a Fusion tool') end
  local camera=host:resolve_camera(scene)
  local previous=host:resolve_last_layer(scene,object.id)
  if kind=='Marker' or kind=='Label' then
    if not object.anchor then fail(kind..' requires geographic anchor') end
    point(object.anchor)
  elseif kind=='Route' then
    validate_route(object.route)
    if type(points)~='table' or #points<2 or #points>8192 then fail('Route sampling invalid') end
    for i,p in ipairs(points) do
      point(p)
      if i>1 and math.abs(p.lon-points[i-1].lon)>180 then
        fail('Route crosses the antimeridian; native line writer requires safe seam-splitting before insertion')
      end
    end
  else fail('unsupported native authoring kind '..tostring(kind)) end
  local created={}
  local began=false
  if comp.StartUndo then comp:StartUndo('CartoRig: create '..kind);began=true end
  local ok,err=xpcall(function()
    local raw,mask
    if kind=='Label' then
      raw=add(comp,created,'TextPlus','CR2_LABEL_TEXT_'..object.id)
      raw:SetInput('StyledText',object.text or object.name or '')
      local xy=point(object.anchor)
      raw:SetInput('Center',{xy[1],xy[2]})
      raw:SetInput('Size',(object.style.fontSize or 32)/1080)
      raw:SetInput('Red1',1);raw:SetInput('Green1',1)
      raw:SetInput('Blue1',1);raw:SetInput('Alpha1',1)
      host:tag(raw,scene.id,object.id,'InternalLabelText')
    else
      raw=add(comp,created,'Background','CR2_WHITE_'..kind:upper()..'_'..object.id)
      assign_rgba(raw,'#FFFFFF',1)
      host:tag(raw,scene.id,object.id,'Internal'..kind..'Fill')
      if kind=='Marker' then
        mask=add(comp,created,'EllipseMask','CR2_MARKER_MASK_'..object.id)
        mask:SetInput('Center',point(object.anchor))
        -- Mask coordinates are relative to the underlying world canvas.
        mask:SetInput('Width',(object.style.size or 14)/1080)
        mask:SetInput('Height',(object.style.size or 14)/1080)
      elseif kind=='Route' then
        local coords={}
        for _,p in ipairs(points) do coords[#coords+1]={p.lon,p.lat} end
        mask=host:_make_polyline_mask(coords,'CR2_ROUTE_MASK_'..object.id,false)
        created[#created+1]=mask
        mask:SetInput('Solid',0)
        mask:SetInput('WriteLength',(object.style.drawProgress or 100)/100)
        mask:SetInput('BorderWidth',(object.style.strokeWidth or 3)/1080)
      end
      link(raw,'EffectMask',mask)
    end
    local fg=add(comp,created,'CartoRig'..kind,'CR2_'..kind:upper()..'_'..object.id)
    host:tag(fg,scene.id,object.id,kind)
    link(fg,'Input',raw)
    local colorValue=object.style.fill or object.style.stroke or object.style.color or '#FFFFFF'
    local rr,gg,bb=color(colorValue)
    local colorPrefix=kind=='Marker' and 'Fill' or (kind=='Route' and 'Stroke' or 'Text')
    fg:SetInput(colorPrefix..'Red',rr)
    fg:SetInput(colorPrefix..'Green',gg)
    fg:SetInput(colorPrefix..'Blue',bb)
    if kind~='Label' then fg:SetInput(colorPrefix..'Alpha',
      ((kind=='Marker' and object.style.fillAlpha) or (kind=='Route' and object.style.strokeAlpha) or 100)/100) end
    fg:SetInput('ObjectOpacity',(object.style.opacity or 100)/100)
    if mask then host:tag(mask,scene.id,object.id,'InternalMask') end
    local merge=add(comp,created,'Merge','CR2_COMPOSITE_'..object.id)
    host:tag(merge,scene.id,object.id,'InternalComposite')
    link(merge,'Background',previous)
    link(merge,'Foreground',fg)
    link(camera,'Input',merge)
    object.hostToolRef=safe_name(fg)
    object.maskToolRef=mask and safe_name(mask) or nil
    object.compositeToolRef=safe_name(merge)
    scene.lastLayerRef=safe_name(merge)
  end,debug.traceback)
  if not ok then
    pcall(function()link(camera,'Input',previous)end)
    for i=#created,1,-1 do pcall(function()created[i]:Delete()end)end
  end
  if began and comp.EndUndo then comp:EndUndo(ok) end
  if not ok then fail('rolled back '..kind..': '..tostring(err)) end
  return object
end
return O
