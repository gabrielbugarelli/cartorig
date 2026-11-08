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
local function normalized_pose(pose)
  if not finite(pose.longitude) or not finite(pose.latitude) or not finite(pose.zoom) or pose.zoom<=0 or pose.zoom>50 then fail('invalid camera pose') end
  -- The Fusion Transform Center controls the position of the centre of the source world image.
  -- World point x=(lon+180)/360, y=(lat+90)/180 must land at 0.5/0.5 after scaling.
  local x=(pose.longitude+180)/360
  local y=(pose.latitude+90)/180
  return {0.5-(x-0.5)*pose.zoom,0.5-(y-0.5)*pose.zoom}
end
local channelMap={
  Region={opacity={tool='object',input='TopLeftAlpha',percent=true},fill={tool='object',color={'TopLeftRed','TopLeftGreen','TopLeftBlue'}}},
  Marker={opacity={tool='object',input='TopLeftAlpha',percent=true},size={tool='mask',inputs={'Width','Height'},scale=1/1080}},
  Label={opacity={tool='object',input='Alpha1',percent=true}},
  Route={opacity={tool='object',input='TopLeftAlpha',percent=true},drawProgress={tool='mask',input='WriteLength',percent=true}},
  Camera={zoom={tool='object',input='Size'},longitude={tool='object',camera=true},latitude={tool='object',camera=true}},
  BaseMap={opacity={tool='object',input='TopLeftAlpha',percent=true}},
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
  local cameraCenter=nil
  if object.kind=='Camera' and (plan.channels.longitude or plan.channels.latitude) then
    -- Camera Center is a single 2D native input; it must be composed from both geographic channels.
    local lon=plan.channels.longitude
    local lat=plan.channels.latitude
    if not lon or not lat or #lon~=#lat then fail('camera Center requires synchronized longitude and latitude keys') end
    for i=1,#lon do
      if lon[i].frame~=lat[i].frame then fail('camera Center keys are not synchronized') end
    end
    local zoom=plan.channels.zoom
    if not zoom or #zoom~=#lon then fail('camera Center requires paired Zoom keys') end
    cameraCenter={}
    for i=1,#lon do
      if zoom[i].frame~=lon[i].frame then fail('camera Zoom and Center keys must be synchronized') end
      cameraCenter[#cameraCenter+1]={frame=lon[i].frame,value=normalized_pose({longitude=lon[i].value,latitude=lat[i].value,zoom=zoom[i].value})}
    end
  end
  -- Special native pairing: a Camera that changes only Zoom can use the Size input directly.
  -- Longer term, a shared geometry Fuse will own lon/lat independently in the Inspector.
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
      elseif not spec.camera then
        for _,key in ipairs(row.keys) do
          set_key(tool,spec.input,key.value*(spec.percent and 0.01 or 1),key.frame)
        end
      end
    end
    if cameraCenter then
      local tool=active_tool(host,object,{tool='object'})
      ensure_spline(tool,'Center',true)
      for _,k in ipairs(cameraCenter) do
        local result=tool:SetInput('Center',k.value,k.frame)
        if result==false then fail('Fusion rejected camera Center key') end
      end
    end
    local tool=host:tool_for(object)
    if tool then
      tool:SetData('CartoRig.V2.MotionPresetId',plan.presetId)
      tool:SetData('CartoRig.V2.MotionLastFrame',plan.last)
    end
  end,debug.traceback)
  if started and comp.EndUndo then comp:EndUndo(ok) end
  if not ok then fail('native keyframe write failed: '..tostring(err)) end
  return true
end
return M
