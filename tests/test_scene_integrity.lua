local root=assert(arg[1]);local M=dofile(root..'/src/cartorig/scene.lua');local Motion=dofile(root..'/src/cartorig/motion.lua')
local state=M.new('integrity-scene-2026')
local city={id='NE:city:1',name='Cidade',type='City',point={lon=-43.2,lat=-22.9}}
local marker=M.add_location(state,city,'Marker')
local route=M.add_route(state,{lon=-47,lat=-15},{lon=-51,lat=1})
assert(M.validate(state))
local copy=M.snapshot(state)
copy.objects[4].route.followerId='unknown'
assert(not pcall(function()M.validate(copy)end))
copy=M.snapshot(state)
copy.objects[4].route.followerId=marker.id
assert(M.validate(copy))
local group=M.add_group(copy,'Group A')
local group2=M.add_group(copy,'Group B')
group.groupId=group2.id;group2.groupId=group.id
assert(not pcall(function()M.validate(copy)end))
copy=M.snapshot(state);copy.objects[3].motion.fill='not a table'
assert(not pcall(function()M.validate(copy)end))
assert(not pcall(function()Motion.prepare(marker,'MO-MRK-01',{frameCount=900})end))
assert(M.validate(state))
print('PASS integrity: invalid follower, group cycle, invalid Motion binding, missing frame')
