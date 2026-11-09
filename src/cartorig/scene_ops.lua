-- Safe structural mutations on the canonical CartoRig scene. No host side effects.
local M={}
local function fail(x) error('CartoRig scene operation: '..x,2) end
local function finite(x) return type(x)=='number' and x==x and x<math.huge and x>-math.huge end
local function point(p)
  return type(p)=='table' and finite(p.lon) and finite(p.lat) and p.lon>=-180 and p.lon<=180 and p.lat>=-90 and p.lat<=90
end
local function locate(scene,id)
  for _,o in ipairs(scene.objects or {}) do if o.id==id then return o end end
end
local function assert_mutable(scene,obj)
  if not obj then fail('object missing') end
  if obj.locked then fail('object locked') end
  -- Lock applies transitively, including nested group folders. Never allow
  -- lower-level Route operations to bypass Scene's ancestor lock policy.
  local cursor=obj.groupId
  local visited={[obj.id]=true}
  while cursor do
    if visited[cursor] then fail('group cycle detected') end
    visited[cursor]=true
    local group=locate(scene,cursor)
    if not group or group.kind~='Group' then fail('dangling parent group') end
    if group.locked then fail('ancestor group locked') end
    cursor=group.groupId
  end
end
local function reachable(scene,id,target)
  local current=locate(scene,id)
  local seen={}
  while current and current.groupId do
    if current.groupId==target then return true end
    if seen[current.groupId] then fail('group cycle detected') end
    seen[current.groupId]=true
    current=locate(scene,current.groupId)
  end
  return false
end
function M.create_group(scene,core,name,ids)
  if type(name)~='string' or name=='' then fail('name required') end
  if type(ids)~='table' or #ids<1 then fail('at least one member required') end
  local unique={}
  for _,id in ipairs(ids) do
    if unique[id] then fail('duplicate member') end
    unique[id]=true
    local obj=locate(scene,id);assert_mutable(scene,obj)
    if obj.kind=='BaseMap' or obj.kind=='Camera' then fail('cannot group structural object') end
    if obj.groupId then fail('existing group member must first be ungrouped') end
  end
  local group=core.add_group(scene,name)
  for _,id in ipairs(ids) do locate(scene,id).groupId=group.id end
  return group
end
function M.ungroup(scene,id)
  local group=locate(scene,id);assert_mutable(scene,group)
  if group.kind~='Group' then fail('selection is not a group') end
  for _,o in ipairs(scene.objects) do if o.groupId==id then o.groupId=nil end end
  for i,o in ipairs(scene.objects) do
    if o.id==id then table.remove(scene.objects,i);break end
  end
  for i,o in ipairs(scene.objects) do o.drawOrder=i end
  if scene.selected==id then scene.selected=nil end
end
function M.update_route(scene,id,fields)
  local o=locate(scene,id);assert_mutable(scene,o)
  if o.kind~='Route' then fail('selection is not a route') end
  if type(fields)~='table' then fail('route edit required') end
  local new={}
  for key,value in pairs(o.route) do new[key]=value end
  for key,val in pairs(fields) do
    if key~='from' and key~='to' and key~='waypoints' and key~='pathType' and key~='curvature' and key~='followerId' then fail('unrecognized route field') end
    new[key]=val
  end
  if not point(new.from) or not point(new.to) then fail('route endpoints must be coordinates') end
  if new.from.lon==new.to.lon and new.from.lat==new.to.lat then fail('route endpoints coincide') end
  if new.pathType~='Straight' and new.pathType~='Curved' then fail('unsupported route path type') end
  if not finite(new.curvature) or new.curvature<-100 or new.curvature>100 then fail('curvature outside -100..100') end
  if type(new.waypoints)~='table' or #new.waypoints>100 then fail('invalid waypoint list') end
  for _,p in ipairs(new.waypoints) do if not point(p) then fail('waypoint must be WGS84 point') end end
  if new.followerId then
    local follower=locate(scene,new.followerId)
    if not follower or follower.kind~='Marker' then fail('follower must reference Marker in same scene') end
    if follower.locked then fail('follower is locked') end
    for _,other in ipairs(scene.objects) do
      if other.kind=='Route' and other.id~=id and other.route and other.route.followerId==new.followerId then
        fail('marker already follows another route')
      end
    end
  end
  o.route=new
  return o
end
function M.reverse_route(scene,id)
  local o=locate(scene,id);assert_mutable(scene,o)
  if o.kind~='Route' then fail('selection is not a route') end
  local r=o.route;r.from,r.to=r.to,r.from
  local rev={}
  for i=#r.waypoints,1,-1 do rev[#rev+1]=r.waypoints[i] end
  r.waypoints=rev
  -- Curvature offsets control points along the normal to each directed chord.
  -- Reversing the chords flips that normal; negate the signed curvature so
  -- the pixels follow the same geographic path in reverse, not a mirrored arc.
  if r.pathType=='Curved' then r.curvature=-r.curvature end
  return o
end
function M.validate_groups(scene)
  for _,o in ipairs(scene.objects or {}) do
    if o.groupId then
      local parent=locate(scene,o.groupId)
      if not parent or parent.kind~='Group' then fail('dangling group') end
      if reachable(scene,o.groupId,o.id) then fail('group cycle') end
    end
    if o.kind=='Route' and o.route then
      if not point(o.route.from) or not point(o.route.to) then fail('invalid route coordinates') end
      if o.route.followerId then
        local follower=locate(scene,o.route.followerId)
        if not follower or follower.kind~='Marker' then fail('dangling follower') end
      end
    end
  end
  return true
end
return M
