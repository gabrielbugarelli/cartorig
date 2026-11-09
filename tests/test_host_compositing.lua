-- Host-level integration contracts: media connection preservation and hole topology.
local root=assert(arg[1])
local Scene=dofile(root..'/src/cartorig/scene.lua')
local Host=dofile(root..'/src/cartorig/fusion_host.lua')
local function mock(opts)
  opts=opts or {}
  local comp={nodes={},failed=false}
  local Tool={};Tool.__index=Tool
  function Tool:SetAttrs(a)self.Name=a.TOOLS_Name end
  function Tool:GetAttrs()return {TOOLS_RegID=self.ID,TOOLS_Name=self.Name}end
  function Tool:GetData(key)return self.data[key]end
  function Tool:SetData(key,val)self.data[key]=val end
  function Tool:SetInput(key,val)
    if key=='PaintMode' and opts.rejectPaint then return false end
    self.inputs[key]=val;return true
  end
  function Tool:ConnectInput(key,source)
    if self.ID=='MediaOut' and opts.rejectOutput and source and source.ID~='MediaIn' then
      return false
    end
    self.links[key]=source;return true
  end
  function Tool:GetInputList()
    return {Input={GetConnectedOutput=function()
      local upstream=self.links.Input
      if not upstream then return nil end
      return {GetTool=function()return upstream end}
    end}}
  end
  function Tool:Delete()self.deleted=true end
  function comp:AddTool(id,...)
    local node=setmetatable({ID=id,data={},inputs={},links={},Name=id..tostring(#self.nodes+1),deleted=false},Tool)
    self.nodes[#self.nodes+1]=node
    return node
  end
  function comp:FindTool(name)
    for _,n in ipairs(self.nodes) do if n.Name==name and not n.deleted then return n end end
  end
  function comp:GetToolList()
    local out={};for _,n in ipairs(self.nodes) do if not n.deleted then out[#out+1]=n end end;return out
  end
  function comp:StartUndo(_)end
  function comp:EndUndo(_)end
  local source=comp:AddTool('MediaIn')
  local output=comp:AddTool('MediaOut')
  if opts.prewired~=false then output:ConnectInput('Input',source) end
  if opts.noInputIntrospection then output.GetInputList=false end
  local host=Host.new(comp,{readstring=function(src)
    if src:find('FuID',1,true) then return {type='FuID',value='Subtract'} end
    assert(src:find('Polyline {',1,true));return {type='Polyline',value=src}
  end})
  return host,comp,source,output
end
local host,comp,source,out=mock()
local scene=Scene.new('integration-scene-001')
assert(host:init_base(scene))
local overlay=comp:FindTool(scene.outputMergeToolRef)
assert(overlay and overlay.ID=='Merge')
assert(comp:FindTool(scene.objects[2].hostToolRef).ID=='CartoRigCamera')
assert(overlay.links.Background==source)
assert(overlay.links.Foreground==comp:FindTool(scene.objects[2].hostToolRef))
assert(out.links.Input==overlay)
assert(host:rollback_base(scene))
assert(out.links.Input==source)
assert(not scene.hostInitialized)
assert(#comp:GetToolList()==2)
assert(source.deleted==false and out.deleted==false)
-- Failing to create an output wire restores the user's upstream and deletes no user nodes.
local failhost,failcomp,original,oldout=mock({rejectOutput=true})
local failstate=Scene.new('integration-scene-002')
assert(not pcall(function()failhost:init_base(failstate)end))
assert(oldout.links.Input==original)
assert(#failcomp:GetToolList()==2)
-- Fail closed if a preexisting user graph cannot be inspected.
local closed,cclosed,up,upout=mock({noInputIntrospection=true})
local prior=#cclosed:GetToolList()
assert(not pcall(function()closed:init_base(Scene.new('integration-scene-003'))end))
assert(#cclosed:GetToolList()==prior and upout.links.Input==up)
-- Polygon with hole: one effect-mask chain [outer -> hole/Subtract].
local h,ch=mock()
local st=Scene.new('integration-scene-004');assert(h:init_base(st))
local region={id='island',kind='Country',name='Island',geometryType='Polygon',geometry={
  type='Polygon',coordinates={
    {{-20,-20},{20,-20},{20,20},{-20,20},{-20,-20}},
    {{-8,-8},{8,-8},{8,8},{-8,8},{-8,-8}}
  }
}}
local object=Scene.add_location(st,region,'Region')
assert(h:add_region(st,object,region))
local masks={}
for _,node in ipairs(ch:GetToolList()) do
  if node:GetData('CartoRig.V2.Kind')=='InternalMask' and node:GetData('CartoRig.V2.ObjectId')==object.id then
    masks[#masks+1]=node
  end
end
assert(#masks==2,'outer and hole retained')
local subtract=nil
for _,node in ipairs(masks) do
  if node.inputs.PaintMode then
    assert(node.inputs.PaintMode.type=='FuID')
    assert(node.links.EffectMask)
    subtract=node
  end
end
assert(subtract and subtract.links.EffectMask.inputs.PaintMode==nil)
-- A rejected PaintMode must leave neither internal masks nor other owned artifacts.
local badhost,badcomp=mock({rejectPaint=true})
local badscene=Scene.new('integration-scene-005');assert(badhost:init_base(badscene))
local before=#badcomp:GetToolList()
local badobj=Scene.add_location(badscene,region,'Region')
local last=badscene.lastLayerRef
assert(not pcall(function()badhost:add_region(badscene,badobj,region)end))
assert(#badcomp:GetToolList()==before)
assert(badscene.lastLayerRef==last)
-- LuaJIT 5.1 compatibility: table.unpack is absent; Label does not depend on it.
local f=assert(io.open(root..'/src/cartorig/fusion_objects.lua','rb'))
local src=f:read('*a');f:close()
assert(not src:find('table%.unpack',1,false))
print('PASS host integration: non-destructive MediaOut overlay, rollback, polygon holes, Lua 5.1 portability')
