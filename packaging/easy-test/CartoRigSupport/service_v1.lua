-- CartoRig 1.0: a single offline geographic authoring model for Resolve 20.
-- Fusion is an implementation detail; public UI never asks users for ISO3.
-- This is an Edit/host integration candidate. No undocumented host methods
-- are assumed: scene identification fails closed on ambiguity.
local M={}
local info=assert(debug.getinfo(1,"S"))
local root=assert(info.source:sub(1,1)=="@" and info.source:sub(2):match("^(.*[\\/])"))
local countries=assert(loadfile(root.."countries.lua"))()

local function requireHost(x,name)
    if x==nil or x==false then error(name.." unavailable in this Resolve host",3) end
    return x
end
local function set(tool,name,value,frame)
    local ok
    if frame~=nil then ok=tool:SetInput(name,value,frame)
    else ok=tool:SetInput(name,value) end
    if ok==false then error("Unable to write '"..name.."' to the CartoRig render node",3) end
end
local function escape(s)
    s=tostring(s or "")
    if #s>250 or s:find("[%z\1-\31]") then error("Invalid geographic text",3) end
    return '"'..s:gsub("\\","\\\\"):gsub('"','\\"')..'"'
end
local function bounded(v,min,max,name)
    v=tonumber(v)
    if not v or v~=v or v<min or v>max then error("Invalid "..name,3) end
    return v
end
local function rgb(hex)
    hex=tostring(hex or "")
    if not hex:match("^#%x%x%x%x%x%x$") then
        error("Use a six-digit hex color such as #C92A2A",3)
    end
    return tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16)
end
local function alpha(v)
    return math.floor(bounded(v or 100,0,100,"opacity")*2.55+0.5)
end
local function regionJson(meta,preservedKeys)
    local r,g,b=rgb(meta.fill)
    local sr,sg,sb=rgb(meta.stroke or meta.fill)
    return '[{"feature_key":'..escape(meta.key)..',"kind":'..escape(meta.kind)..
        ',"name":'..escape(meta.name)..',"parent":'..escape(meta.parent or "")..
        ',"source_layer":'..escape(meta.sourceLayer)..',"scale":'..
        escape(meta.scale or "10m")..',"rowid":'..tostring(meta.rowid)..
        ',"fill":['..r..','..g..','..b..','..alpha(meta.opacity)..']'..
        ',"stroke":['..sr..','..sg..','..sb..',255]'..
        ',"visible":'..tostring(meta.visible~=false)..',"color_keys":'..
        (preservedKeys or "[]")..'}]'
end
local function currentRegionKeys(tool)
    -- Preserve user-authored native RGBA keyframes when changing static style.
    -- Lua balanced-pattern matching handles nested [rgba] arrays.
    local existing=tostring(tool:GetInput("GeographicRegionSaved") or "")
    local keys=existing:match('"color_keys"%s*:%s*(%b[])')
    return keys or "[]"
end
local function serializeMarker(meta)
    local r,g,b=rgb(meta.fill)
    return '{"schemaVersion":1,"title":"CartoRig Marker","camera":'..
           '{"lon":0,"lat":0,"zoom":1.3,"bearing":0},'..
           '"style":{"transparent":true},'..
           '"markers":[{"id":'..escape(meta.key)..',"label":'..
           escape(meta.label or "")..',"lon":'..tostring(meta.lon)..
           ',"lat":'..tostring(meta.lat)..',"showPin":'..
           tostring(meta.showPin~=false)..',"size":'..
           tostring(meta.size or 6)..',"color":"#'..
           string.format("%02X%02X%02X",r,g,b)..
           '"}],"routes":[],"highlights":[],"cameraKeys":[]}'
end
local function resolve()
    local r=(bmd and bmd.scriptapp and bmd.scriptapp("Resolve")) or _G.resolve
    requireHost(r,"Resolve")
    local version=requireHost(r:GetVersion(),"Resolve version")
    if tonumber(version[1])~=20 then
        error("CartoRig 1.0 integration requires DaVinci Resolve Studio 20",2)
    end
    local pm=requireHost(r:GetProjectManager(),"Project manager")
    local project=requireHost(pm:GetCurrentProject(),"Current project")
    local timeline=requireHost(project:GetCurrentTimeline(),"Current timeline")
    return r,pm,project,timeline
end
local function compOf(item)
    if not item or type(item.GetFusionCompCount)~="function" or
       tonumber(item:GetFusionCompCount() or 0)<1 then return nil end
    local comp=item:GetFusionCompByIndex(1)
    if not comp then return nil end
    if comp:FindTool("CR_Map_Base") and comp:FindTool("CR_Map_LayersOut") then
        return comp
    end
    return nil
end
function M.scenes()
    local _,_,_,timeline=resolve()
    if type(timeline.GetTrackCount)~="function" or
       type(timeline.GetItemListInTrack)~="function" then
        error("Clip enumeration not exposed by Resolve scripting; cannot select safely",2)
    end
    local result={}
    for track=1,tonumber(timeline:GetTrackCount("video") or 0) do
        for _,item in pairs(timeline:GetItemListInTrack("video",track) or {}) do
            local comp=compOf(item)
            if comp then
                local start=tonumber(item:GetStart() or 0)
                local label="V"..track.."  |  "..tostring(item:GetName() or "CartoRig")..
                    "  |  frame "..tostring(start)
                result[#result+1]={item=item,comp=comp,track=track,
                                   start=start,label=label}
            end
        end
    end
    table.sort(result,function(a,b)
        if a.track~=b.track then return a.track>b.track end
        return a.start<b.start
    end)
    return result
end
local function sceneAt(index)
    local list=M.scenes()
    local n=tonumber(index)
    if not n or n<1 or n>#list then
        error("Select a CartoRig clip explicitly before editing",3)
    end
    local scene=list[n]
    return scene.comp,scene.comp:FindTool("CR_Map_Base"),
           scene.comp:FindTool("CR_Map_LayersOut")
end
local function objectList(comp)
    local result={}
    for _,node in pairs(comp:GetToolList(false) or {}) do
        local attrs=node:GetAttrs() or {}
        local n=tonumber((attrs.TOOLS_Name or ""):match("^CR_Layer_(%d+)_"))
        if n then
            result[#result+1]={index=n,order=tonumber(node:GetData("CartoRig.V1Order")) or n,
                node=node,meta=node:GetData("CartoRig.V1Object")}
        end
    end
    table.sort(result,function(a,b)
        if a.order==b.order then return a.index<b.index end
        return a.order<b.order
    end)
    return result
end
function M.objects(sceneIndex)
    local comp=sceneAt(sceneIndex)
    return objectList(comp)
end
local function syncCamera(layer,base)
    for _,name in ipairs({"Longitude","Latitude","Zoom","Bearing",
                          "SceneTimeOffset","SceneTimeScale"}) do
        if not layer[name] or not base[name] or
           type(layer[name].SetExpression)~="function" then
            error("Host cannot bind geographic object to camera: "..name,3)
        end
        if layer[name]:SetExpression("CR_Map_Base."..name)==false then
            error("Failed to bind object camera: "..name,3)
        end
    end
end
local function connectImage(to,source)
    for _,key in ipairs({"Source","Input","Image"}) do
        local ok,result=pcall(function()return to:ConnectInput(key,source)end)
        if ok and result~=false then return end
    end
    error("Fusion cannot connect CartoRig image nodes",3)
end
local function rewire(comp,layers,base)
    local tail=base
    for _,entry in ipairs(objectList(comp)) do
        connectImage(entry.node,tail)
        tail=entry.node
    end
    if layers:ConnectInput("Input",tail)==false then
        error("Unable to rebuild CartoRig object composition",3)
    end
end
local function atomic(comp,label,action)
    requireHost(comp.StartUndo,"Fusion StartUndo")
    comp:StartUndo(label)
    local ok,result=pcall(action)
    comp:EndUndo(ok)
    if not ok then error(result,3) end
    return result
end
local function addObject(sceneIndex,kind,meta,configure)
    local comp,base,layers=sceneAt(sceneIndex)
    return atomic(comp,"CartoRig: Add "..kind,function()
        local entries=objectList(comp)
        if #entries>=128 then error("Maximum CartoRig objects reached") end
        local index=1
        for _,entry in ipairs(entries) do
            index=math.max(index,entry.index+1)
        end
        local node=requireHost(comp:AddTool("ofx.com.cartorig.native.overlay",index,1),
                               "CartoRig OpenFX Overlay")
        local ok,result=pcall(function()
            local name=string.format("CR_Layer_%03d_%s",index,kind)
            requireHost(node:SetAttrs({TOOLS_Name=name}),"Rename object")
            set(node,"ObjectLayerOnly",1)
            set(node,"UseSceneCamera",0)
            set(node,"Opacity",1)
            syncCamera(node,base)
            configure(node)
            if node:SetData("CartoRig.V1Order",index)==false then
                error("Host refused object ordering metadata")
            end
            if node:SetData("CartoRig.V1Object",meta)==false then
                error("Host refused to store object metadata")
            end
            rewire(comp,layers,base)
        end)
        if not ok then pcall(function()node:Delete()end);error(result) end
        return node
    end)
end
function M.create()
    local core=assert(loadfile(root.."core.lua"))()
    return core.create()
end
local function normalized(text)
    text=tostring(text or ""):lower():gsub("^%s+",""):gsub("%s+$","")
    return text:gsub("á","a"):gsub("à","a"):gsub("ã","a"):gsub("â","a")
               :gsub("é","e"):gsub("ê","e"):gsub("í","i")
               :gsub("ó","o"):gsub("ô","o"):gsub("õ","o"):gsub("ú","u")
               :gsub("ç","c")
end
local function pathData()
    local base=(os.getenv("LOCALAPPDATA") or "").."\\CartoRigNative\\NaturalEarth\\vector\\"
    local index=base.."catalog.sqlite"
    local primary=base.."natural_earth_vector.gpkg"
    local secondary=base.."supplements.gpkg"
    local exe=root.."cartorig_ne_lookup.exe"
    local f=io.open(index,"rb");if not f then return nil end;f:close()
    f=io.open(exe,"rb");if not f then return nil end;f:close()
    return index,primary,secondary,exe
end
local function findOfficial(query,kind)
    local index,primary,secondary,exe=pathData()
    if not index then return {} end
    if tostring(query):find('["&|<>^%%!]') or #query>100 or
       #query<2 or tostring(query):find("[%z\1-\31]") then
        error("Invalid location query",3)
    end
    local results={}
    -- Exact executable and database paths are local. A fixed command line
    -- whitelist refuses Windows shell metacharacters in user-supplied text.
    for _,gpkg in ipairs({primary,secondary}) do
        local f=io.open(gpkg,"rb")
        if f then f:close()
            local output=(os.getenv("TEMP") or os.getenv("TMP") or ".")..
                       "\\CartoRigSearch_"..tostring(os.time()).."_"..
                       tostring(math.random(1000000))..".txt"
            local cmd='cmd /D /S /C ""'..exe..'" "'..index..'" "'..
                      kind..'" "'..query..'" "'..gpkg..'" > "'..
                      output..'" 2>NUL"'
            local status=os.execute(cmd)
            if status==true or status==0 then
                local file=io.open(output,"rb")
                if file then
                    for line in file:lines() do
                        local fields={}
                        for column in (line.."\t"):gmatch("([^\t]*)\t") do
                            fields[#fields+1]=column
                        end
                        if #fields>=10 and tonumber(fields[7]) and
                           tonumber(fields[9]) and tonumber(fields[10]) then
                            results[#results+1]={
                                kind=fields[1],name=fields[2],parent=fields[3],
                                geometry=fields[4],sourceLayer=fields[5],
                                key=fields[6],rowid=tonumber(fields[7]),
                                scale=fields[8],lon=tonumber(fields[9]),
                                lat=tonumber(fields[10]),isOfficial=true
                            }
                        end
                    end
                    file:close()
                end
            end
            os.remove(output)
            if #results>0 then break end
        end
    end
    return results
end
function M.search(query,requestedKind)
    query=tostring(query or "")
    if #query<2 or #query>100 then
        error("Enter 2–100 characters to search an offline location",2)
    end
    local selected=requestedKind or "all"
    local result,seen={},{}
    for _,kind in ipairs({"country","state","city","continent"}) do
        if selected=="all" or selected==kind then
            for _,location in ipairs(findOfficial(query,kind)) do
                local key=location.kind.."|"..normalized(location.name)..
                          "|" .. normalized(location.parent)
                if not seen[key] then
                    seen[key]=true;result[#result+1]=location
                end
            end
        end
    end
    if selected=="all" or selected=="country" then
        for _,c in ipairs(countries) do
            if normalized(c.name):find(normalized(query),1,true) or
               (normalized(query)=="brasil" and c.code=="BRA") then
                local key="country|"..normalized(c.name).."|"
                local already=false
                for _,entry in ipairs(result) do
                    if entry.kind=="country" and normalized(entry.name)==normalized(c.name) then
                        already=true;break
                    end
                end
                if not already and not seen[key] then
                    result[#result+1]={kind="country",name=c.name,parent="",
                        code=c.code,lon=c.lon,lat=c.lat,isOfficial=false,
                        geometry="POLYGON"}
                    seen[key]=true
                end
            end
        end
    end
    return result
end
function M.addRegion(sceneIndex,location,color,stroke,opacity)
    if not location or (location.kind~="country" and location.kind~="state" and
        location.kind~="continent") then
        error("Region requires published polygon geometry; cities are points",2)
    end
    if location.isOfficial and not
       tostring(location.geometry):upper():find("POLYGON",1,true) and
       location.kind~="continent" then
        error("Selected Natural Earth result has no region polygon",2)
    end
    local meta={type="Region",kind=location.kind,name=location.name,
        parent=location.parent or "",key=location.key or location.code,
        code=location.code,sourceLayer=location.sourceLayer,
        rowid=location.rowid,scale=location.scale,fill=color or "#C92A2A",
        stroke=stroke or color or "#C92A2A",opacity=opacity or 100,
        visible=true}
    rgb(meta.fill);rgb(meta.stroke);alpha(meta.opacity)
    if not location.isOfficial and not location.code then
        error("Official polygon data unavailable; cannot invent geometry",2)
    end
    return addObject(sceneIndex,"Region",meta,function(tool)
        if location.isOfficial then
            set(tool,"UseInstalledNaturalEarth",1)
            set(tool,"GeographicRegionSaved",regionJson(meta))
        else
            set(tool,"CountryA",location.code)
            local r,g,b=rgb(meta.fill)
            set(tool,"CustomMapColors",1)
            set(tool,"HighlightR",r);set(tool,"HighlightG",g)
            set(tool,"HighlightB",b)
            set(tool,"HighlightAlpha",255)
            local sr,sg,sb=rgb(meta.stroke)
            set(tool,"BorderR",sr);set(tool,"BorderG",sg);set(tool,"BorderB",sb)
            set(tool,"HighlightStrength",alpha(meta.opacity)/255)
        end
    end)
end
function M.addMarker(sceneIndex,location,label,color)
    if not location or not tonumber(location.lon) or not tonumber(location.lat) then
        error("Selected point has no verified geographic coordinates",2)
    end
    local meta={type="Marker",name=location.name,label=label or "",
                key="marker-"..tostring(os.time()).."-"..tostring(math.random(100000)),
                lon=location.lon,lat=location.lat,fill=color or "#D4AF37",
                visible=true,opacity=100,size=6}
    rgb(meta.fill)
    meta.showPin=true
    return addObject(sceneIndex,"Marker",meta,function(tool)
        set(tool,"EmbeddedSceneJSON",serializeMarker(meta))
    end)
end
function M.addLabel(sceneIndex,location,text,color)
    if not location or not tonumber(location.lon) or not tonumber(location.lat) then
        error("Cannot anchor label without real geographic coordinates",2)
    end
    text=tostring(text or location.name or "")
    if #text<1 or #text>250 then error("Label length must be 1–250 characters",2) end
    local meta={type="Label",name="Label: "..text,label=text,
        key="label-"..tostring(os.time()).."-"..tostring(math.random(100000)),
        lon=location.lon,lat=location.lat,fill=color or "#D4AF37",
        visible=true,opacity=100,size=6,showPin=false}
    rgb(meta.fill)
    return addObject(sceneIndex,"Label",meta,function(tool)
        set(tool,"EmbeddedSceneJSON",serializeMarker(meta))
    end)
end
local function focusAt(sceneIndex,location,zoom,duration)
    if not location or not tonumber(location.lon) or not tonumber(location.lat) then
        error("Location has no coordinate; a state is not a city point",2)
    end
    local comp,base=sceneAt(sceneIndex)
    zoom=bounded(zoom or 4.2,0,18,"camera zoom")
    duration=bounded(duration or 0,0,10000,"animation duration")
    local when=tonumber(comp.CurrentTime) or 0
    if duration==0 and (base:GetData("CartoRig.V1Animated.Longitude") or
        base:GetData("CartoRig.V1Animated.Latitude") or
        base:GetData("CartoRig.V1Animated.Zoom")) then
        error("Camera already has animation. Use Animate at the playhead; "..
              "Focus cannot silently overwrite an animated track",2)
    end
    return atomic(comp,duration>0 and "CartoRig: Animate camera" or
                  "CartoRig: Focus camera",function()
        for _,property in ipairs({
            {"Longitude",location.lon},{"Latitude",location.lat},{"Zoom",zoom}
        }) do
            if duration>0 then
                local input=base[property[1]]
                if not input or type(base.AddModifier)~="function" then
                    error("Cannot animate camera in this Fusion host")
                end
                local key="CartoRig.V1Animated."..property[1]
                if not base:GetData(key) then
                    if base:AddModifier(property[1],"BezierSpline")==false then
                        error("Host refused camera keyframe spline")
                    end
                    base:SetData(key,true)
                end
                local from=tonumber(base:GetInput(property[1],when)) or
                           tonumber(base:GetInput(property[1])) or property[2]
                set(base,property[1],from,when)
                set(base,property[1],property[2],when+duration)
            else
                set(base,property[1],property[2])
            end
        end
    end)
end
function M.focus(scene,location,zoom)return focusAt(scene,location,zoom,0) end
function M.animateCamera(scene,location,zoom,frames)
    return focusAt(scene,location,zoom,bounded(frames,1,10000,"duration"))
end
local function geoPoint(location,manual)
    if location.kind=="country" or location.kind=="state" or
       location.kind=="continent" then
        if not manual then
            error("Area destination requires an explicitly chosen coordinate; "..
                  "it is not automatically a city or centroid",3)
        end
        return {lon=bounded(manual.lon,-180,180,"longitude"),
                lat=bounded(manual.lat,-85,85,"latitude")}
    end
    return {lon=bounded(location.lon,-180,180,"longitude"),
            lat=bounded(location.lat,-85,85,"latitude")}
end
function M.addRoute(sceneIndex,from,to,options)
    if not from or not to then error("Choose both route endpoints",2) end
    options=options or {}
    local a=geoPoint(from,options.fromPoint)
    local b=geoPoint(to,options.toPoint)
    local meta={type="Route",name=from.name.." → "..to.name,
        key="route-"..tostring(os.time()).."-"..tostring(math.random(100000)),
        from=from.name,to=to.name,lon=a.lon,lat=a.lat,
        endLon=b.lon,endLat=b.lat,
        fill=options.color or "#D4AF37",opacity=options.opacity or 100,
        width=bounded(options.width or 4,.5,30,"route width"),
        curve=bounded(options.curve or 0,-100,100,"route curve"),
        arrowhead=options.arrowhead~=false,visible=true}
    rgb(meta.fill);alpha(meta.opacity)
    return addObject(sceneIndex,"Route",meta,function(tool)
        set(tool,"NativeRouteEnabled",1)
        set(tool,"RouteStartLongitude",a.lon)
        set(tool,"RouteStartLatitude",a.lat)
        set(tool,"RouteEndLongitude",b.lon)
        set(tool,"RouteEndLatitude",b.lat)
        set(tool,"NativeRouteCurve",meta.curve)
        set(tool,"NativeRouteWidth",meta.width)
        set(tool,"NativeRouteArrowhead",meta.arrowhead and 1 or 0)
        set(tool,"RouteMarkers",0)
        set(tool,"RouteProgress",1) -- no animation without explicit user request
        local r,g,blue=rgb(meta.fill)
        set(tool,"NativeRouteRed",r)
        set(tool,"NativeRouteGreen",g)
        set(tool,"NativeRouteBlue",blue)
        set(tool,"Opacity",alpha(meta.opacity)/255)
    end)
end
function M.animateRoute(sceneIndex,objectIndex,duration)
    duration=bounded(duration,1,10000,"route animation duration")
    local comp=sceneAt(sceneIndex)
    local object=M.objects(sceneIndex)[objectIndex]
    if not object or not object.meta or object.meta.type~="Route" then
        error("Choose an existing Route",2)
    end
    return atomic(comp,"CartoRig: Animate route",function()
        local time=tonumber(comp.CurrentTime) or 0
        if type(object.node.AddModifier)~="function" or
           object.node:AddModifier("RouteProgress","BezierSpline")==false then
            error("RouteProgress keyframes unsupported in this host")
        end
        set(object.node,"RouteProgress",0,time)
        set(object.node,"RouteProgress",1,time+duration)
    end)
end
function M.style(sceneIndex,objectIndex,hex,stroke,opacity)
    local comp,base=sceneAt(sceneIndex)
    local entry=M.objects(sceneIndex)[objectIndex]
    if not entry or not entry.meta then error("Select a CartoRig object",2) end
    local m=entry.meta
    rgb(hex);rgb(stroke or hex);alpha(opacity)
    return atomic(comp,"CartoRig: Style "..m.type,function()
        -- Routes use Stroke; polygons use Fill + Stroke. The UI does not
        -- expose two competing meanings for the same property.
        m.fill=m.type=="Route" and (stroke or hex) or hex
        m.stroke=stroke or hex;m.opacity=opacity
        if m.type=="Region" then
            if m.sourceLayer then
                set(entry.node,"GeographicRegionSaved",
                    regionJson(m,currentRegionKeys(entry.node)))
            else
                local r,g,b=rgb(hex)
                set(entry.node,"CustomMapColors",1)
                set(entry.node,"HighlightR",r)
                set(entry.node,"HighlightG",g)
                set(entry.node,"HighlightB",b)
                set(entry.node,"HighlightAlpha",255)
                local sr,sg,sb=rgb(m.stroke)
                set(entry.node,"BorderR",sr);set(entry.node,"BorderG",sg)
                set(entry.node,"BorderB",sb)
                set(entry.node,"HighlightStrength",alpha(opacity)/255)
            end
        elseif m.type=="Route" then
            local r,g,b=rgb(hex)
            set(entry.node,"NativeRouteRed",r)
            set(entry.node,"NativeRouteGreen",g)
            set(entry.node,"NativeRouteBlue",b)
            set(entry.node,"Opacity",alpha(opacity)/255)
        elseif m.type=="Marker" or m.type=="Label" then
            set(entry.node,"EmbeddedSceneJSON",serializeMarker(m))
            set(entry.node,"Opacity",alpha(opacity)/255)
        end
        entry.node:SetData("CartoRig.V1Object",m)
    end)
end
function M.backgroundMode(sceneIndex,transparent)
    local comp=sceneAt(sceneIndex)
    local ocean=comp:FindTool("CR_Ocean")
    if not ocean then error("CartoRig background source is missing",2) end
    return atomic(comp,"CartoRig: Background transparency",function()
        set(ocean,"TopLeftAlpha",transparent and 0 or 1)
        if ocean:SetData("CartoRig.V1TransparentOcean",transparent and true or false)==false then
            error("Cannot persist background transparency mode")
        end
    end)
end
function M.baseStyle(sceneIndex,part,hex)
    if part~="land" and part~="ocean" and part~="border" then
        error("Select land, ocean or border style",2)
    end
    local comp,base=sceneAt(sceneIndex)
    local r,g,b=rgb(hex)
    local prefix=part=="land" and "Land" or
                 part=="ocean" and "Ocean" or "Border"
    return atomic(comp,"CartoRig: Base map "..part,function()
        set(base,"CustomMapColors",1)
        set(base,prefix.."R",r)
        set(base,prefix.."G",g)
        set(base,prefix.."B",b)
    end)
end
function M.hide(sceneIndex,objectIndex,hide)
    local comp=sceneAt(sceneIndex)
    local entry=M.objects(sceneIndex)[objectIndex]
    if not entry or not entry.meta then error("Select a CartoRig object",2) end
    return atomic(comp,hide and "CartoRig: Hide object" or
                  "CartoRig: Show object",function()
        entry.meta.visible=not hide
        if entry.meta.type=="Region" and entry.meta.sourceLayer then
            set(entry.node,"GeographicRegionSaved",regionJson(entry.meta))
        else
            set(entry.node,"Opacity",hide and 0 or alpha(entry.meta.opacity or 100)/255)
        end
        entry.node:SetData("CartoRig.V1Object",entry.meta)
    end)
end
function M.delete(sceneIndex,objectIndex)
    local comp,base,layers=sceneAt(sceneIndex)
    local entry=M.objects(sceneIndex)[objectIndex]
    if not entry then error("Select the object to delete",2) end
    return atomic(comp,"CartoRig: Delete object",function()
        -- Reconnect downstream without touching any user-authored node.
        local ordered=objectList(comp)
        local tail=base
        for _,e in ipairs(ordered) do
            if e.node~=entry.node then
                connectImage(e.node,tail);tail=e.node
            end
        end
        if layers:ConnectInput("Input",tail)==false then
            error("Cannot detach object safely; deletion cancelled")
        end
        if entry.node:Delete()==false then
            error("Fusion refused object deletion")
        end
    end)
end

function M.renameObject(sceneIndex,objectIndex,newName)
    newName=tostring(newName or ""):match("^%s*(.-)%s*$")
    if #newName<1 or #newName>120 or newName:find("[%z\1-\31]") then
        error("Name must contain 1–120 printable characters",2)
    end
    local comp=sceneAt(sceneIndex)
    local entry=M.objects(sceneIndex)[objectIndex]
    if not entry or not entry.meta then error("Select an existing object",2) end
    return atomic(comp,"CartoRig: Rename object",function()
        entry.meta.name=newName
        if entry.node:SetData("CartoRig.V1Object",entry.meta)==false then
            error("Cannot persist the new name")
        end
    end)
end
function M.moveObject(sceneIndex,objectIndex,delta)
    if delta~=-1 and delta~=1 then error("Invalid reorder direction",2) end
    local comp,base,layers=sceneAt(sceneIndex)
    local entries=objectList(comp)
    local a=entries[objectIndex]
    local b=entries[objectIndex+delta]
    if not a or not b then error("Object is already at the stack edge",2) end
    return atomic(comp,"CartoRig: Reorder objects",function()
        local aOrder,bOrder=a.order,b.order
        if a.node:SetData("CartoRig.V1Order",bOrder)==false or
           b.node:SetData("CartoRig.V1Order",aOrder)==false then
            error("Host refused layer reordering")
        end
        rewire(comp,layers,base)
    end)
end
function M.editRoute(sceneIndex,objectIndex,from,to,options)
    local comp=sceneAt(sceneIndex)
    local entry=M.objects(sceneIndex)[objectIndex]
    if not entry or not entry.meta or entry.meta.type~="Route" then
        error("Select an existing Route",2)
    end
    options=options or {}
    local a=from and geoPoint(from,options.fromPoint) or
        {lon=entry.meta.lon,lat=entry.meta.lat}
    local b=to and geoPoint(to,options.toPoint) or
        {lon=entry.meta.endLon,lat=entry.meta.endLat}
    local curve=bounded(options.curve or entry.meta.curve,-100,100,"route curvature")
    local width=bounded(options.width or entry.meta.width,.5,30,"route width")
    local arrowhead=options.arrowhead
    if arrowhead==nil then arrowhead=entry.meta.arrowhead end
    return atomic(comp,"CartoRig: Edit route",function()
        local node=entry.node
        set(node,"RouteStartLongitude",a.lon)
        set(node,"RouteStartLatitude",a.lat)
        set(node,"RouteEndLongitude",b.lon)
        set(node,"RouteEndLatitude",b.lat)
        set(node,"NativeRouteCurve",curve)
        set(node,"NativeRouteWidth",width)
        set(node,"NativeRouteArrowhead",arrowhead and 1 or 0)
        -- Do not touch RouteProgress / BezierSpline: preserve authored keyframes.
        entry.meta.lon=a.lon;entry.meta.lat=a.lat
        entry.meta.endLon=b.lon;entry.meta.endLat=b.lat
        entry.meta.curve=curve;entry.meta.width=width
        entry.meta.arrowhead=arrowhead
        if from then entry.meta.from=from.name end
        if to then entry.meta.to=to.name end
        entry.meta.name=entry.meta.from.." → "..entry.meta.to
        if node:SetData("CartoRig.V1Object",entry.meta)==false then
            error("Failed to persist edited route")
        end
    end)
end
function M.duplicateObject(sceneIndex,objectIndex)
    local original=M.objects(sceneIndex)[objectIndex]
    if not original or not original.meta then error("Choose an existing object",2) end
    local meta=original.meta
    if meta.type=="Region" then
        -- New layer, identical publisher geometry, independently editable style.
        local loc={kind=meta.kind,name=meta.name,parent=meta.parent,
            code=meta.code,isOfficial=meta.sourceLayer~=nil,
            geometry="MULTIPOLYGON",sourceLayer=meta.sourceLayer,
            rowid=meta.rowid,scale=meta.scale,key=meta.key}
        return M.addRegion(sceneIndex,loc,meta.fill,meta.stroke,meta.opacity)
    elseif meta.type=="Marker" or meta.type=="Label" then
        local loc={kind="city",name=meta.name,lon=meta.lon,lat=meta.lat}
        if meta.type=="Label" then
            return M.addLabel(sceneIndex,loc,meta.label,meta.fill)
        end
        return M.addMarker(sceneIndex,loc,meta.label,meta.fill)
    elseif meta.type=="Route" then
        local from={kind="city",name=meta.from,lon=meta.lon,lat=meta.lat}
        local to={kind="city",name=meta.to,lon=meta.endLon,lat=meta.endLat}
        return M.addRoute(sceneIndex,from,to,{
            color=meta.fill,curve=meta.curve,width=meta.width,
            arrowhead=meta.arrowhead,opacity=meta.opacity})
    end
    error("Unsupported object type for duplication",2)
end
return M
