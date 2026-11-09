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
-- Persisted styles are untrusted project data and must be validated.
copy=M.snapshot(state)
copy.objects[3].style.opacity=140
assert(not pcall(function()M.validate(copy)end))
copy=M.snapshot(state)
copy.objects[3].style.fill='INVALID'
assert(not pcall(function()M.validate(copy)end))
copy=M.snapshot(state)
copy.objects[3].style={opacity=0/0}
assert(not pcall(function()M.validate(copy)end))
copy=M.snapshot(state)
copy.objects[3].visible='yes'
assert(not pcall(function()M.validate(copy)end))
-- Nested groups inherit lock, not only direct parent lock.
copy=M.snapshot(state)
local pa=M.add_group(copy,'Parent Group')
local child=M.add_group(copy,'Child Group')
child.groupId=pa.id
local obj=M.get(copy,marker.id)
obj.groupId=child.id
M.set_lock(copy,pa.id,true)
assert(not pcall(function()M.set_style(copy,marker.id,'fill','#FFFFFF')end))
M.set_lock(copy,pa.id,false)
M.set_style(copy,marker.id,'fill','#FFFFFF')
assert(M.validate(copy))
-- Duplicate is only a model draft: must not alias host node references.
obj.hostToolRef='CR2_Marker_original'
obj.maskToolRef='CR2_Mask_original'
obj.compositeToolRef='CR2_Composite_original'
local dup=M.duplicate(copy,marker.id)
assert(dup.hostToolRef==nil and dup.maskToolRef==nil and dup.compositeToolRef==nil)
assert(dup.style.fill==obj.style.fill and dup.id~=obj.id)
assert(M.validate(copy))
print('PASS integrity: invalid follower, group cycle, invalid Motion binding, missing frame')
