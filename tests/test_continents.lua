local root=assert(arg[1]);local Json=dofile(root..'/src/cartorig/json.lua')
local Catalog=dofile(root..'/src/cartorig/catalog.lua')
local doc={type='FeatureCollection',features={}}
local function country(name,continent,x)
  doc.features[#doc.features+1]={type='Feature',properties={NAME=name,CONTINENT=continent},
    geometry={type='Polygon',coordinates={{{x,-10},{x+2,-10},{x+2,-5},{x,-10}}}}}
end
country('Brazil','South America',-50)
country('Chile','South America',-70)
country('France','Europe',2)
local entries=Catalog.from_geojson(doc,'Country',{dataset='admin0',version='test-fixture'})
local groups=Catalog.continent_groups(entries)
assert(#groups==2)
local byname={}
for _,g in ipairs(groups)do
  assert(g.kind=='Continent' and g.geometryType=='Composite' and #g.memberIds>0)
  assert(g.geometry==nil and g.point==nil and g.featureFile==nil)
  byname[g.name]=g
  entries[#entries+1]=g
end
local south=byname['South America']
assert(south and #south.memberIds==2)
local brazil=Catalog.search(entries,'Brasil','Country',5)[1]
assert(brazil)
local found=false
for _,id in ipairs(south.memberIds)do if id==brazil.id then found=true end end
assert(found,'Brazil must belong to its declared Natural Earth continent group')
assert(Catalog.search(entries,'South America','Continent',5)[1].id==south.id)
assert(not Catalog.search(entries,'South America','State',5)[1])
local continent=Catalog.load_feature(root..'/data',south,Json)
assert(continent.geometry==nil and continent.point==nil)
print('PASS continent search: 2 source-derived composites, typed filter, no invented polygons')
