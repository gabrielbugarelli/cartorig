-- Contract tests for the Fusion Scene backend. A mock host is NOT a
-- substitute for in-app Resolve 20 HOST-01..HOST-10 verification.
local function check(ok,message)if not ok then error("FAIL "..message,2) end end
local T={}
T.__index=function(t,k)
    if T[k]then return T[k]end
    t.inputs[k]=t.inputs[k] or {SetExpression=function(self,v)
        self.expression=v;return true
    end}
    return t.inputs[k]
end
function T.new(kind)
    return setmetatable({kind=kind,name=kind,inputs={},data={},values={},deleted=false},T)
end
function T:SetAttrs(v)self.name=v.TOOLS_Name;return true end
function T:GetAttrs()return {TOOLS_Name=self.name}end
function T:GetData(k)return self.data[k]end
function T:SetData(k,v)self.data[k]=v;return true end
function T:SetInput(k,v,f)
    self.values[k]=v;return true
end
function T:GetInput(k)return self.values[k]end
function T:ConnectInput(k,t)
    self.values[k]=t
    return true
end
function T:Delete()self.deleted=true;return true end
local C={}
C.__index=C
function C.new()
    local comp=setmetatable({nodes={},CurrentTime=0,undos=0},C)
    local output=T.new("MediaOut");output.name="MediaOut1"
    output.Input={GetConnectedOutput=function()return nil end}
    comp.nodes[1]=output
    return comp
end
function C:GetToolList()
    local out={}
    for _,tool in ipairs(self.nodes)do if not tool.deleted then
        out[#out+1]=tool
    end end
    return out
end
function C:FindTool(n)
    for _,tool in ipairs(self.nodes)do
        if not tool.deleted and tool.name==n then return tool end
    end
    return nil
end
function C:FindToolByID(k)
    for _,t in ipairs(self.nodes)do if not t.deleted and t.kind==k then
        return t end
    end
end
function C:AddTool(k,x,y)
    local node=T.new(k);self.nodes[#self.nodes+1]=node
    return node
end
function C:StartUndo(title)self.undos=self.undos+1;return true end
function C:EndUndo(ok)return true end
function C:SetActiveTool(node)self.active=node;return true end
function C:GetAttrs()return {COMPS_Name="Test composition"}end
local data="build/mock-geo-catalog"
os.execute("mkdir -p "..data)
local file=assert(io.open(data.."/catalog.tsv","wb"))
file:write("id\tkind\tname\tparent\taliases\tminx\tminy\tmaxx\tmaxy\toffset\tbytes\n")
file:write("ne_10m_admin_0_countries:1\tcountry\tBrazil\tSouth America\tbrazil|brasil\t-74\t-34\t-34\t6\t8\t99\n")
file:write("ne_10m_admin_1_states_provinces:22\tstate\tRio de Janeiro\tBrazil\trio de janeiro\t-45\t-25\t-40\t-20\t107\t88\n")
file:write("ne_10m_populated_places:3\tcity\tSão Paulo\tBrazil\tsao paulo\t-46.63\t-23.55\t-46.63\t-23.55\t195\t44\n")
file:close()
_G.CARTORIG_TEST_DATA=data
comp=C.new()
local api=dofile("fusion/CartoRigSupport/scene.lua")
check(not api.isInitialized(),"empty fusion composition")
local created,message=api.initialize()
check(created,"initialize new scene")
check(api.isInitialized(),"initialized current composition")
check(#api.objects()==2,"Base Map and Camera are sole defaults")
check(comp:FindTool("CR_Stack_Output")~=nil,"output created")
check(comp:FindTool("CR_Base_Map"):GetInput("CountryA")==nil,
      "no injected default editorial region")
local state=api.search("Rio de Janeiro","state")
check(#state==1 and state[1].kind=="state","states found by name")
check(#api.search("São Paulo","city")==1,"Unicode city search")
check(#api.search("brasil","country")==1,"Portuguese country alias")
local id=api.addRegion(state[1])
check(#api.objects()==3,"region appended without editing other objects")
local selected=api.select(id)
check(comp.active==selected.node,"node selected for native Inspector")
check(selected.feature==state[1].id,"feature reference persisted")
api.rename(id,"Rio state in blue")
check(api.select(id).name=="Rio state in blue","rename doesn't modify ID")
api.visibility(id,false)
check(not api.select(id).visible,"visibility persisted")
api.lock(id,true)
local ok,err=pcall(function()api.rename(id,"Illegal edit")end)
check(not ok and tostring(err):find("locked")~=nil,"locking blocks edits")
api.lock(id,false)
api.visibility(id,true)
local marker=api.addMarker(api.search("São Paulo","city")[1])
check(#api.objects()==4,"marker independently editable")
api.focus(api.search("São Paulo","city")[1],false)
local camera=comp:FindTool("CR_Camera")
check(camera:GetInput("CenterLongitude")~=nil,"camera focus is static")
local count=#api.objects()
ok,err=pcall(function()api.addRoute({lon=-47.88,lat=-15.79},{lon=999,lat=0})end)
check(not ok and #api.objects()==count,"invalid route point rejected")
local route=api.addRoute({lon=-47.88,lat=-15.79,name="Brasília"},
                         {lon=-51.3,lat=.7,name="Amapá chosen point"})
check(#api.objects()==5,"route created with explicit coordinates")
check(#api.waypoints(route)==0,"new route has no editorial waypoints")
api.addWaypoint(route,-50,-8)
api.addWaypoint(route,-49,-3)
check(#api.waypoints(route)==2,"two real WGS84 waypoints saved")
check(api.select(route).node:GetInput("WaypointsEncoded")=="-50,-8;-49,-3",
      "native render receives waypoint sequence")
api.moveWaypoint(route,2,-1)
check(api.waypoints(route)[1].lon==-49,"move waypoint reorders geometry")
api.reverseRoute(route)
check(api.waypoints(route)[1].lon==-50,"reverse route reverses waypoint order")
check(api.select(route).node:GetInput("FromLongitude")==-51.3,
      "reverse route swaps origins explicitly")
api.removeWaypoint(route,2)
check(#api.waypoints(route)==1,"route waypoint removed without reconstruction")
api.delete(route)
check(#api.objects()==4,"route removed without destroying map")
local label=api.addLabel(api.search("São Paulo","city")[1],"São Paulo")
check(#api.objects()==5,"independent georeferenced Label object")
check(api.select(label).role=="Label","Label retains inspector identity")
check(api.select(label).node:GetInput("StyledText")=="São Paulo",
      "Unicode text survives in native host parameter")
local group=api.addGroup("Northern focus")
check(#api.objects()==6,"organizational Group exists")
api.setParent(label,group)
api.lock(group,true)
local blocked=pcall(function()api.rename(label,"Tampered")end)
check(not blocked,"Group lock prevents editing children")
api.lock(group,false)
api.visibility(group,false)
check(api.select(label).node:GetInput("Visible")==0,
      "Group hides member without deleting it")
api.visibility(group,true)
check(api.select(label).node:GetInput("Visible")==1,
      "Group show restores member's local visibility")
api.ungroup(group)
check(#api.objects()==5,"Ungroup keeps its former Label")
local stateEntry=api.select(id)
api.move(stateEntry.id,1)
check(api.select(id).id==id,"reorder changes Z without mutating identity")
local custom=api.addCustomPoint(-51.3,.7,"Selected Amapá point")
check(api.select(custom).role=="Marker","manual geo point creates Marker")
local refused=pcall(function()api.addMarker(state[1])end)
check(not refused,"state bbox center never silently becomes a city marker")
local other=C.new()
comp=other
check(not api.isInitialized(),"second composition does not inherit first")
check(#api.objects()==0,"no cross-composition scene leak")
comp=C.new()
api.initialize()
check(#api.objects()==2,"second composition starts neutral")
print("PASS: Fusion Scene 1.0 mock context isolation, geo search, CRUD, locks, camera, route")
