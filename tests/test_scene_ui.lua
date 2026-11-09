-- UIManager host mock exercising the actual Scene script and Tree events.
-- This is NOT a DaVinci Resolve Studio 20 GUI proof.
local function check(x,msg)if not x then error("FAIL UI "..msg,2)end end
local script="fusion/CartoRig Scene.lua"
local root="build/mock-geo-catalog"
os.execute("mkdir -p "..root)
local file=assert(io.open(root.."/catalog.tsv","wb"))
file:write("id\tkind\tname\tparent\taliases\tminx\tminy\tmaxx\tmaxy\toffset\tbytes\n")
file:write("ne_10m_admin_0_countries:1\tcountry\tBrazil\tSouth America\tbrazil|brasil\t-74\t-34\t-34\t6\t8\t99\n")
file:write("ne_10m_admin_1_states_provinces:22\tstate\tRio de Janeiro\tBrazil\trio de janeiro\t-45\t-25\t-40\t-20\t107\t88\n")
file:close()
local manifest=assert(io.open(root.."/manifest.json","wb"))
manifest:write('{"format":"CRG1","geometry_sha256":"'..string.rep("a",64)..'"}')
manifest:close()
_G.CARTORIG_TEST_DATA=root
local T={}
T.__index=function(t,key)
 if T[key] then return T[key] end
 t.inputs[key]=t.inputs[key] or
     {SetExpression=function(self,expression)self.expression=expression;return true end}
 return t.inputs[key]
end
function T.new(kind)
 return setmetatable({kind=kind,name=kind,inputs={},data={},values={},
                      deleted=false},T)
end
function T:GetAttrs()return {TOOLS_Name=self.name} end
function T:SetAttrs(p)self.name=p.TOOLS_Name;return true end
function T:GetData(k)return self.data[k] end
function T:SetData(k,v)self.data[k]=v;return true end
function T:SetInput(k,v)self.values[k]=v;return true end
function T:GetInput(k)return self.values[k] end
function T:ConnectInput(k,up)
 if not up then return false end
 self.values[k]=up
 return true
end
function T:Delete()self.deleted=true;return true end
local C={}
C.__index=C
function C.new(name)
 local c=setmetatable({nodes={},name=name,undos=0},C)
 local out=T.new("MediaOut");out.name="MediaOut1"
 out.Input={GetConnectedOutput=function()return out.values.Input end}
 c.nodes[1]=out
 return c
end
function C:GetToolList(selected)
 if selected then return self.ActiveTool and {self.ActiveTool} or {} end
 local all={}
 for _,tool in ipairs(self.nodes)do
  if not tool.deleted then all[#all+1]=tool end
 end
 return all
end
function C:FindTool(name)
 for _,tool in ipairs(self:GetToolList(false))do
  if tool.name==name then return tool end
 end
end
function C:FindToolByID(name)
 for _,tool in ipairs(self:GetToolList(false))do
  if tool.kind==name then return tool end
 end
end
function C:AddTool(name)
 local tool=T.new(name)
 self.nodes[#self.nodes+1]=tool
 return tool
end
function C:StartUndo()self.undos=self.undos+1;return true end
function C:EndUndo()return true end
function C:SetActiveTool(tool)self.ActiveTool=tool;return true end
function C:GetAttrs()return {COMPS_Name=self.name} end
local compA=C.new("Composition-A")
local compB=C.new("Composition-B")
local comp=compA
_G.comp=compA
local notices={}
local active={}
local ui={}
setmetatable(ui,{__index=function(_,kind)
 return function(self,props)
  props=props or {}
  props.__kind=kind
  return props
 end
end})
function ui:AddNotify(event)
 notices[event]=(notices[event] or 0)+1
 return {event=event}
end
function ui:RemoveNotify(event)
 notices[event]=(notices[event] or 0)-1
end
local function treeWidget(spec)
 local t={roots={},ColumnCount=spec.ColumnCount,columns={}}
 function t:Clear()self.roots={}end
 function t:SetHeaderLabels(values)self.columns=values end
 function t:NewItem()
  local child={Text={},Selected=false,Expanded=false,children={}}
  function child:AddChild(item)self.children[#self.children+1]=item end
  return child
 end
 function t:AddTopLevelItem(row)self.roots[#self.roots+1]=row end
 function t:HasFocus()return true end
 function t:SelectedItems()
  local all={}
  local function visit(row)
   if row.Selected then all[#all+1]=row end
   for _,kid in ipairs(row.children)do visit(kid)end
  end
  for _,root in ipairs(self.roots)do visit(root)end
  return all
 end
 return t
end
local function widget(spec)
 if spec.__kind=="Tree" then return treeWidget(spec) end
 local w={Text=spec.Text or "",CurrentIndex=0}
 function w:Clear()self.entries={};self.CurrentIndex=-1 end
 function w:AddItems(values)self.entries=values end
 function w:HasFocus()return false end
 return w
end
local currentDispatcher
local visited=0
local function makeDispatcher(_)
 local d={On=setmetatable({},{__index=function(t,k)
  local v={};rawset(t,k,v);return v end})}
 function d:AddWindow(props,layout)
  local all={}
  local function collect(x)
   if type(x)~="table" then return end
   if x.ID then all[x.ID]=widget(x)end
   for _,v in ipairs(x)do collect(v)end
  end
  collect(layout)
  local win={On=setmetatable({},{__index=function(t,k)
   local v={};rawset(t,k,v);return v end})}
  function win:GetItems()return all end
  function win:Show()end
  function win:Hide()end
  d.window=win;d.items=all
  return win
 end
 function d:ExitLoop()self.exited=true end
 function d:RunLoop()
  visited=visited+1
  local window=self.window
  local w=self.items
  local tree=w.ObjectTree
  check(tree~=nil and tree.columns[1]=="Scene object",
        "native Tree widget initialized")
  check(w.Status.Text:find("COMP_WITHOUT_CARTORIG")~=nil,
        "uninitialized composition gets context feedback")
  if visited==1 then
   window.On.Initialize.Clicked({})
   local names={}
   for _,node in ipairs(compA:GetToolList(false))do
    names[#names+1]=node.name
   end
   check(compA:FindTool("CR_Base_Map")~=nil,
         "Scene initialized from window: "..tostring(w.Status.Text)..
         "; nodes="..table.concat(names,",")..
         "; active="..tostring(comp==compA))
   w.Search.Text="Brazil";w.Type.CurrentIndex=2
   window.On.Find.Clicked({})
   window.On.AddRegion.Clicked({})
   local region
   for _,t in ipairs(compA:GetToolList(false))do
    if t:GetData("CartoRig.Fusion.RC1.Role")=="Region"then region=t end
   end
   check(region~=nil,"Scene adds country Region")
   check(#tree.roots>=2,"native Tree has category hierarchy")
   local selected=tree:SelectedItems()
   check(#selected==1,"newly authored Region selected by stable ID")
   window.On.ObjectTree.ItemSelectionChanged({})
   check(compA.ActiveTool==region,"tree selection activates native inspector node")
   window.On.CartoRigSceneWindow.KeyPress({Key=16777265})
   check(w.RenameValue.Text=="Brazil","F2 puts selected object name in rename field")
   window.On.Delete.Clicked({})
   check(not region.deleted and w.Status.Text:find("Confirm Delete"),
         "first Delete only requests confirmation")
   window.On.CartoRigSceneWindow.KeyPress({Key=16777216})
   window.On.Delete.Clicked({})
   check(not region.deleted and w.Status.Text:find("Confirm Delete"),
         "Escape cancels pending deletion, next Delete requires new confirmation")
   local foreign=compA:AddTool("Blur")
   compA:SetActiveTool(foreign)
   d.On.Comp_Activate_Tool({Args={tool=foreign}})
   check(#tree:SelectedItems()==0 and
         w.Status.Text:find("Non%-CartoRig"),
         "external Node Editor selection clears stale Tree target")
   comp=compB
   d.On.Comp_Activate_Tool({Args={tool=nil}})
   check(w.Status.Text:find("WRONG_CONTEXT")~=nil,
         "composition switch is invalidated before user mutation")
   window.On.Delete.Clicked({})
   check(region.deleted~=true,"wrong-context Delete cannot alter old composition")
   window.On.Refresh.Clicked({})
   check(w.Context.Text:find("Composition%-B"),
         "user explicitly refreshes active composition")
  else
   check(w.Context.Text:find("COMP_WITHOUT_CARTORIG"),
         "reopening Scene keeps active composition state")
  end
  window.On.Close.Clicked({})
 end
 currentDispatcher=d
 return d
end
_G.fu={UIManager=ui,GetCurrentComp=function()return comp end}
_G.fusion=_G.fu
_G.bmd={UIDispatcher=makeDispatcher}
for cycle=1,20 do
 local ok,err=pcall(dofile,script)
 check(ok,"Scene script executes: "..tostring(err))
 for event,n in pairs(notices)do
  check(n==0,"every host notification released after closing Scene: "..event)
 end
 check(currentDispatcher.exited,"window dispatcher loop exits cleanly")
end
check(visited==20,"twenty open/close cycles exercised")
print("PASS Fusion UI mock: real Tree, Inspector selection, wrong context, no stale delete, 20 notification-clean lifecycles")
