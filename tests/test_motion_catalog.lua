local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua');local Motion=dofile(root..'/src/cartorig/motion.lua')
local s=Scene.new('scene-motion-catalog-01')
local objects={BaseMap=s.objects[1],Camera=s.objects[2]}
objects.Region=Scene.add_location(s,{id='ne-br',name='Brazil',type='Country',geometryType='Polygon'},'Region')
objects.Marker=Scene.add_location(s,{id='city-br',name='Brasília',type='City',point={lon=-47.9,lat=-15.8}},'Marker')
objects.Label=Scene.add_location(s,{id='city-sp',name='São Paulo',type='City',point={lon=-46.63,lat=-23.55}},'Label')
objects.Route=Scene.add_route(s,{lon=-47.9,lat=-15.8},{lon=-51.2,lat=0.1})
objects.Route.route.followerId=objects.Marker.id
local opts={frameCount=900,start=100,targetColor='#00FF00',targetZoom=4,
  targetPose={longitude=-179,latitude=1,zoom=5},layer='Land'}
local count=0
for id,d in pairs(Motion.definitions) do
  local obj=objects[d.kind]
  assert(obj,'missing fixture '..d.kind)
  local plan=Motion.prepare(obj,id,opts,{})
  assert(plan.objectId==obj.id and plan.presetId==id and plan.last<900)
  assert(next(plan.channels),'preset created no editable curve')
  for name,keys in pairs(plan.channels) do
    assert(#keys>0,'empty curve '..name)
    local prev=-1
    for _,k in ipairs(keys)do
      assert(type(k.frame)=='number' and k.frame>=0 and k.frame<900)
      assert(k.frame>=prev,'unsorted keys '..id)
      prev=k.frame
    end
  end
  count=count+1
end
assert(count==16)
local cam=Motion.prepare(objects.Camera,'MO-CAM-01',{frameCount=900,start=0,
  targetPose={longitude=-179,latitude=0,zoom=2}}, {})
assert(cam.channels.longitude[2].value==-179,'initial camera 0 should travel to -179')
objects.Camera.style.longitude=179
local wrapped=Motion.prepare(objects.Camera,'MO-CAM-01',{frameCount=900,start=0,
  targetPose={longitude=-179,latitude=0,zoom=2}}, {})
assert(wrapped.channels.longitude[2].value==181,'camera must interpolate shortest dateline arc')
assert(not pcall(function()Motion.prepare(objects.Region,'MO-REG-01',{start=100,frameCount=900,duration=0},{}) end))
assert(not pcall(function()Motion.prepare(objects.Region,'MO-REG-06',{start=100,frameCount=900,peak=1000},{}) end))
assert(not pcall(function()Motion.prepare(objects.Camera,'MO-CAM-02',{start=100,frameCount=900,targetZoom=math.huge},{}) end))
local ocean=Motion.prepare(objects.BaseMap,'MO-MAP-01',{start=10,frameCount=900,layer='Ocean'}, {})
assert(ocean.channels['layerOpacity.Ocean'])
local land=Motion.prepare(objects.BaseMap,'MO-MAP-01',{start=10,frameCount=900,layer='Land'}, ocean.channels)
assert(land.channels['layerOpacity.Land'],'separate basemap layers must have independent animation')
print('PASS motion catalog: 16 plans, required channels, bounds, shortest camera path, independent base layers')
