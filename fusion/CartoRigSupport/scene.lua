-- CartoRig Fusion RC1 — Scene domain adapter.
-- Only the current Fusion composition is authoritative. No Edit APIs.
-- IDs live on Fusion nodes, not in the UIManager process. All mutations
-- are explicit, reversible via Fusion undo where host supports it.
local M={}
M.VERSION="1.0.0-rc1-dev"
local SESSION="CartoRig.Fusion.RC1."
local function assertHost(value,message)
    if value==nil or value==false then error(message.." (Fusion host unavailable)",3) end
    return value
end
local function current()
    -- A long-lived UIManager window must follow the ACTIVE composition;
    -- the initial global comp points to the script launch context only.
    local composition=nil
    if _G.fu and type(fu.GetCurrentComp)=="function" then
        composition=fu:GetCurrentComp()
    end
    if not composition and _G.fusion and
       type(fusion.GetCurrentComp)=="function" then
        composition=fusion:GetCurrentComp()
    end
    if not composition then composition=_G.comp end
    return assertHost(composition,"No current Fusion composition")
end
local function tools(composition)
    return assertHost(composition:GetToolList(false),"Tool enumeration")
end
local function eachTool(composition,fn)
    for _,tool in pairs(tools(composition)) do fn(tool) end
end
local function meta(tool,key)
    if type(tool.GetData)~="function" then return nil end
    return tool:GetData(SESSION..key)
end
local function stamp(tool,key,value)
    assertHost(tool:SetData(SESSION..key,value),"Persist CartoRig "..key)
end
local function readable(tool)
    return (tool:GetAttrs() or {}).TOOLS_Name or ""
end
local function unique(composition,prefix)
    local taken={}
    eachTool(composition,function(t)taken[readable(t)]=true end)
    for n=1,5000 do
        local name=prefix..string.format("_%04d",n)
        if not taken[name] then return name end
    end
    error("CartoRig node naming capacity exceeded")
end
local function newid(composition)
    local ids={}
    eachTool(composition,function(t)
        local id=meta(t,"ObjectId")
        if id then ids[id]=true end
    end)
    for n=1,100000 do
        local id=string.format("cr-obj-%08x-%06d",os.time()%0xffffffff,n)
        if not ids[id] then return id end
    end
    error("Could not assign a unique CartoRig object ID")
end
local function rename(tool,value)
    assertHost(tool:SetAttrs({TOOLS_Name=value}),"Rename Fusion tool")
end
local function input(tool,key,value,time)
    local ok
    if time~=nil then ok=tool:SetInput(key,value,time)
    else ok=tool:SetInput(key,value) end
    assertHost(ok,"Set Fusion input "..key)
end
local function connect(tool,upstream)
    for _,socket in ipairs({"Source","Input","Image"}) do
        local ok,result=pcall(function()return tool:ConnectInput(socket,upstream)end)
        if ok and result~=false and result~=nil then return end
    end
    error("Unable to connect CartoRig OpenFX input",3)
end
local function transaction(composition,title,fn)
    assertHost(composition.StartUndo,"Fusion Undo API")
    composition:StartUndo(title)
    local ok,result=pcall(fn)
    local committed,why=pcall(function()composition:EndUndo(ok)end)
    if not ok then error(result,3) end
    if not committed then error(why,3) end
    return result
end
function M.composition()return current()end
function M.isInitialized(composition)
    composition=composition or current()
    local map=composition:FindTool("CR_Base_Map")
    local camera=composition:FindTool("CR_Camera")
    if not map or not camera or not composition:FindTool("CR_Stack_Output") then
        return false
    end
    return meta(map,"Role")=="Base Map" and meta(camera,"Role")=="Camera"
end
local function getCore(composition)
    if not M.isInitialized(composition) then
        error("Initialize CartoRig in the current Fusion composition first",3)
    end
    return composition:FindTool("CR_Base_Map"),composition:FindTool("CR_Camera"),
           composition:FindTool("CR_Stack_Output")
end
local function owned(composition)
    local results={}
    eachTool(composition,function(tool)
        if meta(tool,"ObjectId") then
            results[#results+1]={
                id=meta(tool,"ObjectId"),
                role=meta(tool,"Role"),
                name=meta(tool,"DisplayName") or readable(tool),
                feature=meta(tool,"FeatureId"),
                locationKind=meta(tool,"LocationKind"),
                locked=meta(tool,"Locked") or false,
                visible=meta(tool,"Visible")~=false,
                z=tonumber(meta(tool,"Order")) or 0,
                node=tool
            }
        end
    end)
    table.sort(results,function(a,b)
        if a.z==b.z then return a.id<b.id end
        return a.z<b.z
    end)
    return results
end
function M.objects()
    local composition=current()
    if not M.isInitialized(composition) then return {} end
    return owned(composition)
end
local function objectFor(composition,id)
    for _,entry in ipairs(owned(composition)) do
        if entry.id==id then return entry end
    end
    error("CartoRig object no longer exists in this composition",3)
end
local function isLocked(composition,entry)
    if entry.locked then return true end
    local parent=meta(entry.node,"ParentGroup")
    if parent and parent~=""then
        local ok,group=pcall(objectFor,composition,parent)
        if ok and group.role=="Group"and group.locked then return true end
    end
    return false
end
local function trySelect(composition,tool)
    if type(composition.SetActiveTool)=="function" then
        local ok,res=pcall(function()return composition:SetActiveTool(tool)end)
        if ok and res~=false then return true end
    end
    return false
end
function M.select(id)
    local composition=current()
    local entry=objectFor(composition,id)
    trySelect(composition,entry.node)
    return entry
end
local function maxOrder(composition)
    local order=0
    for _,entry in ipairs(owned(composition)) do order=math.max(entry.z,order) end
    return order+1
end
local function setObjectData(composition,tool,role,name,feature,kind)
    stamp(tool,"ObjectId",newid(composition))
    stamp(tool,"Role",role)
    stamp(tool,"DisplayName",name)
    stamp(tool,"FeatureId",feature or "")
    stamp(tool,"LocationKind",kind or "")
    if feature and feature~="" then
        stamp(tool,"SourceProvider","Natural Earth")
        stamp(tool,"SourceScale","10m")
        stamp(tool,"SourceDataset",feature:match("^(.-):") or "")
        stamp(tool,"SourceWorldview","Publisher default")
    end
    stamp(tool,"Locked",false)
    stamp(tool,"Visible",true)
    stamp(tool,"Order",maxOrder(composition))
end
local function bindCamera(node)
    for _,pair in ipairs({
       {"CameraLongitude","CenterLongitude"},
       {"CameraLatitude","CenterLatitude"},
       {"CameraZoom","Zoom"},
       {"CameraBearing","Bearing"}
    }) do
       local handle=node[pair[1]]
       if not handle or type(handle.SetExpression)~="function" then
           error("Cannot bind "..pair[1].." to the shared Fusion camera")
       end
       assertHost(handle:SetExpression("CR_Camera."..pair[2]),
                  "Bind shared geo camera")
    end
end
local function rewire(composition)
    local base,camera,out=getCore(composition)
    assertHost(out,"CartoRig output port unavailable")
    local tail=base
    for _,entry in ipairs(owned(composition)) do
        if entry.role~="Base Map" and entry.role~="Camera"
           and entry.role~="Group" then
            connect(entry.node,tail)
            tail=entry.node
        end
    end
    connect(out,tail)
end
local function newTool(composition,pluginName,label,x,y)
    local tool=assertHost(composition:AddTool(pluginName,x or 0,y or 0),
                          "Create CartoRig "..label)
    rename(tool,unique(composition,"CR_"..label))
    return tool
end
function M.initialize()
    local composition=current()
    if M.isInitialized(composition)then return false,"Already initialized"end
    if composition:FindTool("CR_Base_Map") or composition:FindTool("CR_Camera") then
        error("Reserved CartoRig node names already present. No changes made.")
    end
    local media=composition:FindTool("MediaOut1")
                  or composition:FindToolByID("MediaOut")
    -- We deliberately do not replace user connections to MediaOut.
    return transaction(composition,"CartoRig: Initialize scene",function()
        local bg=assertHost(composition:AddTool("Background",-5,0),
                            "Fusion Background")
        rename(bg,"CR_Background")
        input(bg,"TopLeftAlpha",0)
        local map=newTool(composition,"ofx.com.cartorig.fusionrc1.map","BaseMap",-3,0)
        rename(map,"CR_Base_Map")
        connect(map,bg)
        local camera=newTool(composition,"ofx.com.cartorig.fusionrc1.camera",
                             "Camera",0,-3)
        rename(camera,"CR_Camera")
        local stack=assertHost(composition:AddTool("PipeRouter",5,0),
                               "CartoRig stack output")
        rename(stack,"CR_Stack_Output")
        stamp(map,"Role","Base Map");stamp(map,"ObjectId",newid(composition))
        stamp(map,"DisplayName","Base Map");stamp(map,"Order",0)
        stamp(camera,"Role","Camera");stamp(camera,"ObjectId",newid(composition))
        stamp(camera,"DisplayName","Camera");stamp(camera,"Order",0)
        stamp(map,"Initialized",true)
        stamp(map,"SceneId",newid(composition))
        stamp(map,"SchemaVersion",1)
        stamp(map,"Projection","Equirectangular")
        bindCamera(map)
        connect(stack,map)
        -- A populated MediaOut is user-owned: never hijack its input.
        -- For a blank composition, only user-visible connection is made.
        if media and media.Input and type(media.Input.GetConnectedOutput)=="function" then
            local connected=media.Input:GetConnectedOutput()
            if not connected then
                assertHost(media:ConnectInput("Input",stack),
                           "Connect initialized scene to empty MediaOut")
            end
        elseif media then
            -- Cannot prove existing input is empty. Leave stack separate.
        end
        return true,"Scene initialized. Select CR_Stack_Output if not connected."
    end)
end
-- Explicit output integration. Initializing CartoRig never disconnects an
-- existing MediaOut input. The user must choose this operation.
function M.connectOutput()
    local composition=current()
    local base,camera,stack=getCore(composition)
    local media=composition:FindTool("MediaOut1")
                    or composition:FindToolByID("MediaOut")
    if not media then
        error("No MediaOut in this composition; add one before connecting",2)
    end
    if not media.Input or type(media.Input.GetConnectedOutput)~="function" then
        error("Cannot inspect MediaOut input safely; existing connection preserved",2)
    end
    local old=media.Input:GetConnectedOutput()
    if old==stack or (stack.Output and old==stack.Output) then
        return "CartoRig already connected to MediaOut."
    end
    if old then
        -- Resolve may return an Output object whose owner is unavailable.
        -- We only operate on it by passing the original Output to Fusion.
        return transaction(composition,"CartoRig: Connect above existing MediaOut",function()
            local merge=assertHost(composition:AddTool("Merge",7,0),
                                   "Fusion Merge tool")
            local ok,result=pcall(function()
                rename(merge,unique(composition,"CR_Output_Merge"))
                assertHost(merge:ConnectInput("Background",old),
                           "Preserve existing MediaOut image")
                assertHost(merge:ConnectInput("Foreground",stack),
                           "Connect CartoRig to Merge foreground")
                assertHost(media:ConnectInput("Input",merge),
                           "Connect composited output to MediaOut")
            end)
            if not ok then
                pcall(function()media:ConnectInput("Input",old)end)
                pcall(function()merge:Delete()end)
                error(result)
            end
            return "CartoRig output merged over existing MediaOut source."
        end)
    end
    return transaction(composition,"CartoRig: Connect output",function()
        assertHost(media:ConnectInput("Input",stack),
                   "Connect empty MediaOut to CartoRig output")
        return "CartoRig connected to previously empty MediaOut."
    end)
end
function M.rebuild()
    local composition=current()
    return transaction(composition,"CartoRig: Rebuild object stack",function()
        rewire(composition)
        return true
    end)
end
local function dataDirectory()
    if _G.CARTORIG_TEST_DATA then return _G.CARTORIG_TEST_DATA end
    if os.getenv("CARTORIG_RC1_DATA") then return os.getenv("CARTORIG_RC1_DATA") end
    local info=assert(debug.getinfo(1,"S"))
    local root=info.source:sub(2):match("^(.*[\\/])") or ""
    local file=io.open(root.."install-root.txt","rb")
    if file then
        local location=file:read("*l");file:close()
        if location and location~="" then return location end
    end
    return root.."data"
end
local function norm(s)
    s=tostring(s or ""):lower()
    local replace={["á"]="a",["à"]="a",["â"]="a",["ã"]="a",["ä"]="a",
        ["é"]="e",["è"]="e",["ê"]="e",["í"]="i",["ó"]="o",
        ["ô"]="o",["õ"]="o",["ú"]="u",["ü"]="u",["ç"]="c"}
    for from,to in pairs(replace)do s=s:gsub(from,to)end
    return s:gsub("^%s+",""):gsub("%s+$","")
end
local function cols(line)
    local out={}
    for field in (line.."\t"):gmatch("([^\t]*)\t") do out[#out+1]=field end
    return out
end
function M.search(text,kind)
    text=norm(text)
    if #text<2 or #text>120 then error("Search 2–120 characters",2)end
    kind=kind or "all"
    local allowed={all=true,country=true,state=true,city=true,continent=true}
    if not allowed[kind]then error("Unsupported geographic filter",2)end
    local path=dataDirectory()
    local file=assert(io.open(path.."/catalog.tsv","rb"),
                      "Natural Earth offline catalog not installed")
    local found,seen={},{}
    local index=0
    for line in file:lines()do
        index=index+1
        if index>1 then
            local c=cols(line)
            if #c==11 then
                local matches=(kind=="all"or c[2]==kind) and
                    (norm(c[3]):find(text,1,true)
                     or norm(c[5]):find(text,1,true))
                if matches and not seen[c[1]]then
                    seen[c[1]]=true
                    found[#found+1]={
                        id=c[1],kind=c[2],name=c[3],parent=c[4],
                        aliases=c[5],bounds={
                            tonumber(c[6]),tonumber(c[7]),tonumber(c[8]),tonumber(c[9])
                        },geometry=(c[2]=="city" and "Point" or "Polygon")
                    }
                end
            end
        end
    end
    file:close()
    table.sort(found,function(a,b)
        if a.name==b.name then return a.kind<b.kind end
        return a.name<b.name
    end)
    while #found>50 do table.remove(found)end
    return found
end
local function verifyLocation(loc)
    if type(loc)~="table" or type(loc.id)~="string"
       or loc.id=="" or type(loc.kind)~="string"then
        error("Select a real offline location first",3)
    end
    if loc.kind=="city" then return "Point" end
    if loc.kind=="country"or loc.kind=="state" then return "Polygon"end
    error("This location does not have a supported editable geometry",3)
end
function M.addRegion(loc)
    if verifyLocation(loc)~="Polygon" then
        error("City is a point. Add Marker or Focus Camera instead",2)
    end
    local composition=current()
    local base,camera,output=getCore(composition)
    return transaction(composition,"CartoRig: Add Region",function()
        local node=newTool(composition,"ofx.com.cartorig.fusionrc1.region",
                           "Region",2,maxOrder(composition))
        local ok,err=pcall(function()
            input(node,"FeatureId",loc.id)
            bindCamera(node)
            setObjectData(composition,node,"Region",loc.name,loc.id,loc.kind)
            rewire(composition)
        end)
        if not ok then pcall(function()node:Delete()end);error(err) end
        trySelect(composition,node)
        return meta(node,"ObjectId")
    end)
end
function M.addMarker(location)
    local composition=current()
    local base,camera,output=getCore(composition)
    if type(location)~="table"or not location.bounds then
       error("Select an offline location",2)
    end
    if location.kind~="city" and location.kind~="custom_point" then
        error("Only published city points or explicitly chosen coordinates "..
              "can create markers; a region center is not a city",2)
    end
    local bbox=location.bounds
    local lon=(bbox[1]+bbox[3])/2
    local lat=(bbox[2]+bbox[4])/2
    return transaction(composition,"CartoRig: Add Marker",function()
        local node=newTool(composition,"ofx.com.cartorig.fusionrc1.marker",
                           "Marker",3,maxOrder(composition))
        local ok,err=pcall(function()
            bindCamera(node)
            input(node,"PointLongitude",lon)
            input(node,"PointLatitude",lat)
            setObjectData(composition,node,"Marker",location.name,location.id,location.kind)
            rewire(composition)
        end)
        if not ok then pcall(function()node:Delete()end);error(err)end
        trySelect(composition,node)
        return meta(node,"ObjectId")
    end)
end
function M.addLabel(location,text)
    if type(location)~="table" or
       (location.kind~="city" and location.kind~="custom_point") or
       not location.bounds then
        error("Text labels must use a city or explicitly chosen point",2)
    end
    text=tostring(text or location.name or "")
    if #text<1 or #text>250 or text:find("[%z\1-\8]") then
        error("Label text must contain valid printable Unicode characters",2)
    end
    local b=location.bounds
    local lon=(b[1]+b[3])/2
    local lat=(b[2]+b[4])/2
    local composition=current()
    getCore(composition)
    return transaction(composition,"CartoRig: Add Label",function()
        local node=newTool(composition,"ofx.com.cartorig.fusionrc1.label",
                           "Label",4,maxOrder(composition))
        local ok,err=pcall(function()
            input(node,"StyledText",text)
            input(node,"PointLongitude",lon)
            input(node,"PointLatitude",lat)
            bindCamera(node)
            setObjectData(composition,node,"Label",
                          "Label: "..text,location.id,location.kind)
            rewire(composition)
        end)
        if not ok then pcall(function()node:Delete()end);error(err)end
        trySelect(composition,node)
        return meta(node,"ObjectId")
    end)
end
function M.addCustomPoint(lon,lat,label)
    lon=tonumber(lon);lat=tonumber(lat)
    if not lon or not lat or lon<-180 or lon>180 or lat<-85 or lat>85 then
        error("Custom point needs valid WGS84 longitude/latitude",2)
    end
    label=tostring(label or "Custom Point")
    if #label<1 or #label>120 then
        error("Custom point name must contain 1–120 characters",2)
    end
    return M.addMarker({
        id="custom-point:"..tostring(lon)..":"..tostring(lat),
        kind="custom_point",name=label,parent="",
        bounds={lon,lat,lon,lat}
    })
end
function M.focus(loc,fit)
    if type(loc)~="table"or not loc.bounds then
        error("Select a valid geographic location",2)
    end
    local composition=current()
    local base,camera=getCore(composition)
    local b=loc.bounds
    local lon=(b[1]+b[3])/2
    local lat=(b[2]+b[4])/2
    return transaction(composition,"CartoRig: Focus camera",function()
        input(camera,"CenterLongitude",lon)
        input(camera,"CenterLatitude",lat)
        if fit then
            local westEast=math.max(.001,b[3]-b[1])
            local northSouth=math.max(.001,b[4]-b[2])
            local attributes=composition:GetAttrs() or {}
            local width=tonumber(attributes.COMPN_RenderWidth) or 1920
            local height=tonumber(attributes.COMPN_RenderHeight) or 1080
            local padding=.08
            -- Same equirectangular transform as the C++ renderer.
            local zoom=math.min((1-2*padding)*360/westEast,
                (1-2*padding)*360*height/(width*northSouth))
            zoom=math.min(50,math.max(.1,zoom))
            input(camera,"Zoom",zoom)
        end
        trySelect(composition,camera)
        return true
    end)
end
function M.addRoute(from,to)
    local composition=current()
    local base,camera=getCore(composition)
    if not from or not to or not from.lon or not to.lon
       or not from.lat or not to.lat then
        error("Select explicit route endpoint coordinates",2)
    end
    for _,point in ipairs({from,to})do
        if point.lon < -180 or point.lon>180 or point.lat < -85 or point.lat>85 then
            error("Invalid geographic route coordinates",2)
        end
    end
    return transaction(composition,"CartoRig: Add Route",function()
        local node=newTool(composition,"ofx.com.cartorig.fusionrc1.route",
                           "Route",4,maxOrder(composition))
        local ok,err=pcall(function()
            bindCamera(node)
            input(node,"FromLongitude",from.lon)
            input(node,"FromLatitude",from.lat)
            input(node,"ToLongitude",to.lon)
            input(node,"ToLatitude",to.lat)
            setObjectData(composition,node,"Route",
                (from.name or "Origin").." → "..(to.name or "Destination"),"","")
            stamp(node,"Waypoints",{})
            input(node,"WaypointsEncoded","")
            rewire(composition)
        end)
        if not ok then pcall(function()node:Delete()end);error(err)end
        trySelect(composition,node)
        return meta(node,"ObjectId")
    end)
end
local function waypointRoute(composition,id)
    local item=objectFor(composition,id)
    if item.role~="Route" then error("Select an authored Route",3) end
    if isLocked(composition,item) then error("This Route is locked",3)end
    return item
end
local function waypointList(route)
    local stored=meta(route.node,"Waypoints")
    if type(stored)~="table"then return {} end
    local points={}
    for _,point in ipairs(stored)do
        points[#points+1]={lon=tonumber(point.lon),lat=tonumber(point.lat)}
    end
    return points
end
local function encodedWaypoints(points)
    if #points>64 then error("A Route supports at most 64 waypoints",3)end
    local parts={}
    for _,point in ipairs(points)do
        if not point.lon or not point.lat or
           point.lon<-180 or point.lon>180 or
           point.lat<-85 or point.lat>85 then
            error("Invalid WGS84 waypoint",3)
        end
        parts[#parts+1]=string.format("%.12g,%.12g",point.lon,point.lat)
    end
    return table.concat(parts,";")
end
function M.waypoints(id)
    local composition=current()
    return waypointList(waypointRoute(composition,id))
end
function M.addWaypoint(id,longitude,latitude,at)
    local composition=current()
    local route=waypointRoute(composition,id)
    local point={lon=tonumber(longitude),lat=tonumber(latitude)}
    if not point.lon or not point.lat then error("Choose waypoint coordinates",2)end
    local points=waypointList(route)
    local index=tonumber(at)or #points+1
    if index<1 or index>#points+1 then error("Invalid waypoint index",2)end
    table.insert(points,index,point)
    local encoded=encodedWaypoints(points)
    return transaction(composition,"CartoRig: Add Route waypoint",function()
        input(route.node,"WaypointsEncoded",encoded)
        stamp(route.node,"Waypoints",points)
        return #points
    end)
end
function M.moveWaypoint(id,index,direction)
    local composition=current()
    local route=waypointRoute(composition,id)
    local points=waypointList(route)
    index=tonumber(index)
    local nextIndex=index and index+direction
    if not index or not nextIndex or index<1 or nextIndex<1 or
       nextIndex>#points or (direction~=1 and direction~=-1) then
        error("Cannot move waypoint outside its Route",2)
    end
    points[index],points[nextIndex]=points[nextIndex],points[index]
    local encoded=encodedWaypoints(points)
    return transaction(composition,"CartoRig: Reorder waypoint",function()
        input(route.node,"WaypointsEncoded",encoded)
        stamp(route.node,"Waypoints",points)
        return true
    end)
end
function M.removeWaypoint(id,index)
    local composition=current()
    local route=waypointRoute(composition,id)
    local points=waypointList(route)
    index=tonumber(index)
    if not index or index<1 or index>#points then error("Waypoint not selected",2)end
    table.remove(points,index)
    local encoded=encodedWaypoints(points)
    return transaction(composition,"CartoRig: Delete waypoint",function()
        input(route.node,"WaypointsEncoded",encoded)
        stamp(route.node,"Waypoints",points)
        return true
    end)
end
function M.reverseRoute(id)
    local composition=current()
    local route=waypointRoute(composition,id)
    local points=waypointList(route)
    local from={lon=tonumber(route.node:GetInput("FromLongitude")),
                lat=tonumber(route.node:GetInput("FromLatitude"))}
    local to={lon=tonumber(route.node:GetInput("ToLongitude")),
              lat=tonumber(route.node:GetInput("ToLatitude"))}
    if not from.lon or not from.lat or not to.lon or not to.lat then
        error("Route coordinates unavailable",2)
    end
    local reversed={}
    for i=#points,1,-1 do reversed[#reversed+1]=points[i] end
    local encoded=encodedWaypoints(reversed)
    return transaction(composition,"CartoRig: Reverse Route",function()
        input(route.node,"FromLongitude",to.lon)
        input(route.node,"FromLatitude",to.lat)
        input(route.node,"ToLongitude",from.lon)
        input(route.node,"ToLatitude",from.lat)
        input(route.node,"WaypointsEncoded",encoded)
        stamp(route.node,"Waypoints",reversed)
        return true
    end)
end
function M.rename(id,name)
    name=tostring(name or ""):match("^%s*(.-)%s*$")
    if #name<1 or #name>100 or name:find("[%z\1-\31]")then
        error("Name must contain 1–100 characters",2)
    end
    local composition=current()
    local item=objectFor(composition,id)
    if isLocked(composition,item) then error("Object is locked",2)end
    return transaction(composition,"CartoRig: Rename object",function()
        stamp(item.node,"DisplayName",name)
        return true
    end)
end
function M.visibility(id,visible)
    local composition=current()
    local item=objectFor(composition,id)
    if isLocked(composition,item) then error("Object is locked",2)end
    return transaction(composition,"CartoRig: Visibility",function()
        stamp(item.node,"Visible",visible==true)
        if item.role=="Group" then
            for _,entry in ipairs(owned(composition)) do
                if meta(entry.node,"ParentGroup")==id then
                    input(entry.node,"Visible",
                        (visible and entry.visible) and 1 or 0)
                end
            end
        elseif item.role~="Camera" then
            local parent=meta(item.node,"ParentGroup")
            local parentVisible=true
            if parent and parent~="" then
                parentVisible=objectFor(composition,parent).visible
            end
            input(item.node,"Visible",(visible and parentVisible) and 1 or 0)
        end
        return true
    end)
end
function M.lock(id,locked)
    local composition=current()
    local item=objectFor(composition,id)
    return transaction(composition,"CartoRig: Lock object",function()
        stamp(item.node,"Locked",locked==true)
        return true
    end)
end
function M.delete(id)
    local composition=current()
    local item=objectFor(composition,id)
    if item.role=="Base Map"or item.role=="Camera"then
        error("Base Map and Camera are required scene objects",2)
    end
    if isLocked(composition,item) then error("Object is locked",2)end
    if item.role=="Group" then return M.ungroup(id) end
    return transaction(composition,"CartoRig: Delete object",function()
        local base,camera,output=getCore(composition)
        local next=base
        for _,entry in ipairs(owned(composition)) do
            if entry.id~=id and entry.role~="Camera" and
               entry.role~="Base Map" and entry.role~="Group" then
                connect(entry.node,next)
                next=entry.node
            end
        end
        connect(output,next)
        assertHost(item.node:Delete(),"Delete CartoRig owned node")
        return true
    end)
end

-- Groups are organizational Fusion Underlays: a Group is not an extra
-- image effect and does not shift geographic coordinates or draw order.
function M.addGroup(name)
    name=tostring(name or "New Group")
    if #name<1 or #name>120 then error("Invalid group name",2)end
    local composition=current()
    getCore(composition)
    return transaction(composition,"CartoRig: Add Group",function()
        local node=assertHost(composition:AddTool("Underlay",0,0),
                              "Create organizational group")
        rename(node,unique(composition,"CR_Group"))
        setObjectData(composition,node,"Group",name,"","")
        trySelect(composition,node)
        return meta(node,"ObjectId")
    end)
end
local function effectiveVisibility(composition,entry)
    if not entry.visible then return false end
    local parent=meta(entry.node,"ParentGroup")
    if parent and parent~="" then
        local group=objectFor(composition,parent)
        if group.role=="Group" and not group.visible then return false end
    end
    return true
end
function M.setParent(id,groupId)
    local composition=current()
    local entry=objectFor(composition,id)
    if entry.role=="Base Map" or entry.role=="Camera" or entry.role=="Group" then
        error("Only authored visual objects can be placed into a group",2)
    end
    if isLocked(composition,entry) then error("This object is locked",2)end
    local group=objectFor(composition,groupId)
    if group.role~="Group" then error("Select a group destination",2)end
    return transaction(composition,"CartoRig: Group object",function()
        stamp(entry.node,"ParentGroup",groupId)
        input(entry.node,"Visible",effectiveVisibility(composition,entry) and 1 or 0)
        return true
    end)
end
function M.ungroup(id)
    local composition=current()
    local entry=objectFor(composition,id)
    if entry.role~="Group" then error("Select a group",2)end
    return transaction(composition,"CartoRig: Ungroup objects",function()
        for _,child in ipairs(owned(composition)) do
            if meta(child.node,"ParentGroup")==id then
                stamp(child.node,"ParentGroup","")
                input(child.node,"Visible",child.visible and 1 or 0)
            end
        end
        assertHost(entry.node:Delete(),"Remove Group after moving its children")
        return true
    end)
end
function M.move(id,direction)
    if direction~=-1 and direction~=1 then error("Choose Move Up or Move Down",2)end
    local composition=current()
    local a=objectFor(composition,id)
    if isLocked(composition,a) or a.role=="Camera" or a.role=="Base Map" then
        error("This object cannot be reordered",2)
    end
    local reorder={}
    for _,entry in ipairs(owned(composition)) do
        if entry.role~="Camera" and entry.role~="Base Map" and entry.role~="Group" then
            reorder[#reorder+1]=entry
        end
    end
    local index
    for i,item in ipairs(reorder) do if item.id==id then index=i;break end end
    if not index or not reorder[index+direction] then
        error("Object already at this draw order boundary",2)
    end
    local b=reorder[index+direction]
    if isLocked(composition,b) then error("Adjacent object is locked",2)end
    return transaction(composition,"CartoRig: Reorder object",function()
        stamp(a.node,"Order",b.z)
        stamp(b.node,"Order",a.z)
        rewire(composition)
        return true
    end)
end
return M
