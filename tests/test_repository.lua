local root=assert(arg[1]);local S=dofile(root..'/src/cartorig/scene.lua')
local J=dofile(root..'/src/cartorig/json.lua');local R=dofile(root..'/src/cartorig/repository.lua')
local storage={}
local host={GetData=function(_,k)return storage[k]end,SetData=function(_,k,v)storage[k]=v;return true end}
local s=S.new('scene-repository-0001','ne-110m-preview')
R.write(host,s,S,J)
assert(R.read(host,S,J).id==s.id)
local next,item=R.update(host,S,J,function(d)
  return S.add_location(d,{id='city:sp',name='São Paulo',type='City',point={lon=-46.63,lat=-23.55}},'Marker')
end)
assert(item.id and #R.read(host,S,J).objects==3)
local before=storage[R.schema()]
assert(not pcall(function()R.update(host,S,J,function(d)
  S.add_location(d,{id='invalid',name='Invalid',type='City'},'Region')
end)end))
assert(storage[R.schema()]==before,'failed edit must not corrupt stored data')
storage[R.schema()]='{"schema":"incorrect"}'
assert(not pcall(function()R.read(host,S,J)end))
print('PASS repository: save/reopen, UTF-8 JSON, isolated atomic edit, corruption detection')
