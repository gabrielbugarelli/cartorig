-- CartoRig managed graph operations. No operation may alter a foreign node.
-- Inspect the live Fusion connections BEFORE touching the managed graph.
local G={}
local function fail(message) error('CartoRig graph: '..message,2) end
local function tool_name(tool)
  local attrs=tool:GetAttrs() or {}
  return attrs.TOOLS_Name or tool.Name
end
local function own(tool,scene,id,kind)
  return tool and tool:GetData('CartoRig.V2.Owned')==true
    and tool:GetData('CartoRig.V2.SceneId')==scene.id
    and tool:GetData('CartoRig.V2.ObjectId')==id
    and (not kind or tool:GetData('CartoRig.V2.Kind')==kind)
end
local function find_owned(comp,scene,id,kind)
  local found=nil
  for _,tool in pairs(comp:GetToolList(false) or {}) do
    if own(tool,scene,id,kind) then
      if found then fail('ambiguous managed tool for '..tostring(id)) end
      found=tool
    end
  end
  if not found then fail('missing managed tool for '..tostring(id)) end
  return found
end
local function connected_tool(node,inputName)
  if type(node.GetInputList)~='function' then fail('Fusion input inspection is unavailable') end
  local ok,inputs=pcall(function()return node:GetInputList()end)
  if not ok or type(inputs)~='table' then fail('Fusion input list is unavailable') end
  local input=inputs[inputName]
  if not input or type(input.GetConnectedOutput)~='function' then
    fail('Fusion cannot inspect '..tostring(inputName)..' on '..tostring(tool_name(node)))
  end
  local success,output=pcall(function()return input:GetConnectedOutput()end)
  if not success then fail('Fusion failed to inspect '..tostring(inputName)) end
  if not output then return nil end
  if type(output.GetTool)~='function' then fail('connected Fusion output has no owning tool') end
  local valid,source=pcall(function()return output:GetTool()end)
  if not valid or not source then fail('connected Fusion source could not be resolved') end
  return source
end
local function connect(node,input,source)
  local ok,result=pcall(function()return node:ConnectInput(input,source)end)
  if not ok or result==false then
    fail('Fusion refused to reconnect '..tostring(input)..' on '..tostring(tool_name(node)))
  end
end
local function ordered(scene)
  local list={}
  for _,object in ipairs(scene.objects or {}) do
    if object.kind~='BaseMap' and object.kind~='Camera' and object.kind~='Group' then
      if not object.compositeToolRef then fail('object has no composite: '..tostring(object.id)) end
      list[#list+1]=object
    end
  end
  return list
end
-- Reorder the SAME visual objects in the SAME composition, never creating or
-- removing tools. Group folders do not contribute layers. This is an atomic
-- reconnection of CartoRig-owned Merge.Background and Camera.Input sockets.
function G.reorder(host,before,after)
  if not host or not host.comp or not before or not after or before.id~=after.id then
    fail('scene/host identity mismatch')
  end
  if not before.hostInitialized or not after.hostInitialized then fail('scene not initialized') end
  local original,desired=ordered(before),ordered(after)
  if #original~=#desired then fail('reorder cannot add or remove visual objects') end
  local comp=host.comp
  local camera=find_owned(comp,before,before.objects[2].id,'Camera')
  local base=find_owned(comp,before,before.objects[1].id,'BaseMap')
  local tools,ids={},{}
  for _,obj in ipairs(original) do
    if ids[obj.id] then fail('duplicate visual ID') end
    ids[obj.id]=true
    tools[obj.id]=find_owned(comp,before,obj.id,'InternalComposite')
  end
  for _,obj in ipairs(desired) do
    if not ids[obj.id] then fail('object identity changed during reorder') end
    ids[obj.id]=nil
  end
  for id in pairs(ids) do fail('missing object after reorder: '..tostring(id)) end
  -- Fail closed on manual rewiring or foreign tools spliced into the chain.
  local upstream=base
  for _,obj in ipairs(original) do
    local node=tools[obj.id]
    if connected_tool(node,'Background')~=upstream then
      fail('managed draw chain has been modified externally; no nodes changed')
    end
    upstream=node
  end
  if connected_tool(camera,'Input')~=upstream then
    fail('camera input is not the managed final layer; no nodes changed')
  end
  if #original==0 then return false end
  local same=true
  for i,obj in ipairs(desired) do if obj.id~=original[i].id then same=false;break end end
  if same then return false end
  local backup={}
  for _,obj in ipairs(original) do backup[#backup+1]={tools[obj.id],'Background',connected_tool(tools[obj.id],'Background')} end
  backup[#backup+1]={camera,'Input',connected_tool(camera,'Input')}
  local started=false
  if comp.StartUndo then comp:StartUndo('CartoRig: reorder layers');started=true end
  local ok,err=xpcall(function()
    -- Disconnect first: connecting in place could form a temporary feedback loop.
    connect(camera,'Input',nil)
    for _,obj in ipairs(original) do connect(tools[obj.id],'Background',nil) end
    local source=base
    for _,obj in ipairs(desired) do
      local node=tools[obj.id]
      connect(node,'Background',source)
      source=node
    end
    connect(camera,'Input',source)
  end,debug.traceback)
  if not ok then
    -- Re-establish the exact original chain, again disconnecting first.
    local recovered=pcall(function()
      connect(camera,'Input',nil)
      for _,obj in ipairs(original) do connect(tools[obj.id],'Background',nil) end
      for _,item in ipairs(backup) do connect(item[1],item[2],item[3]) end
    end)
    if started and comp.EndUndo then pcall(function()comp:EndUndo(false)end) end
    if not recovered then fail('graph rollback failed; stop editing and use a saved project copy: '..tostring(err)) end
    fail('reorder rolled back: '..tostring(err))
  end
  if started and comp.EndUndo then comp:EndUndo(true) end
  after.lastLayerRef=tool_name(tools[desired[#desired].id])
  return true
end
return G
