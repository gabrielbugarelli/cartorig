-- CartoRig geographic mathematics, independent of Fusion and OS.
-- WGS84 lon/lat in degrees; equirectangular world, shortest seam-aware camera path.
local M={}
local abs,sqrt,cos,sin,rad,atan=math.abs,math.sqrt,math.cos,math.sin,math.rad,math.atan
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
M.finite=finite
function M.valid_point(p)
  return type(p)=='table' and finite(p.lon) and finite(p.lat) and abs(p.lon)<=180 and abs(p.lat)<=90
end
function M.normalize_lon(lon)
  assert(finite(lon),'invalid longitude')
  local t=(lon+180)%360-180
  if t==-180 and lon>0 then return 180 end
  return t
end
function M.shortest_delta(from,to)
  local delta=(to-from+180)%360-180
  if delta==-180 and to-from>0 then return 180 end
  return delta
end
function M.project(point)
  assert(M.valid_point(point),'invalid WGS84 point')
  return {x=(point.lon+180)/360,y=(90-point.lat)/180}
end
function M.unproject(x,y)
  assert(finite(x) and finite(y),'invalid projected coordinates')
  return {lon=M.normalize_lon(x*360-180),lat=90-y*180}
end
function M.screen(point,camera,width,height)
  assert(M.valid_point(point),'invalid geographic point')
  assert(finite(width) and width>0 and finite(height) and height>0,'invalid viewport')
  camera=camera or {}
  local lon=camera.longitude or 0;local lat=camera.latitude or 0
  local zoom=camera.zoom or 1;local bearing=camera.bearing or 0
  assert(finite(zoom) and zoom>0 and finite(lat) and finite(lon) and finite(bearing),'invalid camera')
  local dx=M.shortest_delta(lon,point.lon)*height*zoom/180
  local dy=(lat-point.lat)*height*zoom/180
  local a=rad(bearing);local c,s=cos(a),sin(a)
  return {x=width/2+dx*c-dy*s,y=height/2+dx*s+dy*c}
end
function M.split_antimeridian(points)
  -- Return disjoint visible geographic lines. No accidental line crossing the full map.
  assert(type(points)=='table' and #points>=2,'line needs >=2 points')
  local result={{points[1]}}
  for i=2,#points do
    local prev,p=points[i-1],points[i]
    assert(M.valid_point(prev) and M.valid_point(p),'invalid line point')
    local delta=p.lon-prev.lon
    if abs(delta)>180 then
      local adjusted=p.lon+(delta>0 and -360 or 360)
      local seam=delta>0 and -180 or 180
      local denominator=adjusted-prev.lon
      local t=(seam-prev.lon)/denominator
      local lat=prev.lat+(p.lat-prev.lat)*t
      local a=result[#result];a[#a+1]={lon=seam,lat=lat}
      result[#result+1]={{lon=-seam,lat=lat},p}
    else result[#result][#result[#result]+1]=p end
  end
  return result
end
function M.point_in_ring(point,ring)
  assert(M.valid_point(point) and type(ring)=='table' and #ring>=3,'invalid polygon ring')
  local inside=false
  local x,y=point.lon,point.lat
  local last=ring[#ring]
  for _,v in ipairs(ring) do
    local x1,y1=last.lon or last[1],last.lat or last[2]
    local x2,y2=v.lon or v[1],v.lat or v[2]
    assert(finite(x1) and finite(y1) and finite(x2) and finite(y2),'invalid ring vertex')
    local cross=((y1>y)~=(y2>y)) and (x<(x2-x1)*(y-y1)/(y2-y1)+x1)
    if cross then inside=not inside end
    last=v
  end
  return inside
end
function M.contains(point,polygon)
  -- polygon = list of rings [outer, hole1, hole2, ...]
  if not polygon or not polygon[1] or not M.point_in_ring(point,polygon[1]) then return false end
  for i=2,#polygon do if M.point_in_ring(point,polygon[i]) then return false end end
  return true
end
function M.bezier(a,b,curvature,u)
  assert(M.valid_point(a) and M.valid_point(b),'route endpoints invalid')
  assert(finite(u) and u>=0 and u<=1,'invalid route interpolation')
  assert(finite(curvature) and abs(curvature)<=100,'invalid curvature')
  local delta=M.shortest_delta(a.lon,b.lon)
  local dx=delta/360;local dy=(b.lat-a.lat)/180
  local length=sqrt(dx*dx+dy*dy)
  local nx,ny=0,0
  if length>0 then nx=-dy/length;ny=dx/length end
  local shift=(curvature/100)*length*0.5
  local ax=a.lon/360;local ay=a.lat/180
  local bx=ax+dx;local by=ay+dy
  local cx=(ax+bx)/2+nx*shift;local cy=(ay+by)/2+ny*shift
  local q=1-u
  local xx=q*q*ax+2*q*u*cx+u*u*bx
  local yy=q*q*ay+2*q*u*cy+u*u*by
  return {lon=M.normalize_lon(xx*360),lat=yy*180}
end
function M.route_samples(route,count)
  assert(type(route)=='table' and M.valid_point(route.from) and M.valid_point(route.to),'invalid route')
  count=count or 64;assert(count>=2 and count<=4096,'invalid sample budget')
  local pts={route.from}
  for _,p in ipairs(route.waypoints or {}) do assert(M.valid_point(p),'invalid waypoint');pts[#pts+1]=p end
  pts[#pts+1]=route.to
  local all={}
  for i=1,#pts-1 do
    for j=0,count do
      if i==1 or j>0 then
        local u=j/count
        local p=route.pathType=='Curved' and M.bezier(pts[i],pts[i+1],route.curvature or 0,u) or {
          lon=M.normalize_lon(pts[i].lon+M.shortest_delta(pts[i].lon,pts[i+1].lon)*u),
          lat=pts[i].lat+(pts[i+1].lat-pts[i].lat)*u
        }
        all[#all+1]=p
      end
    end
  end
  return all
end
function M.point_at_progress(route,progress)
  assert(finite(progress) and progress>=0 and progress<=100,'invalid follower progress')
  local pts=M.route_samples(route,64)
  local totals={0};local len=0
  for i=2,#pts do
    local a,b=pts[i-1],pts[i]
    local dx=M.shortest_delta(a.lon,b.lon)/360;local dy=(b.lat-a.lat)/180
    len=len+sqrt(dx*dx+dy*dy)
    totals[i]=len
  end
  if len==0 then return pts[1] end
  local target=len*progress/100
  for i=2,#pts do
    if totals[i]>=target then
      local fraction=(target-totals[i-1])/(totals[i]-totals[i-1])
      return {lon=M.normalize_lon(pts[i-1].lon+M.shortest_delta(pts[i-1].lon,pts[i].lon)*fraction),lat=pts[i-1].lat+(pts[i].lat-pts[i-1].lat)*fraction}
    end
  end
  return pts[#pts]
end
function M.fit(points,width,height,padding)
  assert(type(points)=='table' and #points>0,'no geometry to fit')
  assert(finite(width) and width>0 and finite(height) and height>0,'invalid viewport')
  padding=padding or 8;assert(finite(padding) and padding>=0 and padding<49,'invalid padding')
  local lons={},latmin,latmax
  for _,p in ipairs(points) do
    assert(M.valid_point(p),'invalid fit point')
    lons[#lons+1]=(p.lon+360)%360
    latmin=math.min(latmin or p.lat,p.lat);latmax=math.max(latmax or p.lat,p.lat)
  end
  table.sort(lons)
  local gap=-1;local idx=#lons
  for i=1,#lons do
    local next_lon=lons[(i%#lons)+1]+(i==#lons and 360 or 0)
    if next_lon-lons[i]>gap then gap=next_lon-lons[i];idx=i end
  end
  local start=lons[idx%#lons+1];local span=360-gap
  local mid=M.normalize_lon(start+span/2)
  local spanlat=latmax-latmin
  local pad=1-2*padding/100
  local zoom_x=span>0 and (width/height)*180*pad/span or 50
  local zoom_y=spanlat>0 and 180*pad/spanlat or 50
  return {longitude=mid,latitude=(latmin+latmax)/2,zoom=math.min(50,math.max(0.1,math.min(zoom_x,zoom_y))),bearing=0}
end
return M
