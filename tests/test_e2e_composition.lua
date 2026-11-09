-- One automated vertical slice: authoring commands, geospatial masking,
-- native keyframes, persisted scene data and MediaOut ownership isolation.
-- The mock explicitly does not assert actual Resolve image output.
local root=assert(arg[1])
local function load(name) return dofile(root..'/src/cartorig/'..name..'.lua') end
local mod={Scene=load('scene'),Repository=load('repository'),Json=load('json'),
 Host=load('fusion_host'),Objects=load('fusion_objects'),Geo=load('geo'),
 Motion=load('motion'),Writer=load('motion_apply')}
local Author=load('authoring')
local comp={nodes={},data={},undos=0}
local Tool={};Tool.__index=Tool
function Tool:SetAttrs(v)self.Name=v.TOOLS_Name end
function Tool:GetAttrs()return {TOOLS_Name=self.Name,TOOLS_RegID=self.ID}end
function Tool:SetData(key,value)self.data[key]=value end
function Tool:GetData(key)return self.data[key]end
function Tool:SetInput(key,value,frame)
 self.inputs[key]=self.inputs[key] or {}
 self.inputs[key][frame or 'static']=value
 return true
end
function Tool:ConnectInput(name,source)self.links[name]=source;return true end
function Tool:AddModifier(name,kind)self.modifiers[name]=kind;return true end
function Tool:GetInputList()
 local out={}
 for name in pairs(self.inputs) do
  local node=self
  out[name]={GetKeyFrames=function()
    local frames={}
    for t,v in pairs(node.inputs[name] or {}) do if type(t)=='number' then frames[t]=v end end
    return frames
  end}
 end
 if self.ID=='MediaOut' then
  out.Input={GetConnectedOutput=function()
   if not self.links.Input then return nil end
   local upstream=self.links.Input
   return {GetTool=function()return upstream end}
  end}
 end
 return out
end
function Tool:Delete()self.deleted=true end
function comp:AddTool(kind)
 local t=setmetatable({ID=kind,data={},inputs={},links={},modifiers={},Name=kind..tostring(#self.nodes+1)},Tool)
 self.nodes[#self.nodes+1]=t;return t
end
function comp:GetToolList()
 local result={};for _,tool in ipairs(self.nodes) do if not tool.deleted then result[#result+1]=tool end end
 return result
end
function comp:FindTool(name)
 for _,tool in ipairs(self.nodes) do if tool.Name==name and not tool.deleted then return tool end end
end
function comp:GetData(key)return self.data[key]end
function comp:SetData(key,value)self.data[key]=value;return true end
function comp:StartUndo()self.undos=self.undos+1 end
function comp:EndUndo(success)assert(success~=false,'unexpected failed host transaction')end
function comp:SetActiveTool(t)self.active=t end
comp.CurrentFrame={FlowView={Select=function(_,tool)comp.selected=tool end}}
local media=comp:AddTool('MediaIn')
local out=comp:AddTool('MediaOut');out:ConnectInput('Input',media)
local bridge={readstring=function(data)
 assert(type(data)=='string' and #data<1000000)
 if data:find('FuID',1,true) then return {mode='Subtract'} end
 assert(data:find('Polyline {',1,true))
 return {polyline=data}
end}
local author=Author.new(comp,mod,bridge,'fixture-natural-earth-v1')
local scene=author:initialize('end-to-end-scene-001','fixture-natural-earth-v1')
local out_merge=comp:FindTool(scene.outputMergeToolRef)
assert(out.links.Input==out_merge and out_merge.links.Background==media)
assert(out_merge.links.Foreground==comp:FindTool(scene.objects[2].hostToolRef))
local brazil={id='fixture:BR',kind='Country',name='Brazil',source={dataset='test-admin0',version='1'},
 geometryType='Polygon',geometry={type='Polygon',coordinates={
  {{-74,-33},{-35,-33},{-35,5},{-74,5},{-74,-33}},
  {{-50,-9},{-48,-9},{-48,-7},{-50,-7},{-50,-9}},
 }}}
local state1,reg=author:add_location(brazil,'Region')
assert(reg.hostToolRef and state1.lastLayerRef==reg.compositeToolRef)
local city={id='fixture:sp',name='São Paulo',kind='City',geometryType='Point',
 source={dataset='test-city',version='1'},point={lon=-46.6333,lat=-23.5505}}
local _,marker=author:add_location(city,'Marker')
local _,label=author:add_location(city,'Label')
local _,route=author:add_route({lon=-47.9,lat=-15.8},{lon=-51.1,lat=0.8})
assert(route.hostToolRef and label.hostToolRef and marker.hostToolRef)
local state=author:current()
assert(#state.objects==6 and mod.Scene.validate(state))
assert(author:select(reg.id)==comp:FindTool(reg.hostToolRef))
local fade=author:motion(reg.id,'MO-REG-01',{start=100,frameCount=900})
local region=comp:FindTool(reg.hostToolRef)
assert(fade.channels.opacity and region.modifiers.ObjectOpacity=='BezierSpline')
assert(region.inputs.ObjectOpacity[100]==0 and region.inputs.ObjectOpacity[124]==1)
local cam=state.objects[2]
local fly=author:motion(cam.id,'MO-CAM-01',{start=200,frameCount=900,
 targetPose={longitude=-46.6333,latitude=-23.5505,zoom=4}})
assert(fly.channels.longitude and fly.channels.latitude and fly.channels.zoom)
assert(comp:FindTool(cam.hostToolRef).inputs.Zoom[245]==4)
-- An incompatible later preset cannot erase already authored spline keys.
assert(not pcall(function()author:motion(reg.id,'MO-REG-02',{start=300,frameCount=900})end))
local marker_tool=comp:FindTool(marker.hostToolRef)
assert(author:set_visible(marker.id,false))
assert(comp:FindTool(marker.compositeToolRef).inputs.Blend.static==0)
assert(marker_tool.deleted~=true)
assert(author:set_visible(marker.id,true))
assert(comp:FindTool(marker.compositeToolRef).inputs.Blend.static==1)
assert(author:rename(label.id,'Sao Paulo labelled') and author:current().objects[5]~=nil)
local reopened=Author.new(comp,mod,bridge,'fixture-natural-earth-v1')
local restored=reopened:current()
assert(restored.id==scene.id and #restored.objects==6)
assert(mod.Scene.get(restored,reg.id).motion.opacity[1].presetId=='MO-REG-01')
assert(out.links.Input==out_merge and out_merge.links.Background==media)
assert(reopened:select(route.id)==comp:FindTool(route.hostToolRef))
assert(not pcall(function()Author.new(comp,mod,bridge,'other-bundle'):add_route({lon=0,lat=0},{lon=1,lat=1})end))
assert(media.deleted~=true)
print('PASS E2E MOCK: external MediaOut, polygon+hole, Marker, Label, Route, native Fade/Fly, conflicts, visibility, IDs and reopen')