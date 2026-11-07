-- CartoRig Edit-first authoring core, v0.5 developer preview.
-- This library is not itself a Scripts/Utility menu entry.
-- All user-facing actions are available from Edit > Workspace > Scripts.
-- Never uses HTTP or external geodata at runtime. Requires installed C++ OFX.
local M = {}
local info = debug.getinfo(1, "S")
local root = assert(info and info.source and info.source:sub(1,1) == "@"
    and info.source:sub(2):match("^(.*[\\/])"),
    "CartoRig authoring library must load from a real file")
local countries = assert(loadfile(root .. "countries.lua"))()

local palette = {
    {name="Gold", r=212,g=175,b=55},
    {name="Red", r=201,g=42,b=42},
    {name="Teal",r=46,g=186,b=181},
    {name="Blue",r=74,g=145,b=231},
    {name="White",r=230,g=235,b=240},
}
local aliases = {
    ["brasil"]="BRA",["venezuela"]="VEN",["estados unidos"]="USA",
    ["eua"]="USA",["alemanha"]="DEU",["franca"]="FRA",
    ["espanha"]="ESP",["inglaterra"]="GBR",["reino unido"]="GBR",
    ["china"]="CHN",["japao"]="JPN",["japão"]="JPN",
    ["india"]="IND",["índia"]="IND",["russia"]="RUS",
    ["rússia"]="RUS",["argentina"]="ARG",["chile"]="CHL",
    ["peru"]="PER",["colombia"]="COL",["colômbia"]="COL",
    ["canada"]="CAN",["canadá"]="CAN",["mexico"]="MEX",
    ["méxico"]="MEX",["ucrania"]="UKR",["ucrânia"]="UKR",
    ["australia"]="AUS",["austrália"]="AUS"
}
local function norm(s)
    s = tostring(s or ""):lower()
    s = s:gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," ")
    return s
end

function M.search(query)
    local needle = norm(query)
    if #needle < 2 or #needle > 100 then return nil, "Enter a location name (at least 2 characters)." end
    local alias = aliases[needle]
    for _,c in ipairs(countries) do
        if norm(c.name)==needle or norm(c.code)==needle or c.code==alias then
            return c
        end
    end
    local found={}
    for _,c in ipairs(countries) do
        if norm(c.name):find(needle,1,true) then found[#found+1]=c end
    end
    if #found==1 then return found[1] end
    if #found>1 then
        local suggestions={}
        for i=1,math.min(#found,5) do suggestions[#suggestions+1]=found[i].name end
        return nil, "Ambiguous location. Try: "..table.concat(suggestions,", ")
    end
    return nil, "Country not found in bundled offline catalog: "..query
end

local function required(value,label)
    if value==nil or value==false then error(label.." is not supported/available.",2) end
    return value
end
local function setInput(tool,key,value,frame)
    local result
    if frame==nil then result=tool:SetInput(key,value)
    else result=tool:SetInput(key,value,frame) end
    if result==false then error("Fusion refused '"..key.."'.",2) end
    return result
end
local function connect(to,key,from)
    if to:ConnectInput(key,from)==false then
        error("Fusion refused image connection '"..key.."'.",2)
    end
end
local function nameTool(tool,name)
    if tool:SetAttrs({TOOLS_Name=name})==false then error("Could not rename "..name,2) end
    local attrs=required(tool:GetAttrs(),"Get tool attributes")
    if attrs.TOOLS_Name~=name then error("Name verification failed: "..name,2) end
end
local function newNode(comp,registry,name,x,y)
    local node=required(comp:AddTool(registry,x,y),"Create "..registry)
    nameTool(node,name)
    return node
end
local function connectFilter(tool,source)
    -- Fusion hosts can advertise the same OFX source under different names.
    for _,socket in ipairs({"Source","Input","Image"}) do
        local ok,res=pcall(function() return tool:ConnectInput(socket,source) end)
        if ok and res~=false then return true end
    end
    error("Cannot connect CartoRig OpenFX to Fusion image source.",2)
end

local function resolveContext()
    local resolve = (bmd and bmd.scriptapp and bmd.scriptapp("Resolve")) or _G.resolve
    required(resolve,"DaVinci Resolve")
    local version=required(resolve:GetVersion(),"GetVersion")
    if tonumber(version[1])~=20 then error("This build targets DaVinci Resolve Studio 20.",2) end
    local pm=required(resolve:GetProjectManager(),"Project manager")
    local project=required(pm:GetCurrentProject(),"Current Resolve project")
    local timeline=required(project:GetCurrentTimeline(),"Active Edit timeline")
    return resolve,project,timeline
end

local function currentCartoRig()
    local resolve,project,timeline=resolveContext()
    local item=required(timeline:GetCurrentVideoItem(),
                        "Current video clip (place the playhead over a CartoRig map)")
    if tonumber(item:GetFusionCompCount() or 0)<1 then
        error("Current clip has no Fusion composition. Create a CartoRig Map first.",2)
    end
    local comp=required(item:GetFusionCompByIndex(1),"Fusion composition")
    local base=comp:FindTool("CR_Map_Base")
    local layers=comp:FindTool("CR_Map_LayersOut")
    if not base or not layers then
        error("Current clip is not a CartoRig authoring composition.",2)
    end
    return resolve,project,timeline,item,comp,base,layers
end

local function dialog(comp,title,fields)
    local fn=comp and comp.AskUser
    if type(fn)~="function" then error("Fusion AskUser dialog is unavailable in this Resolve host.",2) end
    return comp:AskUser(title,fields)
end

local function chosenColor(raw)
    local index=tonumber(raw)
    if index==nil then
        for _,color in ipairs(palette) do
            if color.name==raw then return color end
        end
        return palette[1]
    end
    -- AskUser Dropdown is zero-based on some hosts; one-based on others.
    -- Default value is explicitly 0, and all choices are UI presets.
    return palette[math.max(1,math.min(#palette,math.floor(index)+1))] or palette[1]
end

local function mapStack(comp,base)
    local biggest,tail=0,base
    local getList=comp.GetToolList
    if type(getList)=="function" then
        for _,tool in pairs(comp:GetToolList(false) or {}) do
            local attrs=tool:GetAttrs() or {}
            local n=tonumber((attrs.TOOLS_Name or ""):match("^CR_Layer_(%d+)_"))
            if n and n>biggest then biggest,tail=n,tool end
        end
    end
    return biggest+1,tail
end

local function syncCamera(layer,base)
    -- The country/route overlay must follow EVERY animated map-camera frame.
    -- Never silently create a country that drifts when the camera moves.
    for _,param in ipairs({"Longitude","Latitude","Zoom","Bearing",
                           "SceneTimeOffset","SceneTimeScale"}) do
        local input=layer[param]
        local reference=base[param]
        if not input or not reference or type(input.SetExpression)~="function" then
            error("Camera binding unavailable for "..param.."; object not inserted.",2)
        end
        local expression="CR_Map_Base."..param
        if input:SetExpression(expression)==false then
            error("Fusion rejected camera expression for "..param,2)
        end
        if type(input.GetExpression)=="function" then
            local readback=tostring(input:GetExpression() or "")
            if not readback:find(expression,1,true) then
                error("Camera expression readback failed for "..param,2)
            end
        end
    end
end

local function setColor(tool,color,group)
    if group=="route" then
        setInput(tool,"NativeRouteRed",color.r)
        setInput(tool,"NativeRouteGreen",color.g)
        setInput(tool,"NativeRouteBlue",color.b)
    else
        setInput(tool,"CustomMapColors",1)
        setInput(tool,"HighlightR",color.r)
        setInput(tool,"HighlightG",color.g)
        setInput(tool,"HighlightB",color.b)
    end
end

local function compTime(comp)
    local success,time=pcall(function() return tonumber(comp.CurrentTime) end)
    if success and time then return time end
    local attrs=comp:GetAttrs() or {}
    return tonumber(attrs.COMPN_CurrentTime) or tonumber(attrs.COMPN_GlobalStart) or 0
end
local function animate(tool,param,t,duration)
    if duration<=0 then setInput(tool,param,1) return end
    local fn=tool.AddModifier
    if type(fn)~="function" or fn(tool,param,"BezierSpline")==false then
        error("This Fusion OpenFX input cannot create a "..param.." keyframe curve.",2)
    end
    setInput(tool,param,0,t)
    setInput(tool,param,1,t+duration)
end

local function addLayer(comp,base,layers,kind,params)
    local index,tail=mapStack(comp,base)
    if index>128 then error("CartoRig map is limited to 128 authored geographic objects.",2) end
    local name=string.format("CR_Layer_%03d_%s",index,kind)
    local new=required(comp:AddTool("ofx.com.cartorig.native.overlay",index,1),
                       "CartoRig Overlay OpenFX in Fusion")
    local success,why=pcall(function()
        nameTool(new,name)
        if not new.ObjectLayerOnly then
            error("Installed CartoRig OpenFX is outdated: objects-only mode missing.")
        end
        setInput(new,"ObjectLayerOnly",1)
        setInput(new,"Opacity",1)
        setInput(new,"UseSceneCamera",0)
        syncCamera(new,base)
        if params.configure then params.configure(new) end
        -- Do not alter the visible graph until parameters and expressions pass.
        connectFilter(new,tail)
        connect(layers,"Input",new)
    end)
    if not success then
        pcall(function() connect(layers,"Input",tail) end)
        pcall(function() new:Delete() end)
        error(why,2)
    end
    return new
end

function M.create()
    local resolve,project,timeline=resolveContext()
    local item=required(timeline:InsertFusionCompositionIntoTimeline(),
                        "Insert Fusion Composition on Edit timeline")
    local count=tonumber(item:GetFusionCompCount() or 0)
    local comp
    if count>0 then comp=required(item:GetFusionCompByIndex(1),"Fusion Composition")
    else
        comp=required(item:AddFusionComp(),"Initialize Fusion Composition")
        if type(comp)=="boolean" then
            comp=required(item:GetFusionCompByIndex(1),"Read Fusion Composition")
        end
    end
    if comp:FindTool("CR_Map_Base") then error("CartoRig is already installed in this clip.",2) end
    local out=comp:FindTool("MediaOut1") or comp:FindToolByID("MediaOut")
    if not out then out=required(comp:AddTool("MediaOut",5,0),"Fusion MediaOut") end
    comp:StartUndo("Create CartoRig Map")
    local ok,err=pcall(function()
        local bg=newNode(comp,"Background","CR_Ocean",0,0)
        setInput(bg,"TopLeftRed",13/255)
        setInput(bg,"TopLeftGreen",30/255)
        setInput(bg,"TopLeftBlue",50/255)
        setInput(bg,"TopLeftAlpha",1)
        local map=newNode(comp,"ofx.com.cartorig.native.overlay","CR_Map_Base",1,0)
        connectFilter(map,bg)
        setInput(map,"Longitude",0)
        setInput(map,"Latitude",0)
        setInput(map,"Zoom",2.45)
        setInput(map,"Bearing",0)
        setInput(map,"Opacity",1)
        setInput(map,"SceneTimeOffset",0)
        setInput(map,"SceneTimeScale",1)
        setInput(map,"UseSceneCamera",0)
        local layers=newNode(comp,"Transform","CR_Map_LayersOut",3,0)
        connect(layers,"Input",map)
        connect(out,"Input",layers)
    end)
    comp:EndUndo(ok)
    if not ok then error(err,2) end
    -- Nothing is auto-keyframed and no default geographic story is inserted.
    resolve:OpenPage("edit")
    return "Map added to the current Edit timeline. Use CartoRig - Add Country or Add Route."
end

function M.addCountry()
    local _,_,_,_,comp,base,layers=currentCartoRig()
    local answers=dialog(comp,"CartoRig — Add Country",{
        {"Location","Text",Default="Brazil",Name="Search country / ISO3"},
        {"Color","Dropdown",Options={"Gold","Red","Teal","Blue","White"},Default=0},
        {"Reveal","Slider",Default=12,Min=0,Max=60,Integer=true,Name="Reveal duration (frames)"}
    })
    if not answers then return "Cancelled" end
    local match,err=M.search(answers.Location)
    if not match then error(err,2) end
    local color=chosenColor(answers.Color)
    local duration=math.floor(tonumber(answers.Reveal) or 0)
    comp:StartUndo("Add CartoRig country: "..match.name)
    local ok,result=pcall(function()
        return addLayer(comp,base,layers,match.code,{
            configure=function(tool)
                setInput(tool,"CountryA",match.code)
                setColor(tool,color,"country")
                animate(tool,"HighlightStrength",compTime(comp),duration)
            end})
    end)
    comp:EndUndo(ok)
    if not ok then error(result,2) end
    return "Country added: "..match.name.." ("..match.code.."). Independent color and animation."
end

function M.addRoute()
    local _,_,_,_,comp,base,layers=currentCartoRig()
    local answers=dialog(comp,"CartoRig — Add Route",{
        {"Origin","Text",Default="Brazil",Name="Start country"},
        {"Destination","Text",Default="Venezuela",Name="End country"},
        {"Color","Dropdown",Options={"Gold","Red","Teal","Blue","White"},Default=0},
        {"Reveal","Slider",Default=24,Min=0,Max=120,Integer=true,Name="Route draw duration (frames)"}
    })
    if not answers then return "Cancelled" end
    local a,errA=M.search(answers.Origin)
    local b,errB=M.search(answers.Destination)
    if not a then error(errA,2) end
    if not b then error(errB,2) end
    if a.code==b.code then error("Route needs two different countries.",2) end
    local color=chosenColor(answers.Color)
    local duration=math.floor(tonumber(answers.Reveal) or 0)
    comp:StartUndo("Add CartoRig route: "..a.code.." to "..b.code)
    local ok,result=pcall(function()
        return addLayer(comp,base,layers,"Route",{
            configure=function(tool)
                setInput(tool,"NativeRouteEnabled",1)
                setInput(tool,"RouteStartLongitude",a.lon)
                setInput(tool,"RouteStartLatitude",a.lat)
                setInput(tool,"RouteEndLongitude",b.lon)
                setInput(tool,"RouteEndLatitude",b.lat)
                setInput(tool,"NativeRouteWidth",4)
                setInput(tool,"NativeRouteCurve",18)
                setInput(tool,"RouteMarkers",1)
                setInput(tool,"RouteFromLabel",a.code)
                setInput(tool,"RouteToLabel",b.code)
                setColor(tool,color,"route")
                animate(tool,"RouteProgress",compTime(comp),duration)
            end})
    end)
    comp:EndUndo(ok)
    if not ok then error(result,2) end
    return "Route added: "..a.name.." → "..b.name.." (approximate country centers)."
end

local function cameraTrack(map,param,at,from,to,duration)
    if duration<=0 then
        setInput(map,param,to)
        return
    end
    local input=map[param]
    if not input then error("Missing camera input: "..param,2) end
    -- Create a spline once, so subsequent camera edits preserve earlier poses.
    local dataKey="CartoRig.CameraSpline."..param
    local compData=map:GetData(dataKey)
    if not compData then
        if map:AddModifier(param,"BezierSpline")==false then
            error("Cannot create Fusion camera curve "..param,2)
        end
        map:SetData(dataKey,1)
    end
    setInput(map,param,from,at)
    setInput(map,param,to,at+duration)
end

function M.setCamera()
    local _,_,_,_,comp,base=currentCartoRig()
    local answers=dialog(comp,"CartoRig — Camera",{
        {"Location","Text",Default="Brazil",Name="Focus on country / ISO3"},
        {"Zoom","Slider",Default=4.2,Min=0.5,Max=12,Name="Camera zoom"},
        {"Duration","Slider",Default=24,Min=0,Max=120,Integer=true,Name="Move duration (frames)"}
    })
    if not answers then return "Cancelled" end
    local location,err=M.search(answers.Location)
    if not location then error(err,2) end
    local zoom=tonumber(answers.Zoom) or 4.2
    local duration=math.floor(tonumber(answers.Duration) or 0)
    local t=compTime(comp)
    comp:StartUndo("CartoRig camera to "..location.name)
    local ok,reason=pcall(function()
        for _,p in ipairs({
            {key="Longitude",value=location.lon},
            {key="Latitude",value=location.lat},
            {key="Zoom",value=zoom},
        }) do
            local initial=tonumber(base:GetInput(p.key,t))
                or tonumber(base:GetInput(p.key)) or p.value
            cameraTrack(base,p.key,t,initial,p.value,duration)
        end
    end)
    comp:EndUndo(ok)
    if not ok then error(reason,2) end
    return "Camera focus: "..location.name.." ("..location.code..")."
end

local function writeLog(message)
    local folder=os.getenv("TEMP") or os.getenv("TMP")
    if not folder then return end
    pcall(function()
        local file=io.open(folder.."\\CartoRig-Editor-Result.txt","w")
        if file then file:write(message,"\n");file:close() end
    end)
end

function M.run(action)
    local method=({Create=M.create,Country=M.addCountry,Route=M.addRoute,
                   Camera=M.setCamera})[action]
    local ok,result=pcall(function()
        if not method then error("Unknown CartoRig operation: "..tostring(action)) end
        return method()
    end)
    local message=(ok and "OK: " or "ERROR: ")..tostring(result)
    writeLog(message)
    print("[CartoRig] "..message)
    if not ok then
        -- The UI Manager/OS dialog is not guaranteed in every host. Only use
        -- Fusion's supported AskUser when a current Fusion comp is available.
        pcall(function()
            local _,_,_,_,comp=currentCartoRig()
            dialog(comp,"CartoRig",{
                {"Message","Text",ReadOnly=true,Wrap=true,Lines=4,Default=message}
            })
        end)
    end
    return ok,result
end
return M
