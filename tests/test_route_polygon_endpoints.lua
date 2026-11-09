local root=assert(arg[1])
local Geo=dofile(root..'/src/cartorig/geo.lua')
local outer={{-52,0},{-49,0},{-49,3},{-52,3},{-52,0}}
local hole={{-51,1},{-50,1},{-50,2},{-51,2},{-51,1}}
local region={type='Polygon',coordinates={outer,hole}}
assert(Geo.contains_geojson({lon=-51.5,lat=1.5},region))
assert(not Geo.contains_geojson({lon=-50.5,lat=1.5},region),'a lake/hole is not an area endpoint')
assert(not Geo.contains_geojson({lon=-53,lat=1.5},region))
local multi={type='MultiPolygon',coordinates={region.coordinates,
  {{{-45,0},{-44,0},{-44,1},{-45,1},{-45,0}}}}}
assert(Geo.contains_geojson({lon=-44.5,lat=0.5},multi),'secondary island must be selectable')
assert(not pcall(function() Geo.contains_geojson({lon=0,lat=0},
 {type='Point',coordinates={0,0}})end))
assert(not pcall(function()Geo.contains_geojson({lon=179,lat=0},
 {type='Polygon',coordinates={{{179,0},{-179,1},{178,2}}}})end),
 'antimeridian seam must fail-closed until true polygon splitting')
local ui=assert(io.open(root..'/fusion/CartoRig Scene.lua','r')):read('*a')
assert(ui:find('routeFromArea',1,true) and ui:find('routeToArea',1,true))
assert(ui:find('Geo.contains_geojson(p,feature.geometry)',1,true))
print('PASS Polygon/MultiPolygon Route endpoint containment, holes, islands, seam-safe rejection')
