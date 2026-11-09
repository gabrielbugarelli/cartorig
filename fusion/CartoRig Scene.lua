-- CartoRig Scene — Fusion-only single window.
-- Requires DaVinci Resolve Studio 20 Fusion UIManager; no Edit-page scripting.
-- This UI is deliberately thin: all mutations go through scene.lua, and each
-- action re-reads the active composition to prevent cross-comp writes.
local script=assert(debug.getinfo(1,"S").source)
assert(script:sub(1,1)=="@","Launch CartoRig Scene from Fusion > Scripts")
local directory=assert(script:sub(2):match("^(.*[\\/])"))
local scene=assert(loadfile(directory.."CartoRigSupport/scene.lua"))()
local fusion=_G.fu or _G.fusion or
    (bmd and bmd.scriptapp and bmd.scriptapp("Fusion"))
assert(fusion and fusion.UIManager and bmd and bmd.UIDispatcher,
       "CartoRig Scene requires the Fusion UIManager")
local ui=fusion.UIManager
local dispatcher=bmd.UIDispatcher(ui)
local window=dispatcher:AddWindow({
    ID="CartoRigSceneWindow",WindowTitle="CartoRig — Scene",
    Geometry={140,80,515,840},Spacing=7,Margin=12
},ui:VGroup{
    ID="Root",Spacing=8,
    ui:HGroup{
        ui:Label{ID="Context",Text="Current composition: checking...",Weight=0.75},
        ui:Button{ID="Refresh",Text="Refresh",Weight=0.25}
    },
    ui:HGroup{
        ui:Button{ID="Initialize",Text="Initialize CartoRig Scene",Weight=0.66},
        ui:Button{ID="Reveal",Text="Reveal node",Weight=0.34}
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
    ui:ComboBox{ID="Objects"},
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
        ui:LineEdit{ID="RenameValue",PlaceholderText="Rename selected object",Weight=0.63},
        ui:Button{ID="Rename",Text="Rename",Weight=0.20},
        ui:Button{ID="Delete",Text="Delete",Weight=0.17}
    },
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
        ui:Button{ID="UseFrom",Text="Origin from result"},
        ui:Button{ID="UseTo",Text="Target from result"},
        ui:Button{ID="AddRoute",Text="Add Route"}
    },
    ui:HGroup{
        ui:Label{ID="Status",Text="Status: Ready.",WordWrap=true,Weight=0.78},
        ui:Button{ID="Copy",Text="Copy status",Weight=0.22}
    },
    ui:HGroup{
        ui:Label{Text="Offline · Fusion-only · no independent timeline",Weight=0.72},
        ui:Button{ID="Close",Text="Close",Weight=0.28}
    }
})
local item=window:GetItems()
local choices,objects,groups={},{},{}
local context=nil
local locked=false
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
local function selectedObject()
    local obj=objects[currentIndex(item.Objects)]
    if not obj then error("Select a CartoRig object first")end
    return obj
end
local function compositionKey()
    local comp=scene.composition()
    local attrs=comp:GetAttrs() or {}
    return comp,tostring(attrs.COMPS_FileName or attrs.COMPS_Name or comp)
end
local function verifyContext()
    local comp,key=compositionKey()
    if context~=key then
        -- Fail closed: do not edit the last selected object from another comp.
        choices={};objects={}
        setItems(item.Results,{})
        setItems(item.Objects,{})
        context=key
        item.Context.Text="Composition: "..key
        error("Active composition changed. Refresh and select your scene.")
    end
    return comp
end
local function refresh()
    local comp,key=compositionKey()
    context=key
    item.Context.Text="Composition: "..key
    objects=scene.objects()
    local labels={}
    for i,entry in ipairs(objects)do
        labels[#labels+1]=string.format("%02d  %s | %s%s%s",i,
            tostring(entry.role),tostring(entry.name),
            entry.visible and "" or " [Hidden]",
            entry.locked and " [Locked]" or "")
    end
    setItems(item.Objects,labels)
    groups={}
    local groupLabels={"Select destination group..."}
    for _,entry in ipairs(objects) do
        if entry.role=="Group" then
            groups[#groups+1]=entry
            groupLabels[#groupLabels+1]=entry.name
        end
    end
    setItems(item.Groups,groupLabels)
    return tostring(#objects).." CartoRig objects in current composition."
end
local function perform(action)
    if locked then return end
    locked=true
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
function window.On.Show.Clicked(_)
    perform(function()
        local o=chooseObject("show")
        scene.visibility(o.id,true);refresh()
        return "Object shown."
    end)
end
function window.On.Hide.Clicked(_)
    perform(function()
        local o=chooseObject("hide")
        scene.visibility(o.id,false);refresh()
        return "Object hidden; animation remains intact."
    end)
end
function window.On.Lock.Clicked(_)
    perform(function()
        local o=chooseObject("lock")
        scene.lock(o.id,true);refresh()
        return "Object locked in CartoRig Scene."
    end)
end
function window.On.Unlock.Clicked(_)
    perform(function()
        local o=chooseObject("unlock")
        scene.lock(o.id,false);refresh()
        return "Object unlocked."
    end)
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
        local o=chooseObject("group")
        local group=groups[(tonumber(item.Groups.CurrentIndex) or -1)]
        if not group then error("Choose a destination group in the dropdown")end
        scene.setParent(o.id,group.id)
        refresh()
        return o.name.." added to "..group.name.." without changing its draw order."
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
function window.On.Delete.Clicked(_)
    perform(function()
        local o=chooseObject("delete")
        if o.role=="Base Map" or o.role=="Camera" then
            error("Base Map and Camera cannot be deleted.")
        end
        scene.delete(o.id);refresh()
        return "Selected object deleted. Restore via Fusion Undo if needed."
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
function window.On.Copy.Clicked(_)
    perform(function()
        local message=tostring(item.Status.Text)
        if not bmd or not bmd.setclipboard then
            return "Clipboard API unavailable. Diagnostic: "..message
        end
        bmd.setclipboard(message)
        return "Status copied."
    end)
end
function window.On.Close.Clicked(_)dispatcher:ExitLoop()end
function window.On.CartoRigSceneWindow.Close(_)dispatcher:ExitLoop()end
window:Show()
dispatcher:RunLoop()
window:Hide()
