-- CartoRig: deterministic WGS84 antimeridian clipping for polygon authoring.
-- Returns original polygon topology as one or two (possibly more) camera-world
-- pieces. No interpolation of legal boundaries or invented feature geometry.
local G={}
local function fail(s) error('CartoRig geo clip: '..s,2) end
local abs=math.abs
local floor=math.floor
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function close(a,b) return abs(a-b)<1e-9 end
local function same(a,b) return close(a[1],b[1]) and close(a[2],b[2]) end
local function strip_duplicates(ring)
  local result={}
  for _,p in ipairs(ring) do
    if not result[#result] or not same(result[#result],p) then result[#result+1]={p[1],p[2]} end
  end
  if #result>1 and same(result[1],result[#result]) then result[#result]=nil end
  return result
end
local function validate_ring(ring)
  if type(ring)~='table' or #ring<3 or #ring>200000 then fail('invalid ring vertex budget') end
  local pts={}
  for _,p in ipairs(ring) do
    if type(p)~='table' or not finite(p[1]) or not finite(p[2]) or abs(p[1])>180 or abs(p[2])>90 then fail('invalid geographic coordinate') end
    pts[#pts+1]={p[1],p[2]}
  end
  pts=strip_duplicates(pts)
  if #pts<3 then fail('degenerate geographic ring') end
  return pts
end
local function unwrap(input)
  local result={{input[1][1],input[1][2]}}
  for i=2,#input do
    local prev=result[#result][1]
    local lon=input[i][1]
    local delta=(lon-prev+180)%360-180
    if close(delta,-180) and lon-prev>0 then delta=180 end
    result[#result+1]={prev+delta,input[i][2]}
  end
  if abs(result[#result][1]-result[1][1])>180+1e-8 then
    fail('ring winds around a pole/world; explicit polar projection required')
  end
  return result
end
local function mean_x(points)
  local sum=0
  for _,p in ipairs(points) do sum=sum+p[1] end
  return sum/#points
end
local function area(ring)
  local n=#ring;local sum=0
  for i=1,n do local a,b=ring[i],ring[i%n+1];sum=sum+(a[1]*b[2]-b[1]*a[2]) end
  return sum/2
end
local function edge_clip(points,bound,greater)
  if #points==0 then return {} end
  local output={}
  local function inside(p) return (greater and p[1]>=bound-1e-10) or (not greater and p[1]<=bound+1e-10) end
  local function intersect(a,b)
    local dx=b[1]-a[1]
    if abs(dx)<1e-12 then return {bound,a[2]} end
    local u=(bound-a[1])/dx
    return {bound,a[2]+u*(b[2]-a[2])}
  end
  local last=points[#points]
  for _,p in ipairs(points) do
    local was,now=inside(last),inside(p)
    if now then
      if not was then output[#output+1]=intersect(last,p) end
      output[#output+1]=p
    elseif was then output[#output+1]=intersect(last,p) end
    last=p
  end
  return strip_duplicates(output)
end
local function clip_to_world(points,shift)
  local translated={}
  for i,p in ipairs(points) do translated[i]={p[1]+shift*360,p[2]} end
  local result=edge_clip(edge_clip(translated,-180,true),180,false)
  if #result<3 or abs(area(result))<1e-9 then return nil end
  for _,p in ipairs(result) do
    if p[1]<-180-1e-8 or p[1]>180+1e-8 then fail('clip escaped world seam') end
    p[1]=math.max(-180,math.min(180,p[1]))
  end
  return result
end
-- Returns a list of GeoJSON polygon arrays, preserving the ring order:
-- { {outer, hole, ...}, {outer, ...} }.
function G.split_polygon(polygon)
  if type(polygon)~='table' or #polygon==0 or #polygon>256 then fail('invalid polygon ring collection') end
  local unwrapped={};local outer_mean
  for i,ring in ipairs(polygon) do
    local path=unwrap(validate_ring(ring))
    if i==1 then outer_mean=mean_x(path)
    else
      local adjustment=floor((outer_mean-mean_x(path))/360+0.5)*360
      for _,p in ipairs(path) do p[1]=p[1]+adjustment end
    end
    unwrapped[#unwrapped+1]=path
  end
  local shifts={};local shiftseen={}
  local minx,maxx=math.huge,-math.huge
  for _,p in ipairs(unwrapped[1]) do minx=math.min(minx,p[1]);maxx=math.max(maxx,p[1]) end
  if maxx-minx>360+1e-6 then fail('unbounded polygon longitude span') end
  local first=math.ceil((-180-maxx)/360)
  local last=floor((180-minx)/360)
  if last-first>2 then fail('polygon spans too many wrapped worlds') end
  for shift=first,last do
    if not shiftseen[shift] then shifts[#shifts+1]=shift;shiftseen[shift]=true end
  end
  local results={}
  for _,shift in ipairs(shifts) do
    local outer=clip_to_world(unwrapped[1],shift)
    if outer then
      local piece={outer}
      for i=2,#unwrapped do
        local hole=clip_to_world(unwrapped[i],shift)
        if hole then piece[#piece+1]=hole end
      end
      results[#results+1]=piece
    end
  end
  if #results==0 then fail('polygon is empty after antimeridian clipping') end
  return results
end
function G.split_polygons(polygons)
  if type(polygons)~='table' or #polygons==0 then fail('empty polygon collection') end
  local all={}
  for _,polygon in ipairs(polygons) do
    local split=G.split_polygon(polygon)
    for _,piece in ipairs(split) do all[#all+1]=piece end
  end
  return all
end
return G
