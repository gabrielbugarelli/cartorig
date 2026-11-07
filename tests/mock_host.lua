-- Fake Fusion/Qt runtime: structural test only. Not real DaVinci Resolve.
local script = (arg and arg[1]) or "fusion/CartoRig Fusion-first POC.lua"
local nodes, metadata = {}, {}
local active, selected, undoCount
local Tool={};Tool.__index=Tool
function Tool:GetAttrs() return {TOOLS_RegID=self.ID} end
function Tool:SetAttrs(x) self.Name=x.TOOLS_Name or self.Name end
function Tool:SetData(k,v) self.data[k]=v end
function Tool:GetData(k) return self.data[k] end
function Tool:SetInput(k,v,t)
    self.inputs[k]=self.inputs[k] or {}
    self.inputs[k][t or "static"]=v
end
function Tool:ConnectInput(k,target) assert(target);self.links[k]=target;return true end
function Tool:AddModifier(k,name) assert(name=="BezierSpline");self.mods[k]=true;return true end
function Tool:Delete()
    for i,x in ipairs(nodes) do
        if x==self then table.remove(nodes,i);break end
    end
end
local function newTool(id,name)
    local t=setmetatable({ID=id,Name=name,data={},inputs={},links={},mods={}},Tool)
    nodes[#nodes+1]=t
    return t
end
newTool("MediaOut","MediaOut1")
local flow={Select=function(self,t) selected=t end}
local comp={CurrentTime=0, CurrentFrame={FlowView=flow}}
function comp:GetToolList() return nodes end
function comp:FindTool(n)
    for _,t in ipairs(nodes) do if t.Name==n then return t end end
end
function comp:GetData(k) return metadata[k] end
function comp:SetData(k,v) metadata[k]=v end
function comp:StartUndo(name) self.undoLabel=name end
function comp:EndUndo(success) assert(success==true);undoCount=(undoCount or 0)+1 end
function comp:SetActiveTool(t) active=t end
function comp:AddTool(id) return newTool(id,id.."__"..tostring(#nodes)) end

local ui=setmetatable({}, {__index=function(_,name) return function(_,props) return props end end})
local latest
local dispatcher={}
function dispatcher:AddWindow(attrs,layout)
    local items={}
    local function walk(x)
        if type(x)~="table" then return end
        if type(x.ID)=="string" then items[x.ID]=x end
        for _,v in pairs(x) do if type(v)=="table" then walk(v) end end
    end
    walk(layout)
    local tree=items.CRP_Objects
    function tree:Clear() self.rows={} end
    function tree:NewItem() return {Text={}} end
    function tree:AddTopLevelItem(item) self.rows[#self.rows+1]=item end
    function tree:CurrentItem() return self.chosen end
    local win={On=setmetatable({},{__index=function(t,k)
        local v={};rawset(t,k,v);return v
    end})}
    function win:GetItems() return items end
    function win:Show() end
    function win:Hide() end
    latest={win=win,items=items}
    return win
end
function dispatcher:ExitLoop() end
function dispatcher:RunLoop()
    local win,items=latest.win,latest.items
    local tree=items.CRP_Objects
    assert(#tree.rows==4,"object tree")
    local function click(i)
        tree.chosen=tree.rows[i]
        win.On.CRP_Objects.CurrentItemChanged({})
    end
    click(2) -- Brazil
    assert(active and active.Name=="CRP_Brazil")
    assert(selected==active,"Qt selection did not reach Flow")
    comp.CurrentTime=0;win.On.CRP_Red.Clicked({})
    comp.CurrentTime=329;win.On.CRP_Red.Clicked({})
    comp.CurrentTime=330;win.On.CRP_Green.Clicked({})
    local brazil=comp:FindTool("CRP_Brazil")
    assert(brazil.mods.TopLeftRed,"animated red input missing")
    assert(brazil.inputs.TopLeftRed[0]==0.79)
    assert(brazil.inputs.TopLeftRed[329]==0.79)
    assert(brazil.inputs.TopLeftRed[330]==0.12)
    click(3)
    comp.CurrentTime=200;win.On.CRP_Green.Clicked({})
    local rio=comp:FindTool("CRP_Rio")
    assert(rio.inputs.TopLeftGreen[200]==0.64)
    assert(brazil.inputs.TopLeftGreen[200]==nil,"keyframe leaked from Rio to Brazil")
    click(4)
    comp.CurrentTime=77;win.On.CRP_Zoom2.Clicked({})
    assert(comp:FindTool("CRP_Camera").inputs.Size[77]==1.3)
    win.On.CRP_Close.Clicked({})
end
_G.fusion={GetCurrentComp=function() return comp end, UIManager=ui}
_G.bmd={UIDispatcher=function(argUi) assert(argUi==ui);return dispatcher end}
assert(loadfile(script))()
assert(metadata["CartoRigPOC.Version"]=="0.1")
assert(#nodes==9,"unexpected node count: "..tostring(#nodes))
assert(comp:FindTool("MediaOut1").links.Input==comp:FindTool("CRP_Camera"))
assert(comp:FindTool("CRP_Camera").links.Input==comp:FindTool("CRP_RioComposite"))
local count=#nodes
assert(loadfile(script))()
assert(#nodes==count,"reopening duplicated nodes")
assert(undoCount>0)
print("PASS: mocked Fusion graph, tree selection, color keys, camera, reentry")
