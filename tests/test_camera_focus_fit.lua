-- Camera Scene actions mutate native Fusion Control fields transactionally.
local root=assert(arg[1])
local function load(n)return dofile(root..'/src/cartorig/'..n..'.lua')end
local m={Scene=load('scene'),Repository=load('repository'),Json=load('json'),
  Host=load('fusion_host'),Objects=load('fusion_objects'),Geo=load('geo'),
  Motion=load('motion'),Writer=load('motion_apply'),GraphOps=load('graph_ops'),SceneOps=load('scene_ops')}
local Author=load('authoring')
local comp={nodes={},data={},fail_store=false,reject_input=nil,prefs={
 ['Comp.FrameFormat.Width']=2560,['Comp.FrameFormat.Height']=1440}}
local T={};T.__index=T
function T:SetAttrs(a)self.Name=a.TOOLS_Name end
function T:GetAttrs()return{TOOLS_RegID=self.ID,TOOLS_Name=self.Name}end
function T:SetData(k,v)self.data[k]=v end
function T:GetData(k)return self.data[k]end
function T:SetInput(k,v,t)
  if comp.reject_input==k then return false end
  self.inputs[k]=self.inputs[k]or{};self.inputs[k][t or 'static']=v;return true
end
function T:GetInput(k,t)return self.inputs[k]and self.inputs[k][t or 'static']end
function T:ConnectInput(k,src)self.links[k]=src;return true end
function T:Delete()self.deleted=true end
function comp:AddTool(kind)
  local node=setmetatable({ID=kind,Name=kind..#self.nodes,data={},inputs={},links={}},T)
  self.nodes[#self.nodes+1]=node;return node
end
function comp:FindTool(name)
  for _,tool in ipairs(self.nodes)do if not tool.deleted and tool.Name==name then return tool end end
end
function comp:GetToolList()return self.nodes end
function comp:GetData(k)return self.data[k]end
function comp:SetData(k,v)if self.fail_store then error('storage failure')end;self.data[k]=v end
function comp:StartUndo()end
function comp:EndUndo()end
function comp:GetPrefs(key)return self.prefs[key]end
local out=comp:AddTool('MediaOut')
local engine=Author.new(comp,m,{readstring=function(src)return src end},'fixed-natural-earth-bundle')
local scene=engine:initialize('focus-fit-camera-scene','fixed-natural-earth-bundle')
local cameraId=scene.objects[2].id
local camera=engine.host:tool_for(scene.objects[2])
assert(camera and camera:GetInput('CenterLongitude')==0)
local w,h=engine.host:viewport()
assert(w==2560 and h==1440)
local sao={lon=-46.63,lat=-23.55}
local updated=engine:focus_camera(sao)
assert(updated.objects[2].style.longitude==sao.lon)
assert(updated.objects[2].style.latitude==sao.lat)
assert(updated.objects[2].style.zoom==1)
assert(camera:GetInput('CenterLongitude')==sao.lon)
assert(camera:GetInput('CenterLatitude')==sao.lat)
assert(camera:GetInput('Zoom')==1)
assert(camera:GetData('CartoRig.V2.Animated.CenterLatitude')==nil)
-- Changing center in Focus may never create an automatic animation key.
local polygon={name='Geographic target',kind='Country',geometryType='Polygon',
 geometry={type='Polygon',coordinates={{{-60,-22},{-40,-22},{-40,-2},{-60,-2},{-60,-22}}}}}
local expected=m.Geo.fit({{lon=-60,lat=-22},{lon=-40,lat=-2}},w,h,8)
local fit=engine:fit_location(polygon,w,h)
assert(math.abs(fit.objects[2].style.longitude-expected.longitude)<1e-8)
assert(math.abs(fit.objects[2].style.latitude-expected.latitude)<1e-8)
assert(math.abs(fit.objects[2].style.zoom-expected.zoom)<1e-8)
assert(camera:GetInput('Zoom')==fit.objects[2].style.zoom)
-- Point lacks an area: it has the explicit 4x focus reference zoom.
local fitted=engine:fit_location({geometryType='Point',point=sao},w,h)
assert(fitted.objects[2].style.zoom==4)
-- Bearing must not be reset by Focus or Fit.
engine:set_camera_pose({bearing=31})
engine:fit_location(polygon,w,h)
assert(camera:GetInput('Bearing')==31)
local before=engine:current()
local oldLon,oldLat=camera:GetInput('CenterLongitude'),camera:GetInput('CenterLatitude')
local oldZoom=camera:GetInput('Zoom')
-- Native spline on SECOND input refuses operation and restores first input.
camera:SetData('CartoRig.V2.Animated.CenterLatitude',true)
assert(not pcall(function()engine:focus_camera({lon=20,lat=10})end))
camera:SetData('CartoRig.V2.Animated.CenterLatitude',nil)
assert(camera:GetInput('CenterLongitude')==oldLon and camera:GetInput('CenterLatitude')==oldLat)
assert(engine:current().objects[2].style.longitude==before.objects[2].style.longitude)
-- Native SetInput failure on second input restores first.
comp.reject_input='CenterLatitude'
assert(not pcall(function()engine:focus_camera({lon=24,lat=11})end))
comp.reject_input=nil
assert(camera:GetInput('CenterLongitude')==oldLon and camera:GetInput('CenterLatitude')==oldLat)
-- Scene repository write failure restores all native camera fields.
comp.fail_store=true
assert(not pcall(function()engine:focus_camera({lon=12,lat=13})end))
comp.fail_store=false
assert(camera:GetInput('CenterLongitude')==oldLon and camera:GetInput('CenterLatitude')==oldLat)
assert(engine:current().objects[2].style.longitude==oldLon)
-- Cancel invalid camera commands before changing native inputs.
assert(not pcall(function()engine:focus_camera({lon=2,lat=89})end))
assert(not pcall(function()engine:set_camera_pose({zoom=3,unexpected=1})end))
assert(camera:GetInput('Zoom')==oldZoom)
assert(not pcall(function()engine:fit_location({geometryType='Polygon',geometry={type='Polygon',coordinates={}}},w,h)end))
comp.prefs={}
assert(not pcall(function()engine.host:viewport()end))
assert(not pcall(function()engine:fit_location({geometryType='Point',point=sao},0,h)end))
assert(out and not out.deleted)
print('PASS native Focus/Fit Camera: exact viewport, WGS84, no automatic keys, preserved bearing, atomic rollback')
