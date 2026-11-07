-- CartoRig — ONE Edit-first authoring command. No ISO3, no separate
-- "Add Country", "Set Camera", "Animate Arrow" menu items.
-- Host API: Fusion UIManager, DaVinci Resolve scripting, Fusion OpenFX nodes.
-- The installer ships this as the only normal user-facing Utility entry.
local src=assert(debug.getinfo(1,"S").source)
assert(src:sub(1,1)=="@","Run CartoRig from Workspace > Scripts > Utility")
local baseDir=assert(src:sub(2):match("^(.*[\\/])"))
local service=assert(loadfile(baseDir.."CartoRigSupport\\service_v1.lua"))()
local fusion=(bmd and bmd.scriptapp and bmd.scriptapp("Fusion")) or _G.fu
if not fusion or not fusion.UIManager or not bmd or not bmd.UIDispatcher then
    error("CartoRig Editor requires Fusion UIManager in Resolve Studio 20")
end
local ui=fusion.UIManager
local dispatcher=bmd.UIDispatcher(ui)
local win=dispatcher:AddWindow({
    ID="CartoRigEditor", WindowTitle="CartoRig | Map Editor",
    Geometry={110,60,1070,925}, Spacing=9, Margin=13
},ui:VGroup{
    ID="Root",Spacing=8,
    ui:HGroup{
        ui:Label{Text="Map scene",Weight=0.1},
        ui:ComboBox{ID="Scene",Weight=0.6},
        ui:Button{ID="RefreshScenes",Text="Refresh",Weight=0.1},
        ui:Button{ID="CreateScene",Text="Create map",Weight=0.2}
    },
    ui:Label{Text="FIND  →  ADD  →  STYLE  →  ANIMATE",Alignment={AlignHCenter=true}},
    ui:HGroup{
        ui:LineEdit{ID="Query",PlaceholderText="Search country, state or city by name...",Weight=0.7},
        ui:ComboBox{ID="Kind",Weight=0.18},
        ui:Button{ID="Find",Text="Search",Weight=0.12}
    },
    ui:HGroup{
        ui:Label{Text="Location",Weight=0.1},
        ui:ComboBox{ID="Result",Weight=0.9}
    },
    ui:HGroup{
        ui:Button{ID="AddRegion",Text="+ Region"},
        ui:Button{ID="AddMarker",Text="+ Marker"},
        ui:Button{ID="AddLabel",Text="+ Label"},
        ui:Button{ID="Focus",Text="Focus camera"},
        ui:Button{ID="AnimateCamera",Text="Animate camera"}
    },
    ui:HGroup{
        ui:Label{Text="Camera zoom",Weight=0.15},
        ui:LineEdit{ID="Zoom",Text="4.2",Weight=0.18},
        ui:Label{Text="Duration in frames",Weight=0.2},
        ui:LineEdit{ID="Duration",Text="24",Weight=0.12},
        ui:Label{Text="(Only Animate creates keys)",Weight=0.35}
    },
    ui:HGroup{
        ui:Label{Text="Label text (optional; location name by default)",Weight=0.5},
        ui:LineEdit{ID="LabelText",PlaceholderText="Label name",Weight=0.5}
    },
    ui:VGap(5),
    ui:HGroup{
        ui:Label{Text="OBJECTS",Weight=0.15},
        ui:ComboBox{ID="Objects",Weight=0.67},
        ui:Button{ID="RefreshObjects",Text="Refresh",Weight=0.18}
    },
    ui:HGroup{
        ui:Button{ID="ApplyStyle",Text="Apply style"},
        ui:Button{ID="Hide",Text="Hide"},
        ui:Button{ID="Show",Text="Show"},
        ui:Button{ID="DuplicateObject",Text="Duplicate"},
        ui:Button{ID="MoveUp",Text="Move up"},
        ui:Button{ID="MoveDown",Text="Move down"},
        ui:Button{ID="RemoveObject",Text="Delete"}
    },
    ui:HGroup{
        ui:Label{Text="Rename selected object",Weight=0.23},
        ui:LineEdit{ID="ObjectName",PlaceholderText="New name",Weight=0.45},
        ui:Button{ID="RenameObject",Text="Rename",Weight=0.16},
        ui:Button{ID="AnimateRoute",Text="Reveal route",Weight=0.16}
    },
    ui:HGroup{
        ui:Label{Text="Fill",Weight=0.1},
        ui:ColorPicker{ID="FillPicker",Color={R=201/255,G=42/255,B=42/255,A=1},Weight=0.24},
        ui:Label{Text="Stroke",Weight=0.1},
        ui:ColorPicker{ID="StrokePicker",Color={R=212/255,G=175/255,B=55/255,A=1},Weight=0.24},
        ui:Label{Text="Opacity %",Weight=0.14},
        ui:LineEdit{ID="Opacity",Text="100",Weight=0.18}
    },
    ui:HGroup{
        ui:Label{Text="Precise Fill HEX (optional)",Weight=0.23},
        ui:LineEdit{ID="Fill",PlaceholderText="Use color picker or type #RRGGBB",Text="",Weight=0.28},
        ui:Label{Text="Stroke HEX (optional)",Weight=0.20},
        ui:LineEdit{ID="Stroke",PlaceholderText="Uses picker if blank",Text="",Weight=0.29}
    },
    ui:HGroup{
        ui:Label{Text="Base-map layer",Weight=0.18},
        ui:ComboBox{ID="BasePart",Weight=0.25},
        ui:Button{ID="BaseStyle",Text="Apply base color",Weight=0.25},
        ui:Label{Text="Same Fill control for base map and objects",Weight=0.32}
    },
    ui:HGroup{
        ui:Label{Text="Map background",Weight=0.25},
        ui:ComboBox{ID="BackgroundMode",Weight=0.30},
        ui:Button{ID="ApplyBackground",Text="Apply transparency",Weight=0.25},
        ui:Label{Text="Transparent oceans for overlay on video",Weight=0.20}
    },
    ui:VGap(5),
    ui:Label{Text="ROUTE  |  Choose endpoints using Find above. Regions need a manually selected point."},
    ui:HGroup{
        ui:Button{ID="RouteFrom",Text="Use result as origin",Weight=0.2},
        ui:Label{ID="RouteFromLabel",Text="Origin: not selected",Weight=0.3},
        ui:Button{ID="RouteTo",Text="Use result as destination",Weight=0.2},
        ui:Label{ID="RouteToLabel",Text="Destination: not selected",Weight=0.3}
    },
    ui:HGroup{
        ui:Label{Text="Area origin lon / lat",Weight=0.22},
        ui:LineEdit{ID="FromLon",PlaceholderText="Longitude",Weight=0.14},
        ui:LineEdit{ID="FromLat",PlaceholderText="Latitude",Weight=0.14},
        ui:Label{Text="Area destination lon / lat",Weight=0.22},
        ui:LineEdit{ID="ToLon",PlaceholderText="Longitude",Weight=0.14},
        ui:LineEdit{ID="ToLat",PlaceholderText="Latitude",Weight=0.14}
    },
    ui:HGroup{
        ui:Label{Text="Curve (-100..100)",Weight=0.18},
        ui:LineEdit{ID="Curve",Text="0",Weight=0.17},
        ui:Label{Text="Width (px)",Weight=0.13},
        ui:LineEdit{ID="Width",Text="4",Weight=0.12},
        ui:ComboBox{ID="Arrowhead",Weight=0.18},
        ui:Button{ID="AddRoute",Text="+ Add route",Weight=0.15},
        ui:Button{ID="EditRoute",Text="Edit selected",Weight=0.15}
    },
    ui:VGap(6),
    ui:Label{ID="Status",Text="Ready. Select or create a scene; search locally.",WordWrap=true},
    ui:HGroup{
        ui:Label{Text="Offline. Existing map remains unchanged until an action is confirmed."},
        ui:Button{ID="Close",Text="Close",Weight=0.15}
    }
})
local it=win:GetItems()
local scenes,results,objects={}, {}, {}
local function chosenColor(field)
    local manual=tostring(it[field].Text or ""):gsub("^%s+",""):gsub("%s+$","")
    if manual~="" then
        if not manual:match("^#%x%x%x%x%x%x$") then
            error("Invalid "..field.." HEX; use #RRGGBB or leave blank",3)
        end
        return manual:upper()
    end
    local color=it[field.."Picker"].Color
    local function channel(v)
        v=tonumber(v)
        if not v or v~=v then error("Color picker unavailable",3) end
        return math.min(255,math.max(0,math.floor(v*255+0.5)))
    end
    return string.format("#%02X%02X%02X",
                         channel(color.R),channel(color.G),channel(color.B))
end

local from,to=nil,nil
local function setItems(combo,items)
    combo:Clear()
    if #items>0 then combo:AddItems(items);combo.CurrentIndex=0 end
end
local function currentIndex(control)
    local i=tonumber(control.CurrentIndex)
    if not i or i<0 then error("Select an item first",3) end
    return i+1
end
local function sceneIndex()return currentIndex(it.Scene)end
local function selectedLocation()
    return results[currentIndex(it.Result)] or error("Search and select a location",3)
end
local function objectIndex()return currentIndex(it.Objects)end
local function action(fn)
    local ok,response=pcall(fn)
    if ok then
        it.Status.Text=response and tostring(response) or "Applied successfully."
    else
        it.Status.Text="Not applied: "..tostring(response)
        print("[CartoRig Editor] "..tostring(response))
    end
end
local function updateScenes()
    scenes=service.scenes()
    local labels={}
    for _,entry in ipairs(scenes)do labels[#labels+1]=entry.label end
    setItems(it.Scene,labels)
    return "Found "..#scenes.." CartoRig Map scene(s)."
end
local function updateObjects()
    objects=service.objects(sceneIndex())
    local labels={}
    for _,entry in ipairs(objects)do
        local meta=entry.meta or {}
        labels[#labels+1]=tostring(meta.type or "Object").." | "..
                          tostring(meta.name or entry.node:GetAttrs().TOOLS_Name)
    end
    setItems(it.Objects,labels)
    return "Found "..#objects.." CartoRig object(s)."
end
local function kind()
    return ({"all","continent","country","state","city"})[
        math.max(1,(tonumber(it.Kind.CurrentIndex) or 0)+1)]
end
setItems(it.Kind,{"All locations","Continent","Country","State / Province","City"})
setItems(it.BasePart,{"Land","Ocean","Borders"})
setItems(it.BackgroundMode,{"Opaque map","Transparent ocean"})
setItems(it.Arrowhead,{"Arrowhead","Plain line"})
action(updateScenes)
if #scenes>0 then action(updateObjects)end
function win.On.RefreshScenes.Clicked(_)action(function()return updateScenes()end)end
function win.On.Scene.CurrentIndexChanged(_)action(function()return updateObjects()end)end
function win.On.CreateScene.Clicked(_)
    action(function()
        local message=service.create()
        updateScenes();updateObjects()
        return message or "Created blank map. No default animation."
    end)
end
function win.On.Find.Clicked(_)
    action(function()
        results=service.search(it.Query.Text,kind())
        local labels={}
        for _,loc in ipairs(results)do
            labels[#labels+1]=loc.name.." — "..loc.kind..
                              (loc.parent~="" and (" · "..loc.parent) or "")..
                              (loc.isOfficial and " [Natural Earth]" or " [Starter data]")
        end
        setItems(it.Result,labels)
        if #results==0 then
            return "No matching data. Install the offline Natural Earth pack for states and cities."
        end
        return tostring(#results).." candidate(s). Select the correct type explicitly."
    end)
end
function win.On.AddRegion.Clicked(_)
    action(function()
        service.addRegion(sceneIndex(),selectedLocation(),
                          chosenColor("Fill"),chosenColor("Stroke"),tonumber(it.Opacity.Text))
        updateObjects()
        return "Region added with its own fill and stroke. Existing regions unchanged."
    end)
end
function win.On.AddMarker.Clicked(_)
    action(function()
        local loc=selectedLocation()
        service.addMarker(sceneIndex(),loc,loc.name,chosenColor("Fill"))
        updateObjects()
        return "Georeferenced marker added without any automatic animation."
    end)
end
function win.On.AddLabel.Clicked(_)
    action(function()
        local loc=selectedLocation()
        local title=tostring(it.LabelText.Text or "")
        if title=="" then title=loc.name end
        service.addLabel(sceneIndex(),loc,title,chosenColor("Fill"))
        updateObjects()
        return "Independent text label anchored to an offline geographic point."
    end)
end
function win.On.Focus.Clicked(_)
    action(function()
        service.focus(sceneIndex(),selectedLocation(),tonumber(it.Zoom.Text))
        return "Camera focused. No keyframe created."
    end)
end
function win.On.AnimateCamera.Clicked(_)
    action(function()
        service.animateCamera(sceneIndex(),selectedLocation(),
                              tonumber(it.Zoom.Text),tonumber(it.Duration.Text))
        return "Camera keyframes requested from Fusion (verify native curves in Resolve)."
    end)
end
function win.On.RefreshObjects.Clicked(_)action(updateObjects)end
function win.On.ApplyStyle.Clicked(_)
    action(function()
        service.style(sceneIndex(),objectIndex(),chosenColor("Fill"),
                      chosenColor("Stroke"),tonumber(it.Opacity.Text))
        return "Object style updated. Other object styles preserved."
    end)
end
function win.On.Hide.Clicked(_)
    action(function()service.hide(sceneIndex(),objectIndex(),true);return updateObjects()end)
end
function win.On.Show.Clicked(_)
    action(function()service.hide(sceneIndex(),objectIndex(),false);return updateObjects()end)
end
function win.On.RenameObject.Clicked(_)
    action(function()
        service.renameObject(sceneIndex(),objectIndex(),it.ObjectName.Text)
        return updateObjects()
    end)
end
function win.On.DuplicateObject.Clicked(_)
    action(function()
        service.duplicateObject(sceneIndex(),objectIndex())
        updateObjects()
        return "Duplicated geography and static style into an independent object. "..
               "Animation keys are not duplicated in this preview."
    end)
end
function win.On.MoveUp.Clicked(_)
    action(function()
        service.moveObject(sceneIndex(),objectIndex(),-1)
        return updateObjects()
    end)
end
function win.On.MoveDown.Clicked(_)
    action(function()
        service.moveObject(sceneIndex(),objectIndex(),1)
        return updateObjects()
    end)
end
function win.On.RemoveObject.Clicked(_)
    action(function()
        service.delete(sceneIndex(),objectIndex())
        updateObjects()
        return "Only selected CartoRig object deleted."
    end)
end
function win.On.ApplyBackground.Clicked(_)
    action(function()
        local transparent=(tonumber(it.BackgroundMode.CurrentIndex) or 0)==1
        service.backgroundMode(sceneIndex(),transparent)
        return transparent and
            "Transparent ocean mode requested. Validate alpha over video." or
            "Opaque map mode requested."
    end)
end
function win.On.BaseStyle.Clicked(_)
    action(function()
        local idx=currentIndex(it.BasePart)
        service.baseStyle(sceneIndex(),({"land","ocean","border"})[idx],chosenColor("Fill"))
        return "Base-map layer styled. Explicit object overrides remain intact."
    end)
end
function win.On.RouteFrom.Clicked(_)
    action(function()
        from=selectedLocation()
        it.RouteFromLabel.Text="Origin: "..from.name.." ("..from.kind..")"
        return "Route origin set."
    end)
end
function win.On.RouteTo.Clicked(_)
    action(function()
        to=selectedLocation()
        it.RouteToLabel.Text="Destination: "..to.name.." ("..to.kind..")"
        return (to.kind=="state" or to.kind=="country") and
               "Area selected. Enter a chosen destination lon/lat; no implicit city." or
               "Route destination set."
    end)
end
function win.On.AddRoute.Clicked(_)
    action(function()
        local opts={
            color=chosenColor("Fill"),width=tonumber(it.Width.Text),
            curve=tonumber(it.Curve.Text),
            opacity=tonumber(it.Opacity.Text),
            arrowhead=(tonumber(it.Arrowhead.CurrentIndex) or 0)==0
        }
        if from and from.kind~="city" then
            opts.fromPoint={lon=tonumber(it.FromLon.Text),
                            lat=tonumber(it.FromLat.Text)}
        end
        if to and to.kind~="city" then
            opts.toPoint={lon=tonumber(it.ToLon.Text),
                          lat=tonumber(it.ToLat.Text)}
        end
        service.addRoute(sceneIndex(),from,to,opts)
        updateObjects()
        return "Route added. Press Reveal route only if you want keyframes."
    end)
end
function win.On.EditRoute.Clicked(_)
    action(function()
        if not objects[objectIndex()] or
           not objects[objectIndex()].meta or
           objects[objectIndex()].meta.type~="Route" then
            error("Select a Route in the Objects list")
        end
        local opts={
            curve=tonumber(it.Curve.Text),
            width=tonumber(it.Width.Text),
            arrowhead=(tonumber(it.Arrowhead.CurrentIndex) or 0)==0
        }
        if from and from.kind~="city" then
            opts.fromPoint={lon=tonumber(it.FromLon.Text),lat=tonumber(it.FromLat.Text)}
        end
        if to and to.kind~="city" then
            opts.toPoint={lon=tonumber(it.ToLon.Text),lat=tonumber(it.ToLat.Text)}
        end
        service.editRoute(sceneIndex(),objectIndex(),from,to,opts)
        updateObjects()
        return "Existing route edited; native Reveal animation remains untouched."
    end)
end
function win.On.AnimateRoute.Clicked(_)
    action(function()
        service.animateRoute(sceneIndex(),objectIndex(),tonumber(it.Duration.Text))
        return "Route reveal keyframes requested from Fusion."
    end)
end
function win.On.Close.Clicked(_)dispatcher:ExitLoop()end
function win.On.CartoRigEditor.Close(_)dispatcher:ExitLoop()end
win:Show()
dispatcher:RunLoop()
win:Hide()
