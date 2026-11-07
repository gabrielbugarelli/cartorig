-- CartoRig v1.0 mock-host interaction test. DOES NOT certify Resolve 20.
local function check(ok,msg)if not ok then error("FAIL: "..msg,2)end end
local T={}
T.__index=function(self,k)
    if T[k]then return T[k]end
    if self.kind:sub(1,4)=="ofx." then
        self.inputs[k]=self.inputs[k] or {
            SetExpression=function(it,expr)it.expr=expr;return true end,
            GetExpression=function(it)return it.expr end
        }
        return self.inputs[k]
    end
    return nil
end
function T.new(kind)
    return setmetatable({kind=kind,name=kind,values={},frames={},data={},
                         con={},inputs={},deleted=false},T)
end
function T:SetAttrs(a)self.name=a.TOOLS_Name;return true end
function T:GetAttrs()return {TOOLS_Name=self.name}end
function T:SetInput(k,v,frame)
    if frame~=nil then
        self.frames[k]=self.frames[k] or {}
        self.frames[k][frame]=v
    else self.values[k]=v end
    return true
end
function T:GetInput(k,frame)
    if frame~=nil then return (self.frames[k] or {})[frame] or self.values[k]end
    return self.values[k]
end
function T:SetData(k,v)self.data[k]=v;return true end
function T:GetData(k)return self.data[k]end
function T:AddModifier(k,typ)
    check(typ=="BezierSpline","modifier")
    return true
end
function T:ConnectInput(k,t)self.con[k]=t;return true end
function T:Delete()self.deleted=true;return true end
local C={}
C.__index=C
function C.new()
    local c=setmetatable({all={},CurrentTime=0},C)
    local out=T.new("MediaOut");out.name="MediaOut1";c.all[1]=out
    return c
end
function C:AddTool(k,x,y)
    local t=T.new(k);self.all[#self.all+1]=t;return t
end
function C:GetToolList()
    local list={}
    for _,v in ipairs(self.all)do if not v.deleted then list[#list+1]=v end end
    return list
end
function C:FindTool(name)
    for _,v in ipairs(self.all)do
        if v.name==name and not v.deleted then return v end
    end
    return nil
end
function C:FindToolByID(k)
    for _,v in ipairs(self.all)do if v.kind==k and not v.deleted then return v end end
end
function C:StartUndo(k)return true end
function C:EndUndo(k)return true end
function C:GetAttrs()return {COMPN_GlobalStart=0}end
local I={}
I.__index=I
function I.new()return setmetatable({comp=C.new()},I)end
function I:GetFusionCompCount()return 1 end
function I:GetFusionCompByIndex(index)return index==1 and self.comp end
function I:GetStart()return 0 end
function I:GetName()return "CartoRig Map"end
local Timeline={items={}}
function Timeline:InsertFusionCompositionIntoTimeline()
    local item=I.new()
    self.items[#self.items+1]=item
    return item
end
function Timeline:GetTrackCount(t)return t=="video" and 1 or 0 end
function Timeline:GetItemListInTrack(t,n)
    return t=="video" and n==1 and self.items or {}
end
local project={GetCurrentTimeline=function()return Timeline end}
local manager={GetCurrentProject=function()return project end}
resolve={
    GetVersion=function()return {20,2,0}end,
    GetProjectManager=function()return manager end,
    OpenPage=function(self,page)return page=="edit"end
}
local srv=dofile("packaging/easy-test/CartoRigSupport/service_v1.lua")
local ok,msg=pcall(srv.create)
check(ok,"create neutral Map Scene: "..tostring(msg))
local scenes=srv.scenes()
check(#scenes==1,"one host scene in scene selector")
local core=scenes[1].comp
check(core:FindTool("CR_Map_Base"),"base map created")
check(core:FindTool("CR_Map_LayersOut"),"layers out created")
local found=srv.search("Brasil","country")
check(#found>=1 and found[1].code=="BRA","natural name search without ISO3")
local rio=found[1]
srv.addRegion(1,rio,"#C92A2A","#D4AF37",90)
local one=srv.objects(1)
check(#one==1 and one[1].meta.kind=="country","named Region added")
check(one[1].node:GetInput("CountryA")=="BRA","internal ISO3 remains hidden")
check(one[1].node:GetInput("BorderR")==212,"separate stroke color")
check(one[1].node:GetInput("HighlightR")==201,"separate fill color")
local state={kind="state",name="Rio de Janeiro",parent="Brazil",
             isOfficial=true,geometry="MULTIPOLYGON",sourceLayer="ne_10m_admin_1_states_provinces",
             rowid=10,scale="10m",key="ne_10m_admin_1_states_provinces:10",
             lon=-43.3,lat=-22.9}
srv.addRegion(1,state,"#EE3355","#FFFFFF",100)
local two=srv.objects(1)
check(#two==2 and two[2].meta.name=="Rio de Janeiro","state separate from Brazil")
local json=two[2].node:GetInput("GeographicRegionSaved")
check(json:find('"stroke":%[255,255,255,255%]')~=nil,
      "state stroke persisted separately from fill")
check(json:find('"kind":"state"')~=nil,"real state type stored")
srv.style(1,2,"#3300CC","#ABCDEF",80)
check(srv.objects(1)[1].node:GetInput("HighlightR")==201,
      "editing Rio cannot recolor Brazil")
srv.hide(1,2,true)
check(srv.objects(1)[2].node:GetInput("GeographicRegionSaved"):find('"visible":false'),
      "region hidden without being deleted")
srv.hide(1,2,false)
check(srv.objects(1)[2].node:GetInput("GeographicRegionSaved"):find('"visible":true'),
      "region shown again")
local city={kind="city",name="São Paulo",lat=-23.5505,lon=-46.6333}
srv.focus(1,city,6)
local map=core:FindTool("CR_Map_Base")
check(map:GetInput("Zoom")==6 and map:GetInput("Latitude")==city.lat,
      "Focus changes static camera and creates no keyframes")
check(next(map.frames)==nil,"Focus never implies Animate")
srv.animateCamera(1,city,7,25)
check(map.frames.Zoom and map.frames.Zoom[25]==7,
      "Animate makes native Fusion keyframes")
local brasilia={kind="city",name="Brasília",lat=-15.7939,lon=-47.8828}
local amapa={kind="state",name="Amapá",parent="Brazil"}
local before=#srv.objects(1)
ok,msg=pcall(function()srv.addRoute(1,brasilia,amapa,{})end)
check(not ok and #srv.objects(1)==before,
      "Amapá state is NOT silently converted to a city point")
srv.addRoute(1,brasilia,amapa,{toPoint={lat=0.7,lon=-51.3},
    color="#D4AF37",curve=20,arrowhead=false,width=4})
local route=srv.objects(1)[3]
check(route.meta.type=="Route" and not route.meta.arrowhead,
      "graphic line has optional arrowhead")
check(route.node:GetInput("RouteEndLatitude")==0.7,
      "explicit Amapá point stored")
check(route.node:GetInput("NativeRouteArrowhead")==0,
      "native arrowhead switch")
check(route.node:GetInput("RouteProgress")==1 and next(route.node.frames)==nil,
      "adding route does not create animation")
srv.animateRoute(1,3,12)
check(route.node.frames.RouteProgress[0]==0 and
      route.node.frames.RouteProgress[12]==1,
      "route reveal uses native spline at host time")
srv.baseStyle(1,"land","#243547")
check(map:GetInput("LandR")==36,"base style can change independently")
srv.editRoute(1,3,nil,nil,{curve=-40,width=6,arrowhead=true})
check(route.node:GetInput("NativeRouteCurve")==-40 and
      route.node:GetInput("NativeRouteWidth")==6,"route edited without reconstruction")
check(route.node.frames.RouteProgress[12]==1,
      "editing route preserves existing animation keys")
srv.moveObject(1,3,-1)
check(srv.objects(1)[2].meta.type=="Route" and
      srv.objects(1)[3].meta.name=="Rio de Janeiro",
      "object z-order rewire preserves typed identity")
srv.renameObject(1,3,"Rio state highlighted")
check(srv.objects(1)[3].meta.name=="Rio state highlighted",
      "object display name changes without geographic key changes")
srv.duplicateObject(1,1)
check(#srv.objects(1)==4 and srv.objects(1)[4].meta.type=="Region",
      "object duplicates into separate layer and metadata")
srv.delete(1,3)
check(#srv.objects(1)==3,"delete affects selected object only")
check(#srv.scenes()==1,"no extra host scene created by object operations")
print("PASS: v1 single-scene, typed search, independent styles, camera, routes, safety")
