-- CartoRig Fusion-first rewrite: canonical object model (no host dependency).
-- A scene describes AUTHORIAL objects; Fusion remains the sole temporal authority.
local M = {}
local function fail(s) error('CartoRig scene: ' .. s, 2) end
local function copy(x, seen)
  if type(x) ~= 'table' then return x end
  seen = seen or {}
  if seen[x] then return seen[x] end
  local y = {}; seen[x] = y
  for k, v in pairs(x) do y[copy(k, seen)] = copy(v, seen) end
  return y
end
M.copy = copy
local types = { BaseMap=true, Camera=true, Region=true, Route=true, Marker=true, Label=true, Group=true }
local style = {
  Region={ fill='#8296A4', fillAlpha=100, stroke='#D7E0E7', strokeWidth=1.5, strokeAlpha=100, opacity=100 },
  Route={ stroke='#D6DFE6', strokeWidth=3, strokeAlpha=100, opacity=100, drawProgress=100, trimStart=0, trimEnd=100, arrowhead=false },
  Marker={ fill='#E0E8ED', stroke='#142637', size=14, strokeWidth=1.5, opacity=100 },
  Label={ color='#F0F5F8', fontSize=32, halo=true, opacity=100 },
  BaseMap={ ocean='#10283C', land='#394C59', opacity=100, displayMode='Full Map' },
  Camera={ longitude=0, latitude=0, zoom=1, bearing=0, fitPadding=8 },
  Group={},
}
local colors={ fill=true,stroke=true,color=true,ocean=true,land=true }
local pct={ fillAlpha=true,strokeAlpha=true,opacity=true,drawProgress=true,trimStart=true,trimEnd=true,fitPadding=true }
local positive={ strokeWidth=true,size=true,fontSize=true,zoom=true }
local function valid_style(key, value)
  if colors[key] then return type(value)=='string' and value:match('^#%x%x%x%x%x%x$')~=nil end
  if pct[key] then return type(value)=='number' and value==value and value>=0 and value<=100 end
  if positive[key] then return type(value)=='number' and value==value and value>=0 and value<1e6 end
  if key=='longitude' or key=='bearing' then return type(value)=='number' and value>=-180 and value<=180 end
  if key=='latitude' then return type(value)=='number' and value>=-85 and value<=85 end
  if key=='displayMode' then return value=='Full Map' or value=='Transparent Overlay' end
  if key=='halo' or key=='arrowhead' then return type(value)=='boolean' end
  return value~=nil
end
local function find(scene,id)
  for i,object in ipairs(scene.objects) do if object.id==id then return object,i end end
end
function M.get(scene,id) return find(scene,id) end
local function next_id(scene,kind)
  scene.serial=scene.serial+1
  return scene.id .. ':' .. kind .. ':' .. tostring(scene.serial)
end
local function node(scene,kind,name,extra)
  local item={ id=next_id(scene,kind), kind=kind, name=name, visible=true, locked=false,
    style=copy(style[kind]), motion={}, source=nil, related={}, drawOrder=#scene.objects+1 }
  if extra then for k,v in pairs(extra) do item[k]=copy(v) end end
  scene.objects[#scene.objects+1]=item
  return item
end
function M.new(scene_id,manifest_id)
  if type(scene_id)~='string' or #scene_id<8 then fail('scene_id must be a stable nonempty identifier') end
  local scene={id=scene_id,schema='cartorig.scene/1',manifestId=manifest_id or 'unknown', serial=0, objects={},selected=nil}
  node(scene,'BaseMap','Base Map')
  node(scene,'Camera','Camera')
  return scene
end
local function assert_editable(scene,obj)
  if not obj then fail('object not found') end
  if obj.locked then fail('object locked') end
  if obj.groupId then
    local group=find(scene,obj.groupId)
    if group and group.locked then fail('parent group locked') end
  end
end
local function assert_point(point)
  if type(point)~='table' or type(point.lon)~='number' or type(point.lat)~='number'
    or point.lon~=point.lon or point.lat~=point.lat or math.abs(point.lon)>180 or math.abs(point.lat)>90
  then fail('endpoint must be explicit WGS84 longitude and latitude') end
end
function M.add_location(scene,feature,kind)
  if kind~='Region' and kind~='Marker' and kind~='Label' then fail('invalid geographic object kind') end
  if not feature or type(feature.id)~='string' or type(feature.name)~='string' then fail('feature identity missing') end
  if kind=='Region' then
    if feature.geometryType~='Polygon' and feature.geometryType~='MultiPolygon' then
      fail('location has no polygon; do not fabricate administrative boundaries')
    end
  else
    if not feature.point then fail('location has no explicit point') end
    assert_point(feature.point)
  end
  return node(scene,kind,feature.name,{ source={ featureId=feature.id,version=feature.version,
    dataset=feature.dataset,type=feature.type }, anchor=feature.point })
end
function M.add_route(scene,from,to)
  assert_point(from); assert_point(to)
  if from.lon==to.lon and from.lat==to.lat then fail('route endpoints coincide') end
  return node(scene,'Route','Route',{ route={from=copy(from),to=copy(to),waypoints={},pathType='Straight',curvature=0} })
end
function M.rename(scene,id,name)
  local obj=find(scene,id);assert_editable(scene,obj)
  if type(name)~='string' or #name==0 or #name>160 then fail('invalid object name') end
  obj.name=name
end
function M.set_style(scene,id,key,value)
  local obj=find(scene,id);assert_editable(scene,obj)
  if style[obj.kind][key]==nil then fail('property '..tostring(key)..' unsupported for '..obj.kind) end
  if not valid_style(key,value) then fail('invalid value for '..key) end
  if key=='trimStart' and value>obj.style.trimEnd then fail('trim start exceeds end') end
  if key=='trimEnd' and value<obj.style.trimStart then fail('trim end precedes start') end
  obj.style[key]=value
end
function M.set_visible(scene,id,value)
  local obj=find(scene,id);assert_editable(scene,obj)
  if type(value)~='boolean' then fail('visibility must be boolean') end
  obj.visible=value
end
function M.set_lock(scene,id,value)
  local obj=find(scene,id)
  if not obj then fail('object not found') end
  if type(value)~='boolean' then fail('lock must be boolean') end
  obj.locked=value
end
function M.select(scene,id)
  if id and not find(scene,id) then fail('object not found') end
  scene.selected=id
end
local function has_dependencies(scene,id)
  for _,obj in ipairs(scene.objects) do
    if obj.id~=id and (obj.groupId==id or obj.related[id] or (obj.route and obj.route.followerId==id)) then return true end
  end
  return false
end
function M.remove(scene,id)
  local obj,index=find(scene,id);assert_editable(scene,obj)
  if obj.kind=='BaseMap' or obj.kind=='Camera' then fail('cannot delete structural scene object') end
  if has_dependencies(scene,id) then fail('object is referenced; unlink dependents explicitly') end
  table.remove(scene.objects,index)
  if scene.selected==id then scene.selected=nil end
  for n,v in ipairs(scene.objects) do v.drawOrder=n end
end
function M.duplicate(scene,id)
  local obj=find(scene,id);assert_editable(scene,obj)
  if obj.kind=='BaseMap' or obj.kind=='Camera' then fail('cannot duplicate scene singleton') end
  local result=copy(obj)
  result.id=next_id(scene,obj.kind)
  result.name=obj.name..' Copy'
  result.drawOrder=#scene.objects+1
  scene.objects[#scene.objects+1]=result
  return result
end
function M.reorder(scene,id,newIndex)
  local obj,index=find(scene,id);assert_editable(scene,obj)
  if obj.kind=='BaseMap' or obj.kind=='Camera' then fail('structural nodes cannot be reordered') end
  if type(newIndex)~='number' or newIndex%1~=0 or newIndex<3 or newIndex>#scene.objects then fail('invalid draw index') end
  table.remove(scene.objects,index)
  table.insert(scene.objects,newIndex,obj)
  for i,v in ipairs(scene.objects) do v.drawOrder=i end
end
function M.snapshot(scene)
  return copy(scene)
end
function M.validate(scene)
  if scene.schema~='cartorig.scene/1' then fail('unsupported scene schema') end
  local seen={}
  for i,o in ipairs(scene.objects) do
    if not types[o.kind] or seen[o.id] or o.drawOrder~=i then fail('invalid object graph at index '..i) end
    seen[o.id]=true
  end
  if scene.objects[1].kind~='BaseMap' or scene.objects[2].kind~='Camera' then fail('structural objects missing') end
  if scene.selected and not seen[scene.selected] then fail('dangling selection') end
  return true
end
return M
