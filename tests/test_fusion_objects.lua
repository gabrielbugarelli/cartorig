local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local Host=dofile(root..'/src/cartorig/fusion_host.lua')
local Objects=dofile(root..'/src/cartorig/fusion_objects.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local Geo=dofile(root..'/src/cartorig/geo.lua')
local c={nodes={},undo={}}
local T={};T.__index=T
function T:SetAttrs(a)self.Name=a.TOOLS_Name end
function T:GetAttrs()return {TOOLS_Name=self.Name,TOOLS_RegID=self.ID}end
function T:SetData(k,v)self.data[k]=v end
function T:GetData(k)return self.data[k] end
function T:SetInput(k,v,frame)self.inputs[k]=self.inputs[k] or {};self.inputs[k][frame or 'static']=v;return true end
function T:GetInput(k,frame)return self.inputs[k] and self.inputs[k][frame or 'static']end
function T:ConnectInput(k,node)self.links[k]=node;return true end
function T:AddModifier(k,kind)self.mods[k]=kind;return true end
function T:Delete() self.deleted=true end
function c:AddTool(id) local o=setmetatable({ID=id,Name='Node'..#self.nodes,data={},inputs={},links={},mods={}},T);self.nodes[#self.nodes+1]=o;return o end
function c:GetToolList()local a={};for _,t in ipairs(self.nodes)do if not t.deleted then a[#a+1]=t end end;return a end
function c:FindTool(name)for _,t in ipairs(self.nodes)do if not t.deleted and t.Name==name then return t end end end
function c:StartUndo(x)self.lastUndo=x end
function c:EndUndo(ok)self.undo[#self.undo+1]={name=self.lastUndo,ok=ok} end
local output=c:AddTool('MediaOut')
local host=Host.new(c,{readstring=function(s)assert(s:find('Polyline {',1,true));return s end})
local state=Scene.new('fresh-scene-004')
assert(host:init_base(state))
local ref={id='brazil:rio',name='Rio',type='City',dataset='Natural Earth',version='10m',point={lon=-43.2,lat=-22.9}}
local marker=Scene.add_location(state,ref,'Marker')
Objects.build(host,state,marker,'Marker')
assert(host:tool_for(marker));assert(c:FindTool(marker.maskToolRef))
local label=Scene.add_location(state,ref,'Label')
Objects.build(host,state,label,'Label')
local label_text
for _,tool in ipairs(c:GetToolList()) do
  if tool:GetData('CartoRig.V2.ObjectId')==label.id and tool:GetData('CartoRig.V2.Kind')=='InternalLabelText' then label_text=tool end
end
assert(label_text and label_text.inputs.StyledText.static=='Rio')
assert(c:FindTool(label.hostToolRef).ID=='CartoRigLabel')
assert(c:FindTool(label.hostToolRef).inputs.TextRed.static>0)
local route=Scene.add_route(state,{lon=-47.91,lat=-15.78},{lon=-51.68,lat=1.41})
local points=Geo.route_samples(route.route,8)
Objects.build(host,state,route,'Route',points)
assert(c:FindTool(route.maskToolRef) and #c:GetToolList()>=10)
local camera=state.objects[2]
assert(c:FindTool(camera.hostToolRef).links.Input==c:FindTool(state.lastLayerRef))
local options={start=100,frameCount=900}
local pop=Motion.prepare(marker,'MO-MRK-02',options,{})
assert(Writer.apply(host,marker,pop))
assert(math.abs(c:FindTool(marker.maskToolRef).inputs.Width[118]-14/1080)<1e-9)
local fade=Motion.prepare(label,'MO-LBL-01',options,{})
assert(Writer.apply(host,label,fade))
assert(c:FindTool(label.hostToolRef).inputs.ObjectOpacity[118]==1)
local draw=Motion.prepare(route,'MO-RTE-01',options,{})
assert(Writer.apply(host,route,draw))
assert(c:FindTool(route.maskToolRef).inputs.WriteLength[130]==1)
local fly=Motion.prepare(camera,'MO-CAM-01',{start=100,frameCount=900,targetPose={longitude=-46.63,latitude=-23.5,zoom=4}}, {})
assert(Writer.apply(host,camera,fly))
assert(c:FindTool(camera.hostToolRef).inputs.Zoom[145]==4)
assert(math.abs(c:FindTool(camera.hostToolRef).inputs.CenterLongitude[145]+46.63)<1e-8)
assert(c:FindTool(camera.hostToolRef).inputs.CenterLatitude[145]==-23.5)
local invalid=Motion.prepare(marker,'MO-MRK-01',{start=200,frameCount=900},{})
invalid.channels.fake={{frame=200,value=1}}
local before=#c.undo
assert(not pcall(function()Writer.apply(host,marker,invalid)end))
assert(#c.undo==before) -- preflight must not even start an undo
assert(Scene.validate(state))
print('PASS Fusion-native Marker/Label/Route, geoanchor, camera, 4 motion writers, preflight failures')
