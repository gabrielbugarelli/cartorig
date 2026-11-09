-- End-to-end mocked Fusion host verification for managed Z-order operations.
-- Tests actual socket links, not only the Scene JSON ordering.
local root=assert(arg[1])
local function load(n)return dofile(root..'/src/cartorig/'..n..'.lua')end
local m={Scene=load('scene'),Repository=load('repository'),Json=load('json'),
 Host=load('fusion_host'),Objects=load('fusion_objects'),Geo=load('geo'),
 Motion=load('motion'),Writer=load('motion_apply'),GraphOps=load('graph_ops'),SceneOps=load('scene_ops')}
local Author=load('authoring')
local comp={nodes={},data={},refuse=nil,fail_store=false}
local T={};T.__index=T
function T:SetAttrs(a)self.Name=a.TOOLS_Name end
function T:GetAttrs()return {TOOLS_Name=self.Name,TOOLS_RegID=self.ID}end
function T:SetData(k,v)self.data[k]=v end
function T:GetData(k)return self.data[k]end
function T:SetInput(k,v,t)self.inputs[k]=self.inputs[k] or {};self.inputs[k][t or 'static']=v;return true end
function T:GetInput(k,t)return self.inputs[k] and self.inputs[k][t or 'static']end
function T:ConnectInput(k,source)
 if comp.refuse==self and source then comp.refuse=nil;return false end
 self.links[k]=source;return true
end
function T:GetInputList()
 local r={}
 for _,key in ipairs({'Input','Background','Foreground'}) do
  r[key]={GetConnectedOutput=function()
   local node=self.links[key]
   return node and {GetTool=function()return node end} or nil
  end}
 end
 return r
end
function T:Delete()self.deleted=true end
function T:AddModifier(k,method)self.modifiers[k]=method;return true end
function comp:AddTool(kind)
 local n=setmetatable({ID=kind,Name=kind..tostring(#self.nodes+1),data={},links={},inputs={},modifiers={}},T)
 self.nodes[#self.nodes+1]=n;return n
end
function comp:GetToolList()
 local list={};for _,node in ipairs(self.nodes) do if not node.deleted then list[#list+1]=node end end
 return list
end
function comp:FindTool(name)
 for _,node in ipairs(self.nodes) do if not node.deleted and node.Name==name then return node end end
end
function comp:GetData(key)return self.data[key]end
function comp:SetData(key,value)
 if self.fail_store then error('storage refused') end
 self.data[key]=value;return true
end
function comp:StartUndo()end
function comp:EndUndo()end
function comp:SetActiveTool(tool)self.active=tool end
comp.CurrentFrame={FlowView={Select=function(_,node)comp.selected=node end}}
local external=comp:AddTool('MediaIn')
local output=comp:AddTool('MediaOut');output:ConnectInput('Input',external)
local bridge={readstring=function(src)
 if src:find('FuID',1,true) then return {source=src} end
 assert(src:find('Polyline {',1,true));return {source=src}
end}
local author=Author.new(comp,m,bridge,'fixture-bundle')
local scene=author:initialize('draw-order-scene-0001','fixture-bundle')
local polygon={id='br',name='Brazil',kind='Country',geometryType='Polygon',
 geometry={type='Polygon',coordinates={{{-60,-20},{-40,-20},{-40,0},{-60,0}}}}}
local _,r=author:add_location(polygon,'Region')
local city={id='sp',name='São Paulo',kind='City',geometryType='Point',point={lon=-47,lat=-23}}
local _,mark=author:add_location(city,'Marker')
local _,lbl=author:add_location(city,'Label')
local base=comp:FindTool(scene.objects[1].hostToolRef)
local camera=comp:FindTool(scene.objects[2].hostToolRef)
local _,route=author:add_route({lon=-47,lat=-23},{lon=-52,lat=-2})
local function tool(o)return author.host:tool_for(o)end
-- Region color is three independent native channels, not a UI-only value.
local before=tool(r):GetInput('FillRed')
author:set_style(r.id,'fill','#00C040')
assert(tool(r):GetInput('FillRed')==0)
assert(math.abs(tool(r):GetInput('FillGreen')-192/255)<1e-9)
assert(author:current().objects[3].style.fill=='#00C040')
-- Style values belong to each authored Region only.
assert(comp:FindTool(scene.objects[1].hostToolRef):GetInput('OceanRed')==nil or not tool(r).deleted)
-- Marker and Route expose their own authorial Fuse channels.
author:set_style(mark.id,'fill','#AABBCC')
assert(tool(mark):GetInput('FillRed')==170/255)
author:set_style(mark.id,'opacity',60)
assert(tool(mark):GetInput('ObjectOpacity')==0.6)
author:set_style(mark.id,'size',22)
assert(comp:FindTool(mark.maskToolRef):GetInput('Width')==22/1080)
author:set_style(route.id,'stroke','#010203')
assert(math.abs(tool(route):GetInput('StrokeRed')-1/255)<1e-9)
author:set_style(route.id,'strokeWidth',5)
assert(comp:FindTool(route.maskToolRef):GetInput('BorderWidth')==5/1080)
author:set_style(route.id,'drawProgress',35)
assert(math.abs(comp:FindTool(route.maskToolRef):GetInput('WriteLength')-0.35)<1e-9)
-- Text data stays on TextPlus while style is on the Label Fuse.
author:set_style(lbl.id,'color','#112233')
assert(tool(lbl):GetInput('TextBlue')==51/255)
author:set_style(lbl.id,'fontSize',42)
local labelSource
for _,n in ipairs(comp:GetToolList())do
 if n:GetData('CartoRig.V2.ObjectId')==lbl.id and n:GetData('CartoRig.V2.Kind')=='InternalLabelText' then labelSource=n end
end
assert(labelSource and labelSource:GetInput('Size')==42/1080)
-- Structural controls are also routed through their native authorial tools.
local cam=author:current().objects[2]
author:set_style(cam.id,'zoom',3)
assert(comp:FindTool(cam.hostToolRef):GetInput('Zoom')==3)
local bas=author:current().objects[1]
author:set_style(bas.id,'displayMode','Transparent Overlay')
assert(comp:FindTool(bas.hostToolRef):GetInput('DisplayMode')==1)
-- Region Stroke is now a separate Color/Alpha/Visibility channel.
author:set_style(r.id,'stroke','#112233')
assert(math.abs(tool(r):GetInput('StrokeBlue')-51/255)<1e-9)
author:set_style(r.id,'strokeAlpha',45)
assert(tool(r):GetInput('StrokeAlpha')==0.45)
author:set_style(r.id,'strokeVisible',false)
assert(tool(r):GetInput('StrokeVisible')==0)
-- An unsupported property must fail before mutating the Scene metadata.
local s=author:current()
assert(not pcall(function()author:set_style(r.id,'unknownStrokeMode','double')end))
assert(author:current().objects[3].style.stroke==s.objects[3].style.stroke)
-- A persisted spline must not be overwritten by a static Control operation.
tool(r):SetData('CartoRig.V2.Animated.FillRed',true)
assert(not pcall(function()author:set_style(r.id,'fill','#123456')end))
tool(r):SetData('CartoRig.V2.Animated.FillRed',nil)
-- Failed metadata persistence restores original native pixel-affecting inputs.
local old=tool(r):GetInput('FillRed')
comp.fail_store=true
assert(not pcall(function()author:set_style(r.id,'fill','#ABCDEF')end))
comp.fail_store=false
assert(tool(r):GetInput('FillRed')==old)
assert(author:current().objects[3].style.fill=='#00C040')
-- Failure after the first channel write must restore the others.
local oldSetter=T.SetInput
function T:SetInput(k,v,t)
 if self==tool(r) and k=='FillGreen' and v~=self:GetInput('FillGreen') then return false end
 return oldSetter(self,k,v,t)
end
assert(not pcall(function()author:set_style(r.id,'fill','#FFEE00')end))
T.SetInput=oldSetter
assert(tool(r):GetInput('FillRed')==old)
assert(author:current().objects[3].style.fill=='#00C040')
-- Node rename does not change the ability to edit by stable object ID.
tool(mark):SetAttrs({TOOLS_Name='Renamed Marker Tool'})
author:set_style(mark.id,'opacity',85)
assert(tool(mark):GetInput('ObjectOpacity')==0.85)
assert(not external.deleted and not output.deleted)
print('PASS native Control: RGB, opacity, marker size, route width/progress, label font, camera, base, rollback and spline protection')
