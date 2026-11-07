-- Reproduces the actual host failure: _G.Polyline is absent.
-- Native polygon shapes must be loaded from a Fusion .setting.
local root=arg[1] or '.'
local G=assert(loadfile(root..'/fusion/CartoRig/graph.lua'))()
_G.Polyline=nil
local settings_seen={}
_G.bmd={readstring=function(data)
  assert(not data:find('NaN',1,true))
  assert(data:find('Value = Polyline {',1,true))
  assert(data:find('Tools = ordered()',1,true))
  settings_seen[#settings_seen+1]=data
  return {native=true,raw=data}
end}
local function fresh()
    local tools,store={},{}
    local T={}
    T.__index=T
    function T:SetAttrs(p) self.Name=p.TOOLS_Name end
    function T:GetAttrs()return {TOOLS_RegID=self.ID}end
    function T:SetData(k,v)self.data[k]=v end
    function T:GetData(k)return self.data[k]end
    function T:SetInput(k,v,t)self.inputs[k]=v end
    function T:ConnectInput(k,src) self.wires[k]=src;return true end
    function T:LoadSettings(setting)
      assert(self.ID=='PolylineMask')
      assert(setting.native)
      self.setting=setting.raw
      return true
    end
    function T:Delete() for i,v in ipairs(tools)do if self==v then table.remove(tools,i);break end end end
    local function push(id)
      local t=setmetatable({ID=id,Name=id..tostring(#tools+1),data={},inputs={},wires={}},T)
      tools[#tools+1]=t
      return t
    end
    push('MediaOut')
    local c={CurrentTime=0,locked=false}
    function c:AddTool(id) return push(id) end
    function c:GetToolList() return tools end
    function c:GetData(k)return store[k]end
    function c:SetData(k,v)store[k]=v end
    function c:FindTool(name)for _,n in ipairs(tools)do if n.Name==name then return n end end end
    function c:StartUndo() end
    function c:EndUndo() end
    function c:Lock()self.locked=true end
    function c:Unlock()self.locked=false end
    return c,tools
end
local c,nodes=fresh()
local small_world={{id='ne110:world-land',polygons={{
    {{-55,-20},{-48,-20},{-48,-12},{-55,-12}}
}}}}
assert(G.ensure(c,small_world)==true)
assert(#settings_seen==1)
assert(settings_seen[1]:find('Closed = true',1,true))
assert(settings_seen[1]:find('X = ',1,true))
assert(c:FindTool('CR2_Mask_Land_1').setting)
assert(c.locked==false)
assert(G.ensure(c,small_world)==false)
local c2,nodes2=fresh()
_G.bmd.readstring=function()return nil end
local ok,err=pcall(G.ensure,c2,small_world)
assert(not ok and tostring(err):find('could not parse a native PolylineMask',1,true))
assert(c2:GetData('CartoRig.Scene.Version')==nil)
assert(c2.locked==false)
assert(#nodes2==1)
assert(_G.Polyline==nil)
print('PASS: no global Polyline needed; settings parsed, applied, and failure rolled back')
