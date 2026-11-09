local root=assert(arg[1]);local C=dofile(root..'/src/cartorig/coordinates.lua')
local x=C.parse(' -47.9000 ',' -15.8000 ')
assert(x.lon==-47.9 and x.lat==-15.8)
assert(C.parse('-180','90').lon==-180)
for _,pair in ipairs({{'181','0'},{'0','-91'},{'NaN','0'},
 {'0;os.execute("X")','0'},{'5,5','0'},{'','0'},{'0',''}}) do
 assert(not pcall(function()C.parse(pair[1],pair[2])end),pair[1])
end
local Scene=dofile(root..'/src/cartorig/scene.lua')
local Geo=dofile(root..'/src/cartorig/geo.lua')
local s=Scene.new('custom-points-0001','bundle-hash')
local feature={id='custom:-47.900000000:-15.800000000',name='Custom Point (-47.90000, -15.80000)',
 geometryType='Point',point=x,type='Custom Point',dataset='User Authored',version='1'}
local a=Scene.add_location(s,feature,'Marker')
local b=Scene.add_location(s,feature,'Label')
assert(a.id~=b.id and a.source.featureId==b.source.featureId)
assert(a.anchor.lon==-47.9 and b.anchor.lat==-15.8)
Scene.validate(s)
assert(Geo.valid_point(x))
local ui=assert(io.open(root..'/fusion/CartoRig Scene.lua','r')):read('*a')
assert(ui:find('CR_CustomFrom',1,true) and ui:find('CR_CustomTo',1,true))
assert(ui:find('engine:add_custom_point',1,true))
print('PASS explicit custom point: coordinates, authored Marker/Label, Route endpoints and unsafe input rejection')
