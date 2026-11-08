-- CartoRig: deterministic Motion planning. Produces keys, never renders or mutates Fusion itself.
-- The Fusion host is the source of truth once a plan is applied.
local M = {}
local definitions={
  ['MO-REG-01']={kind='Region',name='Fade In',channels={'opacity'},duration=24},
  ['MO-REG-02']={kind='Region',name='Fade Out',channels={'opacity'},duration=24},
  ['MO-REG-03']={kind='Region',name='Color Transition',channels={'fill'},duration=24},
  ['MO-REG-04']={kind='Region',name='Instant Color Change',channels={'fill'},duration=0},
  ['MO-REG-05']={kind='Region',name='Border Draw',channels={'strokeProgress'},duration=36},
  ['MO-REG-06']={kind='Region',name='Highlight Pulse',channels={'highlightStrength'},duration=36},
  ['MO-RTE-01']={kind='Route',name='Draw Path',channels={'drawProgress'},duration=30},
  ['MO-RTE-02']={kind='Route',name='Erase Path',channels={'drawProgress'},duration=30},
  ['MO-RTE-03']={kind='Route',name='Follow Path',channels={'followerProgress'},duration=60},
  ['MO-MRK-01']={kind='Marker',name='Fade In',channels={'opacity'},duration=18},
  ['MO-MRK-02']={kind='Marker',name='Pop In',channels={'size'},duration=18},
  ['MO-CAM-01']={kind='Camera',name='Fly To Location',channels={'longitude','latitude','zoom'},duration=45},
  ['MO-CAM-02']={kind='Camera',name='Zoom To',channels={'zoom'},duration=30},
  ['MO-CAM-03']={kind='Camera',name='Fit Transition',channels={'longitude','latitude','zoom'},duration=45},
  ['MO-LBL-01']={kind='Label',name='Fade In',channels={'opacity'},duration=18},
  ['MO-MAP-01']={kind='BaseMap',name='Layer Fade',channels={'layerOpacity'},duration=18},
}
M.definitions=definitions
local function fail(s) error('CartoRig motion: '..s,2) end
local function key(at,value,interpolation) return {frame=at,value=value,interpolation=interpolation or 'Bezier'} end
local function plan_channel(channels,name,keys) channels[name]=keys end
local function value_or(target,key,default) local v=target[key];if v==nil then return default end;return v end
local function valid_integer(x) return type(x)=='number' and x%1==0 and x==x end
local function validate_frame(start,duration,frameCount)
  if not valid_integer(start) or start<0 then fail('invalid playhead frame') end
  if not valid_integer(duration) or duration<0 then fail('invalid duration') end
  if not valid_integer(frameCount) or frameCount<1 or start+duration>=frameCount then fail('keys extend beyond composition') end
end
local function check_conflicts(channels,existing)
  existing=existing or {}
  for channel in pairs(channels) do
    if existing[channel] and #existing[channel]>0 then fail('CONFLICT: '..channel..' already contains animation') end
  end
end
function M.prepare(object,preset_id,opts,existing)
  opts=opts or {}
  local d=definitions[preset_id]
  if not d then fail('unknown preset '..tostring(preset_id)) end
  if not object or object.kind~=d.kind then fail('preset does not apply to selected object') end
  if object.locked then fail('object locked') end
  local start=opts.start
  local delay=opts.delay or 0
  if not valid_integer(delay) or delay<0 then fail('invalid delay') end
  local duration=opts.duration or d.duration
  if preset_id=='MO-REG-04' then duration=0 end
  local first=start+delay
  validate_frame(first,duration,opts.frameCount)
  local last=first+duration
  local channels={}
  local ease=opts.easing or 'Bezier'
  local function ramp(name,a,b) plan_channel(channels,name,{key(first,a,ease),key(last,b,ease)}) end
  if preset_id=='MO-REG-01' or preset_id=='MO-MRK-01' or preset_id=='MO-LBL-01' then
    ramp('opacity',0,value_or(opts,'targetOpacity',object.style.opacity or 100))
  elseif preset_id=='MO-REG-02' then
    ramp('opacity',value_or(opts,'sourceOpacity',object.style.opacity or 100),0)
  elseif preset_id=='MO-REG-03' then
    if not opts.targetColor or not opts.targetColor:match('^#%x%x%x%x%x%x$') then fail('targetColor required') end
    ramp('fill',object.style.fill,opts.targetColor)
  elseif preset_id=='MO-REG-04' then
    if not opts.targetColor or not opts.targetColor:match('^#%x%x%x%x%x%x$') then fail('targetColor required') end
    local keys={}
    if first>0 then keys[#keys+1]=key(first-1,object.style.fill,'Step') end
    keys[#keys+1]=key(first,opts.targetColor,'Step')
    plan_channel(channels,'fill',keys)
  elseif preset_id=='MO-REG-05' then ramp('strokeProgress',0,100)
  elseif preset_id=='MO-REG-06' then
    local count=opts.pulseCount or 2
    local cycle=opts.cycle or 18
    if not valid_integer(count) or count<1 or count>8 or not valid_integer(cycle) or cycle<2 then fail('invalid pulse parameters') end
    duration=count*cycle;validate_frame(first,duration,opts.frameCount);last=first+duration
    local keys={}
    for i=0,count-1 do
      keys[#keys+1]=key(first+i*cycle,0)
      keys[#keys+1]=key(first+i*cycle+math.floor(cycle/2),opts.peak or 35)
    end
    keys[#keys+1]=key(last,0)
    plan_channel(channels,'highlightStrength',keys)
  elseif preset_id=='MO-RTE-01' then ramp('drawProgress',0,100)
  elseif preset_id=='MO-RTE-02' then ramp('drawProgress',100,0)
  elseif preset_id=='MO-RTE-03' then
    if not object.route or not object.route.followerId then fail('Follow Path requires an existing linked marker') end
    ramp('followerProgress',0,100)
  elseif preset_id=='MO-MRK-02' then
    local size=object.style.size
    plan_channel(channels,'size',{key(first,0),key(first+math.floor(duration*0.7),size*1.15),key(last,size)})
  elseif preset_id=='MO-CAM-01' or preset_id=='MO-CAM-03' then
    local endpose=opts.targetPose
    if not endpose or type(endpose.longitude)~='number' or type(endpose.latitude)~='number' or type(endpose.zoom)~='number' then fail('targetPose required') end
    for _,name in ipairs({'longitude','latitude','zoom'}) do ramp(name,object.style[name],endpose[name]) end
  elseif preset_id=='MO-CAM-02' then
    if type(opts.targetZoom)~='number' or opts.targetZoom<=0 then fail('targetZoom required') end
    ramp('zoom',object.style.zoom,opts.targetZoom)
  elseif preset_id=='MO-MAP-01' then
    if not opts.layer then fail('base layer required') end
    ramp('layerOpacity',0,100)
  else fail('preset implementation missing') end
  check_conflicts(channels,existing)
  return {presetId=preset_id,objectId=object.id,channels=channels,first=first,last=last,
    duration=duration,state='ANIMATED_PRESET',layer=opts.layer}
end
function M.mark_custom(binding,host_fingerprint)
  if not binding then fail('binding required') end
  if host_fingerprint~=binding.originalFingerprint then binding.state='PRESET_CUSTOMIZED' end
  return binding.state
end
return M
