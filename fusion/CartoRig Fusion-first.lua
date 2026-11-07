-- CartoRig 0.2 greenfield Fusion-first authoring interface for DaVinci Resolve Studio 20.
-- This file deliberately does not depend on earlier CartoRig plugin implementations.
-- Creates genuine Natural Earth polygon masks, Fusion nodes, independent native splines.
local function script_dir()
    local source=debug.getinfo(1,'S').source
    local path=source:sub(1,1)=='@' and source:sub(2) or source
    return (path:match('^(.*)[/\\][^/\\]*$') or '.')
end
local ROOT=script_dir()
local catalog=dofile(ROOT..'/CartoRig/catalog.lua')
local graph=dofile(ROOT..'/CartoRig/graph.lua')
local dataDir=ROOT..'/CartoRig/data'
local features=catalog.load(dataDir)
local host=rawget(_G,'fusion') or rawget(_G,'fu')
local comp=rawget(_G,'comp')
if not comp and host and host.GetCurrentComp then comp=host:GetCurrentComp() end
if not comp then error('CartoRig: Select a Fusion Composition and open the Fusion page before launching.',0) end
local ui=host and host.UIManager
local bmd=rawget(_G,'bmd')
if not ui or not bmd or not bmd.UIDispatcher then error('CartoRig: Fusion UIManager is unavailable.',0) end

-- Do not modify third-party nodes: this is a managed CartoRig scene only.
graph.ensure(comp,features)
local dispatcher=bmd.UIDispatcher(ui)
local win=dispatcher:AddWindow({
    ID='CartoRigMain',WindowTitle='CartoRig — Fusion-first Map Editor',Geometry={80,90,490,810},
},ui:VGroup{ID='CR_Root',Spacing=6,
    ui:Label{ID='CR_Title',Text='CARTORIG · MAP SCENE'},
    ui:Label{ID='CR_Source',Text='Offline Natural Earth 110m · Edit clip / Fusion animation'},
    ui:HGroup{
        ui:LineEdit{ID='CR_Find',PlaceholderText='Find location: Brasil, São Paulo, Amapá...'},
        ui:Button{ID='CR_Search',Text='Find'},
    },
    ui:ComboBox{ID='CR_Kind'},
    ui:Tree{ID='CR_Results',ColumnCount=1,MinimumSize={450,140}},
    ui:HGroup{
        ui:Button{ID='CR_AddRegion',Text='+ Region'},
        ui:Button{ID='CR_AddMarker',Text='+ Marker'},
        ui:Button{ID='CR_Focus',Text='Focus Camera'},
    },
    ui:HGroup{
        ui:Label{ID='CR_ObjectsTitle',Text='OBJECTS'},
        ui:Button{ID='CR_Refresh',Text='Refresh'},
    },
    ui:Tree{ID='CR_Objects',ColumnCount=1,MinimumSize={450,155}},
    ui:Label{ID='CR_Selected',Text='Select an object to edit its Fusion properties'},
    ui:HGroup{
        ui:Label{Text='Fill #'},
        ui:LineEdit{ID='CR_Hex',Text='#C92A2A'},
        ui:Button{ID='CR_ApplyFill',Text='Apply'},
        ui:Button{ID='CR_KeyFill',Text='Key @ Playhead'},
    },
    ui:HGroup{
        ui:Label{Text='Opacity %'},
        ui:LineEdit{ID='CR_Opacity',Text='100'},
        ui:Button{ID='CR_ApplyOpacity',Text='Apply'},
        ui:Button{ID='CR_KeyOpacity',Text='Key @ Playhead'},
    },
    ui:HGroup{
        ui:Label{Text='Camera Zoom'},
        ui:LineEdit{ID='CR_Zoom',Text='3'},
        ui:Button{ID='CR_KeyCamera',Text='Key Pose @ Playhead'},
    },
    ui:Label{Text='ROUTE / ARROW'},
    ui:HGroup{
        ui:Button{ID='CR_From',Text='From selected location'},
        ui:Button{ID='CR_To',Text='To selected location'},
    },
    ui:HGroup{
        ui:Button{ID='CR_Representative',Text='Use state representative point'},
        ui:Button{ID='CR_AddRoute',Text='+ Route'},
    },
    ui:Label{ID='CR_Route',Text='From: —   To: —'},
    ui:HGroup{
        ui:Button{ID='CR_Reveal0',Text='Route Reveal 0% key'},
        ui:Button{ID='CR_Reveal100',Text='Route Reveal 100% key'},
    },
    ui:Label{ID='CR_Status',Text='Ready. Native Fusion spline keys follow the playhead.'},
    ui:Button{ID='CR_Close',Text='Close CartoRig Editor'},
})
if not win then error('CartoRig: Could not create native UIManager window',0) end
local w=win:GetItems()
local chosen=nil
local chosenObj=nil
local from=nil
local to=nil
local pendingDestination=nil
local result_rows={}
local object_rows={}

local function status(message) w.CR_Status.Text=tostring(message) end
local function try(action)
    local ok,result=pcall(action)
    if not ok then status('ERROR: '..tostring(result));return nil end
    if result then status(tostring(result)) end
    return result
end
local function tree_clear(tree) tree:Clear() end
local function tree_add(tree,label)
    local item=tree:NewItem()
    item.Text[0]=label
    tree:AddTopLevelItem(item)
end
local function tree_current(tree,rows)
    local selected=tree:CurrentItem()
    if not selected then return nil end
    local text=tostring(selected.Text[0] or '')
    return rows[text]
end
local filters={'All','Continent','Country','State / Province','City'}
for _,x in ipairs(filters) do w.CR_Kind:AddItem(x) end
local function current_kind()
    local index=tonumber(w.CR_Kind.CurrentIndex) or 0
    local text=filters[index+1] or 'All'
    if text=='State / Province' then return 'State' end
    return text
end
local function results_refresh()
    local matches=catalog.search(features,w.CR_Find.Text,current_kind(),75)
    result_rows={}
    tree_clear(w.CR_Results)
    for i,f in ipairs(matches) do
        local label=catalog.description(f)
        if result_rows[label] then label=label..' · '..tostring(i) end
        result_rows[label]=f
        tree_add(w.CR_Results,label)
    end
    chosen=nil
    status(tostring(#matches)..' matching locations in offline catalog')
end
local function objects_refresh()
    object_rows={}
    tree_clear(w.CR_Objects)
    local layers=graph.get_base(comp)
    local entries={
        {kind='BaseMap',label='Base Map · Ocean',node=layers.ocean,id='base-ocean'},
        {kind='BaseMap',label='Base Map · Land',node=layers.land,id='base-land'},
    }
    for _,obj in ipairs(graph.get_objects(comp)) do entries[#entries+1]=obj end
    for _,obj in ipairs(entries) do
        local label=obj.label..'  ['..obj.kind..' # '..obj.id..']'
        object_rows[label]=obj
        tree_add(w.CR_Objects,label)
    end
end
local function select_object(obj)
    chosenObj=obj
    if not obj then return end
    w.CR_Selected.Text=obj.label
    -- The property panel reflects the selected native Fusion node, not stale values.
    local function channel(k)
        local t=tonumber(comp.CurrentTime)
        local value=t and obj.node:GetInput(k,t) or nil
        if type(value)~='number' then value=obj.node:GetInput(k) end
        if type(value)~='number' then return nil end
        return math.max(0,math.min(255,math.floor(value*255+0.5)))
    end
    local r,g,b=channel('TopLeftRed'),channel('TopLeftGreen'),channel('TopLeftBlue')
    if r and g and b then w.CR_Hex.Text=string.format('#%02X%02X%02X',r,g,b) end
    local alpha=channel('TopLeftAlpha')
    if alpha then w.CR_Opacity.Text=tostring(math.floor(alpha*100/255+0.5)) end
    local ok,msg=graph.select(comp,obj.node)
    status((ok and 'Fusion: ' or 'Fusion selection pending: ')..msg)
end
local function select_location()
    chosen=tree_current(w.CR_Results,result_rows)
    if chosen then
        status(catalog.description(chosen)..(chosen.polygons and ' · Polygon' or ' · Point'))
    end
end
local function route_message()
    w.CR_Route.Text='From: '..(from and from.name or '—')..'  To: '..(to and to.name or pendingDestination and ('[Confirm] '..pendingDestination.name) or '—')
end
local function add_selected_region()
    if not chosen then return status('Choose a location in search results') end
    try(function()
        local id=graph.add_region(comp,chosen)
        objects_refresh()
        return 'Added Region #'..id..' using true Natural Earth geometry'
    end)
end
local function add_selected_marker()
    if not chosen then return status('Choose a location in search results') end
    try(function()
        local id=graph.add_marker(comp,chosen)
        objects_refresh()
        return 'Added marker #'..id
    end)
end
local function set_focus(animated)
    if not chosen then return status('Choose a location to focus the camera') end
    try(function()
        graph.camera_focus(comp,chosen,w.CR_Zoom.Text,animated)
        return (animated and 'Keyframed camera on ' or 'Focused camera on ')..chosen.name
    end)
end
win.On.CR_Find.TextChanged=results_refresh
win.On.CR_Search.Clicked=results_refresh
win.On.CR_Kind.CurrentIndexChanged=results_refresh
win.On.CR_Results.CurrentItemChanged=select_location
win.On.CR_Objects.CurrentItemChanged=function() select_object(tree_current(w.CR_Objects,object_rows)) end
win.On.CR_Refresh.Clicked=function()objects_refresh();results_refresh() end
win.On.CR_AddRegion.Clicked=add_selected_region
win.On.CR_AddMarker.Clicked=add_selected_marker
win.On.CR_Focus.Clicked=function()set_focus(false) end
win.On.CR_KeyCamera.Clicked=function()set_focus(true) end
win.On.CR_ApplyFill.Clicked=function()
    try(function() graph.set_fill(comp,chosenObj,w.CR_Hex.Text,false);return 'Applied fill to '..chosenObj.label end)
end
win.On.CR_KeyFill.Clicked=function()
    try(function() graph.set_fill(comp,chosenObj,w.CR_Hex.Text,true);return 'Color keyed on Fusion playhead' end)
end
win.On.CR_ApplyOpacity.Clicked=function()
    try(function() graph.set_opacity(comp,chosenObj,w.CR_Opacity.Text,false);return 'Opacity applied' end)
end
win.On.CR_KeyOpacity.Clicked=function()
    try(function() graph.set_opacity(comp,chosenObj,w.CR_Opacity.Text,true);return 'Opacity keyframed on Fusion playhead' end)
end
win.On.CR_From.Clicked=function()
    if not chosen then return status('Select a geographic origin first') end
    if not chosen.lon then return status('Selected origin has no point') end
    if chosen.polygons then return status('Origin is an area: choose a City point instead') end
    from=chosen;route_message();status('Origin: '..chosen.name)
end
win.On.CR_To.Clicked=function()
    if not chosen then return status('Select a geographic destination first') end
    if not chosen.lon then return status('Selected destination has no point') end
    if chosen.polygons then
        pendingDestination=chosen
        to=nil
        route_message()
        return status('State/Country is an area. Explicitly choose Use state representative point, or select a City.')
    end
    pendingDestination=nil;to=chosen;route_message();status('Destination: '..chosen.name)
end
win.On.CR_Representative.Clicked=function()
    if not pendingDestination then return status('Choose a Country or State destination first') end
    to=pendingDestination
    pendingDestination=nil
    route_message();status('Confirmed representative point for '..to.name..'; not a capital or city')
end
win.On.CR_AddRoute.Clicked=function()
    try(function()
        local id=graph.add_route(comp,from,to)
        objects_refresh()
        return 'Added native Fusion route #'..id..'; style, arrow and trim may be animated'
    end)
end
win.On.CR_Reveal0.Clicked=function()
    try(function()graph.route_reveal(comp,chosenObj,0);return 'Route reveal 0% keyed at playhead' end)
end
win.On.CR_Reveal100.Clicked=function()
    try(function()graph.route_reveal(comp,chosenObj,100);return 'Route reveal 100% keyed at playhead' end)
end
win.On.CR_Close.Clicked=function()dispatcher:ExitLoop() end
win.On.CartoRigMain.Close=function()dispatcher:ExitLoop() end
objects_refresh()
results_refresh()
win:Show()
dispatcher:RunLoop()
win:Hide()
