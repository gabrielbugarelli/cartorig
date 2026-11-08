-- Round-trip Scene metadata inside the Fusion Composition; UTF-8 JSON is non-executable.
-- Rendering must not depend on the UI Manager or external database process.
local M={}
local KEY='CartoRig.V2.SceneJson'
local function fail(s)error('CartoRig repository: '..s,2)end
function M.read(comp,scene,json)
  if not comp or type(comp.GetData)~='function' then fail('Composition.GetData unavailable') end
  local raw=comp:GetData(KEY)
  if raw==nil or raw=='' then return nil end
  if type(raw)~='string' then fail('unexpected scene storage') end
  local ok,data=pcall(json.decode,raw)
  if not ok or type(data)~='table' then fail('stored scene JSON is damaged') end
  scene.validate(data)
  return data
end
function M.write(comp,state,scene,json)
  if not comp or type(comp.SetData)~='function' then fail('Composition.SetData unavailable') end
  scene.validate(state)
  local jsonString=json.encode(state)
  local ok,result=pcall(function()return comp:SetData(KEY,jsonString)end)
  if not ok or result==false then fail('host refused persistent scene state') end
  return jsonString
end
function M.update(comp,scene,json,mutator)
  local previous=M.read(comp,scene,json)
  if not previous then fail('no CartoRig scene in this Composition') end
  local next=scene.snapshot(previous)
  local result=mutator(next)
  scene.validate(next)
  M.write(comp,next,scene,json)
  return next,result
end
function M.schema()return KEY end
return M
