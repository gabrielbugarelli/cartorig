local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua');local Motion=dofile(root..'/src/cartorig/motion.lua')
local scene=Scene.new('motion-edges-001')
local pin=Scene.add_location(scene,{id='c',name='City',type='City',point={lon=10,lat=20}},'Marker')
local opts={start=10,frameCount=100,duration=1}
assert(not pcall(function()Motion.prepare(pin,'MO-MRK-02',opts,{})end), 'Pop requires three distinct frames')
opts.duration=2
local plan=Motion.prepare(pin,'MO-MRK-02',opts,{})
assert(#plan.channels.size==3)
assert(plan.channels.size[1].frame==10 and plan.channels.size[2].frame==11 and plan.channels.size[3].frame==12)
-- No native writer should need to repair duplicate key times returned by the planner.
for _,d in pairs(Motion.definitions)do
  if d.kind=='Marker' then
    local x={start=10,frameCount=100,duration=2}
    local ok,prepared=pcall(function()return Motion.prepare(pin,d==Motion.definitions['MO-MRK-02'] and 'MO-MRK-02' or 'MO-MRK-01',x,{})end)
    assert(ok and prepared)
    for _,keys in pairs(prepared.channels)do
      local prev=-1
      for _,k in ipairs(keys)do assert(k.frame>prev);prev=k.frame end
    end
  end
end
print('PASS Motion planner: Pop 3-key minimum duration and strictly increasing frame indices')
