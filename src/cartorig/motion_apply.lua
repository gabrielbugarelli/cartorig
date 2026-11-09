-- Native Fusion Motion writer for a deliberately bounded, testable channel set.
-- Unsupported rendering channels FAIL instead of silently reporting a working preset.
-- Only Fusion parameters hold time-varying pixel values; plans are ephemeral instructions.
local M={}
local function fail(s) error('CartoRig motion host: '..s,2) end
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function rgb(value)
  if type(value)~='string' or not value:match('^#%x%x%x%x%x%x$') then fail('invalid color key') end
  return {tonumber(value:sub(2,3),16)/255,tonumber(value:sub(4,5),16)/255,tonumber(value:sub(6,7),16)/255}
end
local channelMap={
  Region={opacity={tool='object',input='ObjectOpacity',percent=true},fill={tool='object',color={'FillRed','FillGreen','FillBlue'}},highlightStrength={tool='object',input='HighlightStrength',percent=true}},
  Marker={opacity={tool='object',input='ObjectOpacity',percent=true},size={tool='mask',inputs={'Width','Height'},scale=1/1080}},
  Label={opacity={tool='object',input='ObjectOpacity',percent=true}},
  Route={opacity={tool='object',input='ObjectOpacity',percent=true},drawProgress={tool='mask',input='WriteLength',percent=true}},
  Camera={zoom={tool='object',input='Zoom'},longitude={tool='object',input='CenterLongitude'},latitude={tool='object',input='CenterLatitude'},bearing={tool='object',input='Bearing'}},
  BaseMap={['layerOpacity.Ocean']={tool='object',input='OceanLayerOpacity',percent=true}},
}
M.supported_channels=channelMap
local function active_tool(host,object,spec)
  if spec.tool=='mask' then
    if not object.maskToolRef then fail('object mask tool missing') end
    local t=host.comp:FindTool(object.maskToolRef)
    if not t or t:GetData('CartoRig.V2.ObjectId')~=object.id then fail('mask ownership check failed') end
    return t
  end
  local t=host:tool_for(object)
  if not t then fail('object not linked to live Fusion tool') end
  return t
end
local function channel_inputs(spec)
  if spec.color then return spec.color end
  if spec.inputs then return spec.inputs end
  return {spec.input}
end
local function ensure_spline(tool,input,is_point)
  if not tool:GetData('CartoRig.V2.Animated.'..input) then
    local method=is_point and 'XYPath' or 'BezierSpline'
    local ok,result=pcall(function() return tool:AddModifier(input,method) end)
    if not ok or result==false then fail('Fusion refused '..method..' on '..input) end
    tool:SetData('CartoRig.V2.Animated.'..input,true)
  end
end
local function set_key(tool,input,value,frame)
  ensure_spline(tool,input,false)
  local ok,success=pcall(function()return tool:SetInput(input,value,frame)end)
  if not ok or success==false then fail('Fusion refused keyframe at '..tostring(frame)..' on '..input) end
end
local function native_keys_exist(tool,input)
  if tool:GetData('CartoRig.V2.Animated.'..input)==true then return true end
  if type(tool.GetInputList)~='function' then return false end
  local ok,fields=pcall(function()return tool:GetInputList()end)
  if not ok or type(fields)~='table' then return false end
  local field=fields[input]
  if field and type(field.GetKeyFrames)=='function' then
    local success,keys=pcall(function()return field:GetKeyFrames()end)
    if not success then fail('could not inspect existing Fusion keyframes on '..input) end
    if type(keys)=='table' and next(keys)~=nil then return true end
  end
  return false
end
local function preflight(host,object,plan)
  if type(plan)~='table' or plan.objectId~=object.id or type(plan.channels)~='table' then fail('plan does not match selected object') end
  local mapped=channelMap[object.kind]
  if not mapped then fail('object type is not supported by native Motion writer') end
  local staged={}
  for channel,keys in pairs(plan.channels) do
    local spec=mapped[channel]
    if not spec then fail('native renderer has no editable '..channel..' channel for '..object.kind..' yet') end
    local tool=active_tool(host,object,spec)
    if type(tool.AddModifier)~='function' then fail('Fusion keyframe API not available') end
    -- Do not trust only CartoRig scene metadata: Fusion may have hand-edited
    -- curves which were never registered by the Scene window.
    for _,input in ipairs(channel_inputs(spec)) do
      if native_keys_exist(tool,input) then
        fail('CONFLICT: Fusion channel '..input..' already has animation; preserve manual keys')
      end
    end
    if type(keys)~='table' or #keys==0 then fail('empty channel') end
    local last=-1
    for _,key in ipairs(keys) do
      if not finite(key.frame) or key.frame%1~=0 or key.frame<0 or key.frame<=last then fail('keyframes must be strictly increasing whole frames') end
      last=key.frame
      if spec.color then rgb(key.value) elseif not finite(key.value) then fail('nonfinite key value') end
    end
    staged[#staged+1]={channel=channel,tool=tool,spec=spec,keys=keys}
  end
  return staged
end
function M.apply(host,object,plan)
  if not host or not object or object.locked then fail('invalid or locked object') end
  -- Fail before creating ANY splines if a planned channel has no real native counterpart.
  local staged=preflight(host,object,plan)
  -- Camera now exposes canonical geographic parameters as native Fusion
  -- channels. The Camera Fuse projects these values at EVERY requested frame,
  -- avoiding independent Transform.Center/Size interpolation drift.
  local comp=host.comp
  local started=false
  if comp.StartUndo then comp:StartUndo('CartoRig: '..tostring(plan.presetId));started=true end
  local ok,err=xpcall(function()
    for _,row in ipairs(staged) do
      local spec,tool=row.spec,row.tool
      if spec.color then
        for _,key in ipairs(row.keys) do
          local values=rgb(key.value)
          for n,input in ipairs(spec.color) do set_key(tool,input,values[n],key.frame) end
        end
      elseif spec.inputs then
        for _,key in ipairs(row.keys) do
          for _,input in ipairs(spec.inputs) do set_key(tool,input,key.value*(spec.scale or 1),key.frame) end
        end
      else
        for _,key in ipairs(row.keys) do
          set_key(tool,spec.input,key.value*(spec.percent and 0.01 or 1),key.frame)
        end
      end
    end
    local tool=host:tool_for(object)
    if tool then
      tool:SetData('CartoRig.V2.MotionPresetId',plan.presetId)
      tool:SetData('CartoRig.V2.MotionLastFrame',plan.last)
    end
  end,debug.traceback)
  if started and comp.EndUndo then comp:EndUndo(ok) end
  if not ok then
    local tool=host:tool_for(object)
    if tool then pcall(function()tool:SetData('CartoRig.V2.MotionNeedsRepair',true)end)end
    fail('native keyframe write failed; inspect Undo and keyframes: '..tostring(err))
  end
  return true
end
return M
