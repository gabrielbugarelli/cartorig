local r=assert(arg[1]);local C=dofile(r..'/src/cartorig/catalog.lua');local J=dofile(r..'/src/cartorig/json.lua')
local data={type='FeatureCollection',features={
 {type='Feature',properties={NAME='Rio de Janeiro',ADM0_A3='BRA',ADMIN='Brazil'},geometry={type='Polygon',coordinates={{{-44,-23},{-42,-23},{-42,-22},{-44,-22}}}}},
 {type='Feature',properties={NAME='Rio de Janeiro',ADM0_A3='BRA',ADMIN='Brazil'},geometry={type='Point',coordinates={-43.2,-22.9}}},
 {type='Feature',properties={NAME='São Paulo',ADM0_A3='BRA',ADMIN='Brazil'},geometry={type='Point',coordinates={-46.63,-23.55}}}
}}
local st=C.from_geojson(data,'State',{dataset='ne-10m-admin1',version='2026',scale='10m'})
local cities=C.from_geojson(data,'City',{dataset='ne-10m-cities',version='2026',scale='10m'})
assert(#st==1 and #cities==2)
local all={st[1],cities[1],cities[2]}
assert(#C.search(all,'Rio de Janeiro','All')==2)
assert(C.search(all,'Sao Paulo','City')[1].name=='São Paulo')
assert(#C.search(all,'São Paulo','State')==0)
assert(st[1].geometryType=='Polygon' and cities[1].geometryType=='Point')
local copy=J.decode(J.encode(data));assert(#C.from_geojson(copy,'City')==2)
assert(not pcall(function()C.from_geojson({type='Wrong',features={}},'Country')end))
print('PASS catalog: GeoJSON ingestion, typed ambiguity, accent-insensitive offline search, source identity')
