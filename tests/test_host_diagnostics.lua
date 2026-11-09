local root=assert(arg[1])
local comp={nodes={}}
local T={};T.__index=T
function T:GetAttrs()return {TOOLS_RegID=self.id}end
function T:GetInputList()
  local names=self.id=='CartoRigRegion' and {'FillRed','FillGreen','FillBlue','ObjectOpacity','HighlightStrength'}
     or self.id=='CartoRigBase' and {'DisplayMode','OceanLayerOpacity'}
     or self.id=='CartoRigCamera' and {'CenterLongitude','CenterLatitude','Zoom','Bearing'} or {}
  local inputs={}
  for _,name in ipairs(names) do
    inputs[name]={GetKeyFrames=function()return {[5]={0.25},[20]={0.75}}end}
  end
  return inputs
end
function T:AddModifier()return true end
function T:SetInput()return true end
function T:ConnectInput()return true end
function T:Delete()self.deleted=true end
function comp:AddTool(name)
 local tool=setmetatable({id=name,deleted=false},T)
 self.nodes[#self.nodes+1]=tool
 return tool
end
function comp:GetToolList()
 local out={};for _,t in ipairs(self.nodes) do if not t.deleted then out[#out+1]=t end end
 return out
end
local original=comp:AddTool('MediaOut')
_G.comp=comp
_G.fusion=nil
_G.bmd={readstring=function(text)
 if text:find('Polyline',1,true) then return {polyline=true} end
 if text:find('FuID',1,true) then return {value='Subtract'} end
 return nil
end}
assert(loadfile(root..'/fusion/CartoRig Host Diagnostics.lua'))()
assert(#comp:GetToolList()==1 and comp:GetToolList()[1]==original)
assert(not original.deleted)
_G.comp=nil;_G.bmd=nil
print('PASS Host diagnostics script: tool registration, mask chain, spline and cleanup in disposable mock')
