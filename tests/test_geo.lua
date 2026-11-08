local root=assert(arg[1]); local g=dofile(root..'/src/cartorig/geo.lua')
local function near(a,b,e) assert(math.abs(a-b)<(e or 0.001),tostring(a)..' != '..tostring(b)) end
assert(g.valid_point({lon=-47.92,lat=-15.78}))
assert(not g.valid_point({lon=181,lat=10}))
assert(g.shortest_delta(179,-179)==2)
assert(g.shortest_delta(-179,179)==-2)
local xy=g.project({lon=0,lat=0});near(xy.x,0.5);near(xy.y,0.5)
local pt=g.unproject(0.5,0.5);near(pt.lon,0);near(pt.lat,0)
local screen=g.screen({lon=0,lat=0},{longitude=0,latitude=0,zoom=1},1920,1080)
near(screen.x,960);near(screen.y,540)
local cut=g.split_antimeridian({{lon=179,lat=0},{lon=-179,lat=4}})
assert(#cut==2);near(cut[1][2].lon,180);near(cut[2][1].lon,-180);near(cut[1][2].lat,2)
local ring={{lon=0,lat=0},{lon=10,lat=0},{lon=10,lat=10},{lon=0,lat=10}}
local hole={{lon=4,lat=4},{lon=6,lat=4},{lon=6,lat=6},{lon=4,lat=6}}
assert(g.contains({lon=2,lat=2},{ring,hole}))
assert(not g.contains({lon=5,lat=5},{ring,hole}))
local route={from={lon=-47,lat=-15},to={lon=-52,lat=0},pathType='Curved',curvature=30}
local start=g.point_at_progress(route,0);local finish=g.point_at_progress(route,100)
near(start.lon,route.from.lon);near(finish.lon,route.to.lon)
local focus=g.fit({{lon=179,lat=0},{lon=-179,lat=2}},1920,1080,8)
assert(math.abs(math.abs(focus.longitude)-180)<0.01,focus.longitude)
print('PASS geo: equirectangular projection, dateline seam, polygon holes, routes, camera fit')
