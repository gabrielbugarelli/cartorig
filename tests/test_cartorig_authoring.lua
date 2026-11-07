-- Offline mock-host authoring contract, run with Lua 5.4.
-- This is NOT a real Resolve host acceptance.
local function check(value,message)
    if not value then error("FAIL: "..message,2) end
end
local Tool = {}
Tool.__index=function(self,key)
    if Tool[key] then return Tool[key] end
    if self.kind:sub(1,4)=="ofx." then
        self.handles[key]=self.handles[key] or {
            expression=nil,
            SetExpression=function(input,value) input.expression=value;return true end,
            GetExpression=function(input) return input.expression end,
        }
        return self.handles[key]
    end
    return nil
end
function Tool.new(kind)
    return setmetatable({kind=kind,name=kind,vals={},keys={},attrs={},handles={},
                         connections={},metadata={},deleted=false},Tool)
end
function Tool:SetAttrs(attrs)
    self.name=attrs.TOOLS_Name or self.name
    self.attrs.TOOLS_Name=self.name
    return true
end
function Tool:GetAttrs()return {TOOLS_Name=self.name}end
function Tool:SetInput(name,value,frame)
    if frame==nil then self.vals[name]=value
    else self.keys[name]=self.keys[name] or {};self.keys[name][frame]=value end
    return true
end
function Tool:GetInput(name,frame)
    if frame~=nil then
        local value=self.keys[name] and self.keys[name][frame]
        if value~=nil then return value end
    end
    return self.vals[name]
end
function Tool:ConnectInput(id,other)
    self.connections[id]=other
    return true
end
function Tool:AddModifier(name,modifier)
    self.vals[name]=self.vals[name] or 1
    return true
end
function Tool:GetData(id)return self.metadata[id]end
function Tool:SetData(id,value)self.metadata[id]=value;return true end
function Tool:Delete()self.deleted=true end

local Comp = {}
Comp.__index=Comp
function Comp.new()
    local self=setmetatable({tools={},CurrentTime=0},Comp)
    table.insert(self.tools,Tool.new("MediaOut"))
    self.tools[1]:SetAttrs({TOOLS_Name="MediaOut1"})
    return self
end
function Comp:FindTool(name)
    for _,tool in ipairs(self.tools) do
        if tool.name==name and not tool.deleted then return tool end
    end
    return nil
end
function Comp:FindToolByID(id)
    for _,tool in ipairs(self.tools) do
        if tool.kind==id and not tool.deleted then return tool end
    end
    return nil
end
function Comp:AddTool(id,x,y)
    local t=Tool.new(id)
    table.insert(self.tools,t)
    return t
end
function Comp:GetToolList()
    local result={}
    for i,v in ipairs(self.tools) do
        if not v.deleted then result[i]=v end
    end
    return result
end
function Comp:GetAttrs()return {COMPN_GlobalStart=0}end
function Comp:StartUndo(label)return true end
function Comp:EndUndo(commit)return true end
local answer
function Comp:AskUser(title,fields)return answer end

local Item={}
Item.__index=Item
function Item.new()return setmetatable({comp=Comp.new()},Item)end
function Item:GetFusionCompCount()return 1 end
function Item:GetFusionCompByIndex(n)return n==1 and self.comp or nil end

local Timeline={}
Timeline.__index=Timeline
function Timeline.new()return setmetatable({items={},current=nil},Timeline)end
function Timeline:InsertFusionCompositionIntoTimeline()
    local item=Item.new()
    table.insert(self.items,item)
    self.current=item
    return item
end
function Timeline:GetCurrentVideoItem()return self.current end

local timeline=Timeline.new()
local project={GetCurrentTimeline=function()return timeline end}
local manager={GetCurrentProject=function()return project end}
resolve={
    GetVersion=function()return {20,2,1}end,
    GetProjectManager=function()return manager end,
    OpenPage=function(_,page)return page=="edit" end
}
local core=dofile("packaging/easy-test/CartoRigSupport/core.lua")
check(core.search("Brazil").code=="BRA","offline English country lookup")
check(core.search("Brasil").code=="BRA","offline Portuguese alias lookup")
check(core.search("VEN").code=="VEN","ISO3 lookup")
check(core.search("Unknown-Fantasy-Country")==nil,"unknown places not fabricated")
local ok,result=core.run("Create")
check(ok,"Create Map: "..tostring(result))
local comp=timeline.current.comp
local base=comp:FindTool("CR_Map_Base")
local tail=comp:FindTool("CR_Map_LayersOut")
check(base and tail,"Map base and map-stack port")
check(tail.connections.Input==base,"Map base connected to stack")
check(base:GetInput("Zoom")==2.45,"Map starts with intended neutral zoom")
answer={Location="Brazil",Color=0,Reveal=12}
ok,result=core.run("Country")
check(ok,"Add Country BRA: "..tostring(result))
local first=comp:FindTool("CR_Layer_001_BRA")
check(first,"Country layer created")
check(first:GetInput("CountryA")=="BRA","BRA configured from country search")
check(first:GetInput("ObjectLayerOnly")==1,"Country does not redraw the map base")
check(first.Longitude:GetExpression()=="CR_Map_Base.Longitude","Camera expression")
check(first.keys.HighlightStrength[0]==0 and first.keys.HighlightStrength[12]==1,
      "Country has independent reveal keyframes")
check(tail.connections.Input==first,"Map-stack now ends at BRA")
answer={Location="Venezuela",Color=1,Reveal=0}
ok,result=core.run("Country")
check(ok,"Add Country VEN: "..tostring(result))
local second=comp:FindTool("CR_Layer_002_VEN")
check(second and second.connections.Source==first,"VEN stacked over BRA")
check(second:GetInput("HighlightR")==201,"VEN independent red preset")
check(first:GetInput("HighlightR")==212,"BRA retains independent gold preset")
answer={Origin="Brazil",Destination="Venezuela",Color=3,Reveal=24}
ok,result=core.run("Route")
check(ok,"Add Route: "..tostring(result))
local route=comp:FindTool("CR_Layer_003_Route")
check(route and route.connections.Source==second,"Route adds above existing countries")
check(route:GetInput("NativeRouteEnabled")==1,"Route enabled")
check(route:GetInput("NativeRouteBlue")==231,"Route has independent RGB")
check(route.keys.RouteProgress[0]==0 and route.keys.RouteProgress[24]==1,
      "Route draws over 24 frames")
answer={Location="Brazil",Zoom=4.7,Duration=30}
ok,result=core.run("Camera")
check(ok,"Set Camera: "..tostring(result))
check(base.keys.Zoom[0]==2.45 and base.keys.Zoom[30]==4.7,"Camera zoom keyframes")
check(route.Zoom:GetExpression()=="CR_Map_Base.Zoom","Route follows animated camera")
local n=#comp.tools
answer={Location="Definitely Not Here",Color=0,Reveal=12}
ok,result=core.run("Country")
check(not ok and #comp.tools==n,"Unknown country must not mutate composition")
print("PASS: CartoRig Editor mock-host create/add-country/add-route/animate-camera workflow")
