-- CartoRig Scene — Fusion-only single window.
-- Requires DaVinci Resolve Studio 20 Fusion UIManager; no Edit-page scripting.
-- This UI is deliberately thin: all mutations go through scene.lua, and each
-- action re-reads the active composition to prevent cross-comp writes.
local script=assert(debug.getinfo(1,"S").source)
assert(script:sub(1,1)=="@","Launch CartoRig Scene from Fusion > Scripts")
local directory=assert(script:sub(2):match("^(.*[\\/])"))
local scene=assert(loadfile(directory.."CartoRigSupport/scene.lua"))()
local treeModel=assert(loadfile(directory.."CartoRigSupport/scene_tree.lua"))()
local fusion=_G.fu or _G.fusion or
    (bmd and bmd.scriptapp and bmd.scriptapp("Fusion"))
assert(fusion and fusion.UIManager and bmd and bmd.UIDispatcher,
       "CartoRig Scene requires the Fusion UIManager")
local ui=fusion.UIManager
-- One editor window per process; repeated script invocation must not create
-- duplicate notification subscriptions or competing Scene controllers.
if _G.CARTORIG_SCENE_WINDOW_RUNNING then
    local old=nil
    if type(ui.FindWindow)=="function" then
        pcall(function()old=ui:FindWindow("CartoRigSceneWindow")end)
    end
    if old and type(old.Raise)=="function" then
        pcall(function()old:Show();old:Raise()end)
    end
    return
end
local dispatcher=bmd.UIDispatcher(ui)
local window=dispatcher:AddWindow({
    ID="CartoRigSceneWindow",WindowTitle="CartoRig — Scene",
    Geometry={140,80,470,655},Spacing=7,Margin=12
},ui:VGroup{
    ID="Root",Spacing=8,
    ui:HGroup{
        ui:Label{ID="Context",Text="Current composition: checking...",Weight=0.75},
        ui:Button{ID="Refresh",Text="Refresh",Weight=0.25}
    },
    ui:HGroup{
        ui:Button{ID="Initialize",Text="Initialize Scene",Weight=0.42},
        ui:Button{ID="ConnectOutput",Text="Connect Output",Weight=0.32},
        ui:Button{ID="Reveal",Text="Reveal node",Weight=0.26}
    },
    ui:Label{Text="SEARCH OFFLINE LOCATIONS"},
    ui:HGroup{
        ui:LineEdit{ID="Search",PlaceholderText="Country, state, city...",Weight=0.64},
        ui:ComboBox{ID="Type",Weight=0.22},
        ui:Button{ID="Find",Text="Find",Weight=0.14}
    },
    ui:ComboBox{ID="Results"},
    ui:HGroup{
        ui:Button{ID="AddRegion",Text="Add Region"},
        ui:Button{ID="AddMarker",Text="Add Marker"},
        ui:Button{ID="Focus",Text="Focus"},
        ui:Button{ID="Fit",Text="Fit"}
    },
    ui:HGroup{
        ui:LineEdit{ID="LabelText",PlaceholderText="Label text (default: place name)",Weight=0.63},
        ui:Button{ID="AddLabel",Text="+ Label",Weight=0.20},
        ui:Button{ID="CustomMarker",Text="+ Point",Weight=0.17}
    },
    ui:Label{Text="SCENE OBJECTS — select to edit Control | Motion in Fusion"},
    ui:Tree{ID="ObjectTree",ColumnCount=3,HeaderHidden=false,
            SortingEnabled=false,RootIsDecorated=true,
            SelectionMode="ExtendedSelection",Weight=1.4,
            Events={ItemSelectionChanged=true,ItemActivated=true}},
    ui:HGroup{
        ui:Button{ID="Select",Text="Select"},
        ui:Button{ID="Show",Text="Show"},
        ui:Button{ID="Hide",Text="Hide"},
        ui:Button{ID="Lock",Text="Lock"},
        ui:Button{ID="Unlock",Text="Unlock"}
    },
    ui:HGroup{
        ui:Button{ID="MoveUp",Text="Move Up"},
        ui:Button{ID="MoveDown",Text="Move Down"},
        ui:Button{ID="CreateGroup",Text="+ Group"},
        ui:Button{ID="Ungroup",Text="Ungroup"}
    },
    ui:HGroup{
        ui:ComboBox{ID="Groups",Weight=0.60},
        ui:Button{ID="SetGroup",Text="Move into Group",Weight=0.40}
    },
    ui:HGroup{
        ui:LineEdit{ID="RenameValue",PlaceholderText="Rename object",Weight=0.42},
        ui:Button{ID="Rename",Text="Rename",Weight=0.17},
        ui:Button{ID="Duplicate",Text="Duplicate",Weight=0.22},
        ui:Button{ID="Delete",Text="Delete",Weight=0.19}
    },
    ui:TabBar{ID="AuthoringTabs"},
    ui:Stack{ID="AuthoringStack",CurrentIndex=0,
        ui:VGroup{ID="ObjectPanel",
            ui:Label{Text="Select a tree object to edit its native Control / Motion tabs."}
        },
        ui:VGroup{ID="RoutePanel",
        ui:Label{Text="ROUTE — explicit point coordinates; never assume a region centroid"},
        ui:HGroup{
            ui:Label{Text="Origin lon",Weight=0.18},
            ui:LineEdit{ID="FromLon",PlaceholderText="-47.8828",Weight=0.32},
            ui:Label{Text="Origin lat",Weight=0.17},
            ui:LineEdit{ID="FromLat",PlaceholderText="-15.7939",Weight=0.33}
        },
        ui:HGroup{
            ui:Label{Text="Target lon",Weight=0.18},
            ui:LineEdit{ID="ToLon",PlaceholderText="-51.3000",Weight=0.32},
            ui:Label{Text="Target lat",Weight=0.17},
            ui:LineEdit{ID="ToLat",PlaceholderText="0.7000",Weight=0.33}
        },
        ui:HGroup{
            ui:Label{Text="Route waypoints",Weight=0.29},
            ui:ComboBox{ID="Waypoints",Weight=0.71}
        },
        ui:HGroup{
            ui:LineEdit{ID="WayLon",PlaceholderText="Waypoint lon",Weight=0.24},
            ui:LineEdit{ID="WayLat",PlaceholderText="Waypoint lat",Weight=0.24},
            ui:Button{ID="AddWaypoint",Text="Add",Weight=0.12},
            ui:Button{ID="WayUp",Text="Up",Weight=0.10},
            ui:Button{ID="WayDown",Text="Down",Weight=0.10},
            ui:Button{ID="WayRemove",Text="Remove",Weight=0.13}
        },
        ui:Button{ID="ReverseRoute",Text="Reverse selected Route (keep styles and curves)"},
        ui:HGroup{
            ui:Button{ID="UseFrom",Text="Origin from result"},
            ui:Button{ID="UseTo",Text="Target from result"},
            ui:Button{ID="AddRoute",Text="Add Route"}
        },
        }
    },
    ui:HGroup{
        ui:Button{ID="InspectScene",Text="Inspect",Weight=0.16},
        ui:Button{ID="RecoverCopy",Text="Recover copy",Weight=0.22},
        ui:Label{ID="Status",Text="Status: Ready.",WordWrap=true,Weight=0.42},
        ui:Button{ID="Copy",Text="Copy diagnostics",Weight=0.20}
    },
    ui:HGroup{
        ui:Label{Text="Offline · Fusion-only · no independent timeline",Weight=0.72},
        ui:Button{ID="Close",Text="Close",Weight=0.28}
    }
})
local item=window:GetItems()
item.AuthoringTabs:AddTab("Objects")
item.AuthoringTabs:AddTab("Route")
item.AuthoringTabs.CurrentIndex=0
item.AuthoringStack.CurrentIndex=0
local choices,objects,groups={},{},{}
local treeIds,treeRows={},{}
local rendering=false
local context=nil
local locked=false
local pendingDelete=nil
local pendingRecovery=nil
local kinds={"all","continent","country","state","city"}
local function setItems(widget,texts)
    widget:Clear()
    if #texts>0 then widget:AddItems(texts);widget.CurrentIndex=0 end
end
setItems(item.Type,{"All","Continent","Country","State / Province","City"})
local function currentIndex(widget)
    local index=tonumber(widget.CurrentIndex)
    if not index or index<0 then error("Choose an item before continuing")end
    return index+1
end
local function selectedResult()
    local loc=choices[currentIndex(item.Results)]
    if not loc then error("Search and select a location first")end
    return loc
end
local function selectedIds()
    local selected=item.ObjectTree:SelectedItems() or {}
    local ids,seen={},{}
    for _,row in pairs(selected) do
        local id=treeIds[row]
        if id and not seen[id] then ids[#ids+1]=id;seen[id]=true end
    end
    return ids
end
local function selectedObject()
    local ids=selectedIds()
    if #ids~=1 then
        error("Select exactly one CartoRig object for this action")
    end
    for _,entry in ipairs(objects) do
        if entry.id==ids[1] then return entry end
    end
    error("Selected object no longer exists in this composition")
end
local function compositionKey()
    local comp=scene.composition()
    local attrs=comp:GetAttrs() or {}
    local display=tostring(attrs.COMPS_Name or attrs.COMPS_FileName or "Untitled")
    return comp,tostring(comp),display
end
local function verifyContext()
    local comp,key=compositionKey()
    if context~=key then
        -- Fail closed: do not edit the last selected object from another comp.
        choices={};objects={};groups={}
        treeIds={};treeRows={}
        setItems(item.Results,{})
        item.ObjectTree:Clear()
        context=nil
        item.Context.Text="WRONG_CONTEXT: refresh active composition"
        error("Active composition changed. Refresh before any edit.")
    end
    if scene.state(comp)=="SCENE_BROKEN" then
        error("SCENE_BROKEN: inspect diagnostics; editing is disabled")
    end
    return comp
end
local function refresh()
    local active,comp,key,name=pcall(compositionKey)
    if not active then
        context=nil;pendingDelete=nil;pendingRecovery=nil
        choices={};objects={};groups={}
        treeIds={};treeRows={}
        item.ObjectTree:Clear()
        setItems(item.Results,{})
        setItems(item.Groups,{})
        item.Context.Text="NO_COMP — open a Fusion Composition"
        for _,name in ipairs({"Initialize","ConnectOutput","AddRegion",
            "AddMarker","AddLabel","AddRoute","Focus","Fit","Select",
            "Show","Hide","Lock","Unlock","Delete","Duplicate",
            "CreateGroup","SetGroup","Ungroup","Rename"}) do
            pcall(function()item[name].Enabled=false end)
        end
        return "NO_COMP: open a Fusion composition, then Refresh Scene."
    end
    context=key
    pendingDelete=nil
    pendingRecovery=nil
    local snapshot=scene.snapshot(comp)
    local state=snapshot.state
    item.Context.Text="Composition: "..name.." ["..state.."]"
    local preserve={}
    for _,id in ipairs(selectedIds())do preserve[id]=true end
    if next(preserve)==nil and snapshot.selection.state=="CARTORIG" then
        preserve[snapshot.selection.id]=true
    end
    objects=snapshot.objects
    local tree=item.ObjectTree
    rendering=true
    tree:Clear()
    treeIds={};treeRows={}
    tree.ColumnCount=3
    tree:SetHeaderLabels({"Scene object","Draw order","Status"})
    local function createNode(node,parent)
        if node.kind=="category" and #node.children==0 then return end
        local row=tree:NewItem()
        row.Text[0]=node.name
        if node.kind=="object" or node.kind=="group" then
            row.Text[1]=node.z and tostring(node.z) or ""
            row.Text[2]=(node.visible==false and "Hidden " or "")..
                        (node.locked and "Locked" or "")
            treeIds[row]=node.id;treeRows[node.id]=row
            if preserve[node.id] then row.Selected=true end
        else
            row.Text[1]="";row.Text[2]=""
        end
        if parent then parent:AddChild(row)
        else tree:AddTopLevelItem(row)end
        for _,child in ipairs(node.children or {})do createNode(child,row)end
        if node.kind=="category" or node.kind=="group" then row.Expanded=true end
    end
    if state=="SCENE_READY" or state=="SCENE_EMPTY" then
        for _,node in ipairs(treeModel.build(objects))do createNode(node,nil)end
    end
    rendering=false
    groups={}
    local groupLabels={"Select destination group..."}
    for _,entry in ipairs(objects)do
        if entry.role=="Group" then
            groups[#groups+1]=entry
            groupLabels[#groupLabels+1]=entry.name
        end
    end
    setItems(item.Groups,groupLabels)
    -- Disable dangerous actions while uninitialized or corrupt. The backend
    -- independently rechecks state, so a stale UI cannot bypass this guard.
    local canEdit=(state=="SCENE_READY" or state=="SCENE_EMPTY")
    local controls={"AddRegion","AddMarker","AddLabel","CustomMarker",
        "Focus","Fit","ConnectOutput","Show","Hide","Lock","Unlock",
        "MoveUp","MoveDown","CreateGroup","SetGroup","Ungroup","Rename",
        "Duplicate","Delete","UseFrom","UseTo","AddRoute","AddWaypoint",
        "WayUp","WayDown","WayRemove","ReverseRoute","Select","Reveal"}
    for _,name in ipairs(controls) do
        pcall(function()item[name].Enabled=canEdit end)
    end
    pcall(function()item.Initialize.Enabled=state=="COMP_WITHOUT_CARTORIG"end)
    pcall(function()item.RecoverCopy.Enabled=state=="SCENE_BROKEN"end)
    if state=="SCENE_BROKEN" then
        return "SCENE_BROKEN: inspect diagnostics; authoring disabled."
    end
    if snapshot.selection.state=="NON_CARTORIG" then
        return "Non-CartoRig selection: select a Scene object before editing."
    end
    return tostring(#objects).." CartoRig objects · "..state
end
local function perform(action)
    if locked then return end
    locked=true
    item.Status.Text="Working..."
    local ok,result=pcall(action)
    if ok then
        item.Status.Text="Status: "..tostring(result or "Applied.")
    else
        item.Status.Text="Not applied: "..tostring(result)
        print("[CartoRig Scene] "..tostring(result))
    end
    locked=false
end
perform(refresh)
function window.On.AuthoringTabs.CurrentChanged(_)
    local index=tonumber(item.AuthoringTabs.CurrentIndex)or 0
    item.AuthoringStack.CurrentIndex=math.max(0,math.min(1,index))
end
function window.On.Refresh.Clicked(_)
    perform(refresh)
end
function window.On.Initialize.Clicked(_)
    perform(function()
        verifyContext()
        local created,message=scene.initialize()
        refresh()
        return message or (created and "Initialized." or "Already initialized.")
    end)
end
function window.On.ConnectOutput.Clicked(_)
    perform(function()
        verifyContext()
        return scene.connectOutput()
    end)
end
function window.On.Find.Clicked(_)
    perform(function()
        verifyContext()
        local kind=kinds[currentIndex(item.Type)]
        choices=scene.search(item.Search.Text,kind)
        local labels={}
        for _,loc in ipairs(choices) do
            labels[#labels+1]=loc.name.." · "..loc.kind..
                (loc.parent~="" and (" · "..loc.parent) or "")..
                (loc.geometry and (" ["..loc.geometry.."]") or "")
        end
        setItems(item.Results,labels)
        if #choices==0 then
            return "Location not found in bundled data. Try another spelling or category."
        end
        return #choices.." results. Select a location and choose an explicit action."
    end)
end
function window.On.AddRegion.Clicked(_)
    perform(function()
        verifyContext()
        local loc=selectedResult()
        if loc.kind=="city"then error("Only a point is available for this city; use Marker")end
        local id=scene.addRegion(loc)
        refresh()
        return "Added Region "..loc.name.." ("..id..")"
    end)
end
function window.On.AddMarker.Clicked(_)
    perform(function()
        verifyContext()
        local loc=selectedResult()
        local id=scene.addMarker(loc)
        refresh()
        return "Added Marker "..loc.name.." ("..id..")"
    end)
end
function window.On.AddLabel.Clicked(_)
    perform(function()
        verifyContext()
        local loc=selectedResult()
        local text=tostring(item.LabelText.Text or "")
        if text=="" then text=loc.name end
        local id=scene.addLabel(loc,text)
        refresh()
        return "Added independent georeferenced Label ("..id..")"
    end)
end
function window.On.CustomMarker.Clicked(_)
    perform(function()
        verifyContext()
        local lon,lat=item.FromLon.Text,item.FromLat.Text
        local id=scene.addCustomPoint(lon,lat,"Custom Point")
        refresh()
        return "Added manually chosen geographic point ("..id..")"
    end)
end
function window.On.Focus.Clicked(_)
    perform(function()
        verifyContext()
        scene.focus(selectedResult(),false)
        return "Camera focused without keyframes."
    end)
end
function window.On.Fit.Clicked(_)
    perform(function()
        verifyContext()
        scene.focus(selectedResult(),true)
        return "Static camera fitted. No Motion or keyframe was created."
    end)
end
local function chooseObject(operation)
    verifyContext()
    local entry=selectedObject()
    if entry.locked and operation~="unlock" and operation~="select" then
        error("This object is locked.")
    end
    return entry
end
function window.On.Select.Clicked(_)
    perform(function()
        local o=chooseObject("select")
        scene.select(o.id)
        return "Selected "..o.name..". Open the native Control / Motion Inspector tabs."
    end)
end
function window.On.Reveal.Clicked(_)
    perform(function()
        local o=chooseObject("select")
        scene.select(o.id)
        return "Node selected: "..o.name
    end)
end
local function batchAction(action)
    verifyContext()
    local ids=selectedIds()
    if #ids==0 then error("Select CartoRig objects in the Scene tree") end
    local count=scene.batch(action,ids)
    refresh()
    return count.." object(s): "..action.." — one Fusion Undo unit."
end
function window.On.Show.Clicked(_)
    perform(function()return batchAction("show")end)
end
function window.On.Hide.Clicked(_)
    perform(function()return batchAction("hide")end)
end
function window.On.Lock.Clicked(_)
    perform(function()return batchAction("lock")end)
end
function window.On.Unlock.Clicked(_)
    perform(function()return batchAction("unlock")end)
end
function window.On.MoveUp.Clicked(_)
    perform(function()
        local o=chooseObject("move")
        scene.move(o.id,-1)
        refresh()
        return "Draw order moved one position up."
    end)
end
function window.On.MoveDown.Clicked(_)
    perform(function()
        local o=chooseObject("move")
        scene.move(o.id,1)
        refresh()
        return "Draw order moved one position down."
    end)
end
function window.On.CreateGroup.Clicked(_)
    perform(function()
        verifyContext()
        local name=tostring(item.RenameValue.Text or "")
        if name=="" then name="New Group" end
        scene.addGroup(name)
        refresh()
        return "New organizational group. No extra render layer."
    end)
end
function window.On.SetGroup.Clicked(_)
    perform(function()
        verifyContext()
        local ids=selectedIds()
        local group=groups[(tonumber(item.Groups.CurrentIndex) or -1)]
        if not group then error("Choose a destination group")end
        local count=scene.groupMany(ids,group.id)
        refresh()
        return count.." object(s) placed into "..group.name..
               " without changing global draw order."
    end)
end
function window.On.Ungroup.Clicked(_)
    perform(function()
        local o=chooseObject("ungroup")
        if o.role~="Group" then error("Select an organizational Group") end
        scene.ungroup(o.id)
        refresh()
        return "Group removed. All authored children preserved."
    end)
end
function window.On.Rename.Clicked(_)
    perform(function()
        local o=chooseObject("rename")
        scene.rename(o.id,item.RenameValue.Text)
        refresh()
        return "Object renamed without changing publisher feature ID."
    end)
end
function window.On.Duplicate.Clicked(_)
    perform(function()
        local object=chooseObject("duplicate")
        local id=scene.duplicate(object.id)
        refresh()
        return "Native Fusion settings and animation copied to new object "..id
    end)
end
function window.On.Delete.Clicked(_)
    perform(function()
        verifyContext()
        local ids=selectedIds()
        if #ids==0 then error("Select objects to delete")end
        table.sort(ids)
        local fingerprint=context..":"..table.concat(ids,"|")
        if pendingDelete~=fingerprint then
            pendingDelete=fingerprint
            return "Confirm Delete ("..#ids.." object(s)): click Delete again "..
                   "or press Escape to cancel. Undo remains available."
        end
        pendingDelete=nil
        return batchAction("delete")
    end)
end
local function coords(lon,lat)
    lon=tonumber(lon);lat=tonumber(lat)
    if not lon or not lat then return nil end
    if lon<-180 or lon>180 or lat<-85 or lat>85 then
        error("Coordinates must be valid WGS84 longitude/latitude")
    end
    return {lon=lon,lat=lat}
end
local function pointFrom(loc)
    if loc.kind~="city" or not loc.bounds then
        error("Choose a city point, or specify a manual coordinate inside the region.")
    end
    return {lon=(loc.bounds[1]+loc.bounds[3])/2,
            lat=(loc.bounds[2]+loc.bounds[4])/2}
end
local function updateWaypoints()
    local object=selectedObject()
    local labels={}
    if object.role=="Route" then
        for index,point in ipairs(scene.waypoints(object.id)) do
            labels[#labels+1]=string.format("%02d | %.6f, %.6f",
                                          index,point.lon,point.lat)
        end
    end
    setItems(item.Waypoints,labels)
    return "Route waypoints refreshed."
end
function window.On.ObjectTree.ItemSelectionChanged(_)
    if locked or rendering then return end
    pendingDelete=nil
    perform(function()
        verifyContext()
        local ids=selectedIds()
        if #ids==1 then
            local entry=scene.select(ids[1])
            if entry.role=="Route" then updateWaypoints()
            else setItems(item.Waypoints,{}) end
            return "Selected "..entry.name.." — Inspector Control | Motion."
        end
        setItems(item.Waypoints,{})
        return #ids.." objects selected. Use batch Hide, Lock, Group or Delete."
    end)
end
function window.On.ObjectTree.ItemActivated(_)
    if locked or rendering then return end
    perform(function()
        verifyContext()
        local entry=selectedObject()
        scene.select(entry.id)
        return "Inspector target: "..entry.name
    end)
end
local function activeRoute()
    local object=chooseObject("route")
    if object.role~="Route" then
        error("Select an existing Route in Scene Objects")
    end
    return object
end
function window.On.AddWaypoint.Clicked(_)
    perform(function()
        local route=activeRoute()
        scene.addWaypoint(route.id,item.WayLon.Text,item.WayLat.Text)
        updateWaypoints()
        return "Waypoint added; route geometry updated without new keyframes."
    end)
end
function window.On.WayUp.Clicked(_)
    perform(function()
        local route=activeRoute()
        scene.moveWaypoint(route.id,currentIndex(item.Waypoints),-1)
        updateWaypoints()
        return "Waypoint moved up."
    end)
end
function window.On.WayDown.Clicked(_)
    perform(function()
        local route=activeRoute()
        scene.moveWaypoint(route.id,currentIndex(item.Waypoints),1)
        updateWaypoints()
        return "Waypoint moved down."
    end)
end
function window.On.WayRemove.Clicked(_)
    perform(function()
        local route=activeRoute()
        scene.removeWaypoint(route.id,currentIndex(item.Waypoints))
        updateWaypoints()
        return "Waypoint removed, other objects preserved."
    end)
end
function window.On.ReverseRoute.Clicked(_)
    perform(function()
        local route=activeRoute()
        scene.reverseRoute(route.id)
        updateWaypoints()
        return "Route endpoints and ordered waypoints reversed."
    end)
end
function window.On.UseFrom.Clicked(_)
    perform(function()
        local p=pointFrom(selectedResult())
        item.FromLon.Text=tostring(p.lon);item.FromLat.Text=tostring(p.lat)
        return "Origin uses the official city coordinate."
    end)
end
function window.On.UseTo.Clicked(_)
    perform(function()
        local p=pointFrom(selectedResult())
        item.ToLon.Text=tostring(p.lon);item.ToLat.Text=tostring(p.lat)
        return "Destination uses the official city coordinate."
    end)
end
function window.On.AddRoute.Clicked(_)
    perform(function()
        verifyContext()
        local a=coords(item.FromLon.Text,item.FromLat.Text)
        local b=coords(item.ToLon.Text,item.ToLat.Text)
        if not a or not b then
            error("Select a specific origin and destination coordinate.")
        end
        local id=scene.addRoute(a,b)
        refresh()
        return "Added georeferenced Route "..id..
            ". Draw animation is optional in the native Motion tab."
    end)
end
-- Shortcuts are consumed only when the Scene tree actually owns keyboard focus.
-- Qt::Key numeric codes are used alongside UIManager string variants.
function window.On.CartoRigSceneWindow.KeyPress(ev)
    local focused=false
    pcall(function()focused=item.ObjectTree:HasFocus()end)
    if not focused then return end
    local key=ev and ev.Key
    if key=="Key_Escape" or key=="Escape" or key==16777216 then
        pendingDelete=nil
        item.Status.Text="Operation cancelled; no Scene objects changed."
    elseif key=="Key_F2" or key=="F2" or key==16777265 then
        perform(function()
            local entry=selectedObject()
            item.RenameValue.Text=entry.name
            pcall(function()item.RenameValue:SetFocus("OtherFocusReason")end)
            return "Rename "..entry.name.." and click Rename to commit."
        end)
    elseif key=="Key_Delete" or key=="Delete" or key==16777223 then
        window.On.Delete.Clicked({})
    elseif key=="Key_D" or key=="D" or key==68 then
        local modifier=ev and ev.Modifiers
        local ctrl=(modifier=="ControlModifier" or modifier=="Ctrl" or
            (type(modifier)=="number" and
             math.floor(modifier/67108864)%2==1))
        if ctrl then window.On.Duplicate.Clicked({})end
    end
end
function window.On.Search.ReturnPressed(_)
    window.On.Find.Clicked({})
end
function window.On.Results.Activated(_)
    perform(function()
        local loc=selectedResult()
        if loc.geometry=="Point" then
            return loc.name..": Add Marker, Focus Camera, or use as Route endpoint."
        elseif loc.geometry=="Polygon" then
            return loc.name..": Add Region or Focus Camera."
        end
        return loc.name..": inspect available geography actions."
    end)
end
function window.On.InspectScene.Clicked(_)
    perform(function()
        local report=scene.inspect()
        if #report.issues==0 then
            return "Scene integrity: "..report.state.."; no issues detected."
        end
        return report.state.." ("..#report.issues.." issue(s)): "..
               report.issues[1]..". Copy diagnostics for the complete report."
    end)
end
function window.On.RecoverCopy.Clicked(_)
    perform(function()
        local comp,key=compositionKey()
        if key~=context then
            error("WRONG_CONTEXT: refresh before starting recovery")
        end
        local report=scene.inspect(comp)
        if report.state~="SCENE_BROKEN" then
            error("Recover Copy is only available for a damaged Scene")
        end
        if pendingRecovery~=key then
            pendingRecovery=key
            return "Recovery will create a NEW unlinked Fusion composition. "..
                   "Click Recover copy again to confirm; original will remain unchanged."
        end
        pendingRecovery=nil
        local result=scene.recoverCopy()
        -- NewComp may activate a different composition; require explicit
        -- Refresh and object reselection before any further edit.
        context=nil
        choices={};objects={};groups={}
        item.ObjectTree:Clear()
        treeIds={};treeRows={}
        return result.warning.." Missing authored nodes: "..result.missing
    end)
end
function window.On.Copy.Clicked(_)
    perform(function()
        local report=scene.diagnosticsText()
        if not bmd or not bmd.setclipboard then
            return "Clipboard API unavailable. Inspect scene to view diagnostics."
        end
        bmd.setclipboard(report)
        return "Scene diagnostics copied. No private project paths included."
    end)
end
function window.On.Close.Clicked(_)dispatcher:ExitLoop()end
function window.On.CartoRigSceneWindow.Close(_)dispatcher:ExitLoop()end
-- Event-based Node Editor -> Scene synchronization; no frame-polling timer.
-- Notification handles are strongly retained and removed on window close.
local notifications={}
local function clearTreeSelection()
    rendering=true
    for _,row in pairs(treeRows) do row.Selected=false end
    rendering=false
end
local function syncFromNodeEditor()
    if locked or rendering then return end
    local ok,comp,key=pcall(function()
        local active,identity=compositionKey()
        return active,identity
    end)
    if not ok then
        item.Status.Text="NO_COMP: open a Fusion composition and refresh."
        return
    end
    if key~=context then
        clearTreeSelection()
        choices={};objects={};groups={}
        item.ObjectTree:Clear()
        treeIds={};treeRows={}
        item.Status.Text="WRONG_CONTEXT: active composition changed. Refresh Scene."
        return
    end
    local selection=scene.selectedInHost(comp)
    clearTreeSelection()
    if selection.state=="CARTORIG" and treeRows[selection.id] then
        rendering=true
        treeRows[selection.id].Selected=true
        rendering=false
        item.Status.Text="Node Editor -> Scene: "..selection.nodeName
    elseif selection.state=="NON_CARTORIG" then
        item.Status.Text="Non-CartoRig selection: choose a Scene object."
    else
        item.Status.Text="No active Fusion tool."
    end
end
local function watch(event,callback)
    if not (ui.AddNotify and ui.RemoveNotify) then return false end
    local ok,handle=pcall(function()return ui:AddNotify(event)end)
    if not ok or not handle then return false end
    notifications[#notifications+1]={event=event,handle=handle}
    dispatcher.On[event]=callback
    return true
end
watch("Comp_Activate_Tool",function(_)syncFromNodeEditor()end)
watch("AddTool",function(_)
    if not locked and not rendering then
        perform(refresh)
    end
end)
watch("DeleteTool",function(_)
    if not locked and not rendering then
        perform(refresh)
    end
end)
_G.CARTORIG_SCENE_WINDOW_RUNNING=true
local ok,why=pcall(function()
    window:Show()
    dispatcher:RunLoop()
end)
pcall(function()window:Hide()end)
for _,notice in ipairs(notifications)do
    pcall(function()ui:RemoveNotify(notice.event)end)
end
notifications={}
_G.CARTORIG_SCENE_WINDOW_RUNNING=nil
if not ok then error("CartoRig Scene UI failed: "..tostring(why))end

