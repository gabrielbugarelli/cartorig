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
    -- Some Fusion versions return nil for success; only explicit false
    -- signals rejection. Never execute a mutation after rejection.
    local started=composition:StartUndo(title)
    if started==false then error("Fusion refused to start Undo: "..title,3) end
    local ok,result=pcall(fn)
    local closed,endResult=pcall(function()return composition:EndUndo(ok)end)
    if not ok then error(result,3) end
    if not closed then error(endResult,3) end
    if endResult==false then
        error("Fusion failed to finalize Undo: "..title,3)
    end
    return result
end
function M.composition()return current()end
local function coreNodes(composition)
    local map,camera,output=nil,nil,nil
    local counts={map=0,camera=0,output=0}
    eachTool(composition,function(tool)
        local role=meta(tool,"Role")
        if role=="Base Map" then
            map=tool;counts.map=counts.map+1
        elseif role=="Camera" then
            camera=tool;counts.camera=counts.camera+1
        elseif role=="Stack Output" then
            output=tool;counts.output=counts.output+1
        end
    end)
    -- Output nodes created by older development builds have no metadata.
    -- This fallback is only allowed while there is a unique identified
    -- Base Map and Camera; never bind to arbitrary user-owned pipes.
    if counts.output==0 and counts.map==1 and counts.camera==1 then
        output=composition:FindTool("CR_Stack_Output")
        if output then counts.output=1 end
    end
    return map,camera,output,counts
end
function M.state(composition)
    composition=composition or current()
    local map,camera,output,counts=coreNodes(composition)
    local anyCartoRig=false
    local duplicated=false
    local ids={}
    eachTool(composition,function(tool)
        local id=meta(tool,"ObjectId")
        local role=meta(tool,"Role")
        if id or role then anyCartoRig=true end
        if id then
            if ids[id] then duplicated=true end
            ids[id]=true
        end
    end)
    if duplicated or counts.map>1 or counts.camera>1 or counts.output>1 or
       (anyCartoRig and not(map and camera and output)) then
        return "SCENE_BROKEN"
    end
    if not map or not camera or not output then return "COMP_WITHOUT_CARTORIG" end
    if meta(map,"Initialized")~=true or meta(map,"SchemaVersion")~=1 then
        return "SCENE_BROKEN"
    end
    -- The registry is an independent persisted ledger on Base Map. It
    -- detects authoring nodes physically removed by an external Node Editor
    -- action, instead of silently accepting a smaller object list.
    local registry=meta(map,"ObjectRegistry")
    if registry~=nil then
        if type(registry)~="table" then return "SCENE_BROKEN" end
        local actual={}
        eachTool(composition,function(tool)
            local id=meta(tool,"ObjectId")
            local role=meta(tool,"Role")
            if id and role~="Base Map" and role~="Camera" then
                actual[id]=role
            end
        end)
        for id,role in pairs(registry) do
            if type(id)~="string" or type(role)~="string" or
               actual[id]~=role then return "SCENE_BROKEN" end
            actual[id]=nil
        end
        if next(actual)~=nil then return "SCENE_BROKEN" end
    end
    local authored=0
    eachTool(composition,function(tool)
        local role=meta(tool,"Role")
        if meta(tool,"ObjectId") and role~="Camera" and role~="Base Map" then
            authored=authored+1
        end
    end)
    return authored==0 and "SCENE_EMPTY" or "SCENE_READY"
end
function M.isInitialized(composition)
    local state=M.state(composition)
    return state=="SCENE_READY" or state=="SCENE_EMPTY"
end
local function getCore(composition)
    local state=M.state(composition)
    if state=="SCENE_BROKEN" then
        error("CartoRig scene is broken. Do not initialize over existing nodes; "..
              "recover an editable copy after inspecting missing objects",3)
    end
    if state=="COMP_WITHOUT_CARTORIG" then
        error("Initialize CartoRig in the active Fusion composition first",3)
    end
    local map,camera,output=coreNodes(composition)
    return map,camera,output
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
                parent=meta(tool,"ParentGroup"),
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
    if M.state(composition)=="SCENE_BROKEN" then
        error("SCENE_BROKEN: inspect or recover a copy before modifying objects",3)
    end
    for _,entry in ipairs(owned(composition)) do
        if entry.id==id then return entry end
    end
    error("CartoRig object no longer exists in this composition",3)
end
-- Read-only selection bridge. IDs, never editable node names, are
-- authoritative; external selections are explicit and cannot reuse stale IDs.
function M.selectedInHost(composition)
    composition=composition or current()
    local ok,active=pcall(function()return composition.ActiveTool end)
    if not ok then active=nil end
    if not active then
        local selectedOk,list=pcall(function()return composition:GetToolList(true)end)
        if selectedOk and type(list)=="table" then
            for _,node in pairs(list) do active=node;break end
        end
    end
    if not active then return {state="NONE"} end
    local id=meta(active,"ObjectId")
    if id then
        for _,entry in ipairs(owned(composition)) do
            if entry.id==id and entry.node==active then
                return {state="CARTORIG",id=id,role=entry.role,
                        nodeName=readable(active)}
            end
        end
    end
    return {state="NON_CARTORIG",nodeName=readable(active)}
end
-- Single read-only snapshot for Scene. The caller must bind the result to
-- the composition identity before permitting any later mutation.
function M.snapshot(composition)
    composition=composition or current()
    local state=M.state(composition)
    local objects={}
    if state=="SCENE_READY" or state=="SCENE_EMPTY" then
        objects=owned(composition)
    end
    return {composition=composition,state=state,objects=objects,
            selection=M.selectedInHost(composition)}
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
    if not trySelect(composition,entry.node) then
        error("Fusion could not activate the selected CartoRig node. "..
              "Use Reveal Node or select it directly in the Node Editor.",2)
    end
    return entry
end
local function maxOrder(composition)
    local order=0
    for _,entry in ipairs(owned(composition)) do order=math.max(entry.z,order) end
    return order+1
end
local function persistRegistry(composition,tool,role,remove)
    local map=select(1,coreNodes(composition))
    if not map then error("Base Map registry unavailable",3) end
    local stored=meta(map,"ObjectRegistry")
    if stored==nil then return end -- legacy development composition
    if type(stored)~="table" then error("Invalid Scene registry",3) end
    local registry={}
    for id,kind in pairs(stored) do registry[id]=kind end
    local id=meta(tool,"ObjectId")
    if not id or id=="" then error("Cannot register object without ID",3) end
    if remove then registry[id]=nil else registry[id]=role end
    stamp(map,"ObjectRegistry",registry)
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
    persistRegistry(composition,tool,role,false)
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
       local camera=select(2,coreNodes(current()))
       local name=camera and readable(camera) or "CR_Camera"
       assertHost(handle:SetExpression(name.."."..pair[2]),
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
    if M.state(composition)=="SCENE_BROKEN" then
        error("CartoRig scene is broken. Initialization is not a repair command.")
    end
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
        stamp(stack,"Role","Stack Output")
        stamp(map,"Role","Base Map");stamp(map,"ObjectId",newid(composition))
        stamp(map,"DisplayName","Base Map");stamp(map,"Order",0)
        stamp(camera,"Role","Camera");stamp(camera,"ObjectId",newid(composition))
        stamp(camera,"DisplayName","Camera");stamp(camera,"Order",0)
        stamp(map,"Initialized",true)
        stamp(map,"SceneId",newid(composition))
        stamp(map,"SchemaVersion",1)
        stamp(map,"ObjectRegistry",{})
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
local function currentDatasetFingerprint()
    local path=dataDirectory()
    local file=io.open(path.."/manifest.json","rb")
    if not file then
        error("The Natural Earth dataset manifest is missing. "..
              "Restore the complete offline CartoRig bundle.",3)
    end
    local content=file:read("*a")
    file:close()
    if type(content)~="string" or #content>100000 then
        error("Invalid Natural Earth data manifest",3)
    end
    local sha=content:match('"geometry_sha256"%s*:%s*"([0-9a-fA-F]+)"')
    if not sha or #sha~=64 then
        error("Natural Earth geometry fingerprint missing from manifest",3)
    end
    return sha:lower()
end
function M.datasetFingerprint()
    return currentDatasetFingerprint()
end
local function norm(s)
    -- Lua string.lower() only folds ASCII; uppercase UTF-8 accents otherwise
    -- make ordinary searches such as "SÃO PAULO" fail offline.
    -- Fold the Latin diacritics found in Natural Earth names before lowering.
    s=tostring(s or "")
    local replace={
        ["á"]="a",["à"]="a",["â"]="a",["ã"]="a",["ä"]="a",["å"]="a",
        ["Á"]="a",["À"]="a",["Â"]="a",["Ã"]="a",["Ä"]="a",["Å"]="a",
        ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",
        ["É"]="e",["È"]="e",["Ê"]="e",["Ë"]="e",
        ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",
        ["Í"]="i",["Ì"]="i",["Î"]="i",["Ï"]="i",
        ["ó"]="o",["ò"]="o",["ô"]="o",["õ"]="o",["ö"]="o",
        ["Ó"]="o",["Ò"]="o",["Ô"]="o",["Õ"]="o",["Ö"]="o",
        ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",
        ["Ú"]="u",["Ù"]="u",["Û"]="u",["Ü"]="u",
        ["ç"]="c",["Ç"]="c",["ñ"]="n",["Ñ"]="n"
    }
    for from,to in pairs(replace) do s=s:gsub(from,to) end
    s=s:lower()
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
    local continents={}
    local index=0
    for line in file:lines()do
        index=index+1
        if index>1 then
            local c=cols(line)
            if #c==11 then
                if c[2]=="country" and c[4]~="" then
                    local continent=c[4]
                    local entry=continents[continent]
                    if not entry then
                        entry={id="continent:"..continent,kind="continent",
                               name=continent,parent="Natural Earth derived",
                               geometry="Composite",members={},
                               bounds={180,90,-180,-90}}
                        continents[continent]=entry
                    end
                    entry.members[#entry.members+1]=c[1]
                    local b=entry.bounds
                    b[1]=math.min(b[1],tonumber(c[6])or 180)
                    b[2]=math.min(b[2],tonumber(c[7])or 90)
                    b[3]=math.max(b[3],tonumber(c[8])or -180)
                    b[4]=math.max(b[4],tonumber(c[9])or -90)
                end
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
    if kind=="all" or kind=="continent" then
        for name,entry in pairs(continents) do
            if norm(name):find(text,1,true) and #entry.members>0 then
                table.sort(entry.members)
                found[#found+1]=entry
            end
        end
    end
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
    if loc.kind=="continent" and type(loc.members)=="table"
       and #loc.members>0 and #loc.members<=300 then return "Composite" end
    if loc.kind=="country"or loc.kind=="state" then return "Polygon"end
    error("This location does not have a supported editable geometry",3)
end
function M.addRegion(loc)
    local geometry=verifyLocation(loc)
    if geometry~="Polygon" and geometry~="Composite" then
        error("City is a point. Add Marker or Focus Camera instead",2)
    end
    local featureId=loc.id
    if geometry=="Composite" then
        -- A derived group is not a Natural Earth continent boundary:
        -- the exact member polygons are linked and rendered separately.
        featureId=table.concat(loc.members,"|")
    end
    local composition=current()
    local base,camera,output=getCore(composition)
    return transaction(composition,"CartoRig: Add Region",function()
        local node=newTool(composition,"ofx.com.cartorig.fusionrc1.region",
                           "Region",2,maxOrder(composition))
        local ok,err=pcall(function()
            input(node,"FeatureId",featureId)
            input(node,"DatasetFingerprint",currentDatasetFingerprint())
            bindCamera(node)
            setObjectData(composition,node,"Region",loc.name,featureId,loc.kind)
            if geometry=="Composite" then
                stamp(node,"SourceProvider","Natural Earth derived group")
                stamp(node,"SourceFeatureIds",loc.members)
                stamp(node,"SourceWorldview","Publisher country polygons")
            end
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
local function finiteNumber(value)
    return type(value)=="number" and value==value and
           value~=math.huge and value~=-math.huge
end
local function validPoint(lon,lat)
    return finiteNumber(lon) and finiteNumber(lat) and
           lon>=-180 and lon<=180 and lat>=-85 and lat<=85
end
function M.addCustomPoint(lon,lat,label)
    lon=tonumber(lon);lat=tonumber(lat)
    if not validPoint(lon,lat) then
        error("Custom point needs finite WGS84 longitude/latitude",2)
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
local function cameraBounds(bounds)
    if type(bounds)~="table" then
        error("Location has no geographic bounds",3)
    end
    local west,south,east,north=bounds[1],bounds[2],bounds[3],bounds[4]
    if not (finiteNumber(west) and finiteNumber(south) and
            finiteNumber(east) and finiteNumber(north)) or
       math.abs(west)>180 or math.abs(east)>180 or
       math.abs(south)>90 or math.abs(north)>90 or south>north then
        error("Location has invalid WGS84 bounds",3)
    end
    -- Longitude bounds crossing the date line have west > east.
    -- Preserve the 20-degree 170 -> -170 envelope, not a 340-degree view.
    local unwrappedEast=east<west and east+360 or east
    local center=((west+unwrappedEast)/2+180)%360-180
    local latitude=(south+north)/2
    if math.abs(latitude)>85 then
        error("Location center exceeds supported camera latitude",3)
    end
    return center,latitude,unwrappedEast-west,north-south
end
function M.focus(loc,fit)
    if type(loc)~="table" then
        error("Select a valid geographic location",2)
    end
    -- Validate before opening an Undo transaction or editing any camera key.
    local lon,lat,spanLon,spanLat=cameraBounds(loc.bounds)
    local composition=current()
    local base,camera=getCore(composition)
    local zoom=nil
    if fit then
        local attributes=composition:GetAttrs() or {}
        local width=tonumber(attributes.COMPN_RenderWidth) or 1920
        local height=tonumber(attributes.COMPN_RenderHeight) or 1080
        if not finiteNumber(width) or not finiteNumber(height) or
           width<=0 or height<=0 then
            error("Invalid Fusion render dimensions for Fit",2)
        end
        local usable=.84 -- 8% padding on each side
        local spanX=math.max(.001,spanLon/360)
        local spanY=math.max(.001,spanLat/360)
        zoom=math.min(usable/spanX,usable*height/(width*spanY))
        zoom=math.min(50,math.max(.1,zoom))
    end
    return transaction(composition,"CartoRig: Focus camera",function()
        input(camera,"CenterLongitude",lon)
        input(camera,"CenterLatitude",lat)
        if fit then input(camera,"Zoom",zoom) end
        trySelect(composition,camera)
        return true
    end)
end
function M.addRoute(from,to)
    local composition=current()
    local base,camera=getCore(composition)
    if type(from)~="table" or type(to)~="table" or
       not validPoint(from.lon,from.lat) or
       not validPoint(to.lon,to.lat) then
        error("Route endpoints require finite WGS84 coordinates",2)
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
        if not validPoint(point.lon,point.lat) then
            error("Waypoint requires finite WGS84 longitude/latitude",3)
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
    if not finiteNumber(index) or index%1~=0 or
       index<1 or index>#points+1 then
        error("Waypoint index must be a valid integer",2)
    end
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
    if not finiteNumber(index) or index%1~=0 or
       not finiteNumber(nextIndex) or index<1 or nextIndex<1 or
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
    if not finiteNumber(index) or index%1~=0 or
       index<1 or index>#points then error("Waypoint not selected",2)end
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
    if not validPoint(from.lon,from.lat) or
       not validPoint(to.lon,to.lat) then
        error("Route endpoints are missing or invalid",2)
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
local function cloneData(value,depth)
    depth=depth or 0
    if depth>12 then error("Unsafe CartoRig nested object metadata",3) end
    if type(value)~="table" then return value end
    local result={}
    for k,v in pairs(value) do
        if type(k)=="string" or type(k)=="number" then
            result[k]=cloneData(v,depth+1)
        end
    end
    return result
end
function M.duplicate(id)
    local composition=current()
    local item=objectFor(composition,id)
    if isLocked(composition,item) then error("Object is locked",2) end
    local registry={
        Region="ofx.com.cartorig.fusionrc1.region",
        Route="ofx.com.cartorig.fusionrc1.route",
        Marker="ofx.com.cartorig.fusionrc1.marker",
        Label="ofx.com.cartorig.fusionrc1.label"
    }
    local typeId=registry[item.role]
    if not typeId then
        error("Duplicate is available only for individual Region, Route, "..
              "Marker and Label objects",2)
    end
    if type(item.node.SaveSettings)~="function" then
        error("This Fusion host cannot copy native settings or animation safely",2)
    end
    local captured=item.node:SaveSettings()
    if type(captured)~="table" then
        error("Fusion did not return a copy of the source's complete settings",2)
    end
    -- Capturing through the host's native settings contract is essential:
    -- manual Fusion Spline tangents must not be approximated with sampled keys.
    return transaction(composition,"CartoRig: Duplicate "..item.role,function()
        local duplicate=newTool(composition,typeId,item.role,4,maxOrder(composition))
        local ok,result=pcall(function()
            if type(duplicate.LoadSettings)~="function" or
               duplicate:LoadSettings(captured)==false then
                error("Fusion refused to restore a native animation settings clone")
            end
            rename(duplicate,unique(composition,"CR_"..item.role))
            local copiedName=tostring(item.name or item.role)
            setObjectData(composition,duplicate,item.role,
                          copiedName:sub(1,94).." Copy",
                          item.feature,item.locationKind)
            local parent=meta(item.node,"ParentGroup")
            if parent and parent~="" then
                stamp(duplicate,"ParentGroup",parent)
            end
            local waypoints=meta(item.node,"Waypoints")
            if waypoints then stamp(duplicate,"Waypoints",cloneData(waypoints))end
            -- LoadSettings can restore Source pointers from the copied graph.
            -- Rebuild the complete owned render chain from managed draw order.
            rewire(composition)
        end)
        if not ok then
            pcall(function()duplicate:Delete()end)
            error(result)
        end
        trySelect(composition,duplicate)
        return meta(duplicate,"ObjectId")
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
        persistRegistry(composition,item.node,item.role,true)
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
        persistRegistry(composition,entry.node,"Group",true)
        return true
    end)
end
-- Batch operations preflight all selected IDs before opening ONE host Undo.
-- Group is organizational; hiding and deleting groups never changes geo IDs.
function M.batch(action,ids)
    local allowed={show=true,hide=true,lock=true,unlock=true,delete=true}
    if not allowed[action] then error("Unsupported Scene batch action",2) end
    if type(ids)~="table" or #ids==0 then
        error("Select at least one CartoRig object",2)
    end
    local composition=current()
    local base,camera,output=getCore(composition)
    local seen,selected,drop={}, {},{}
    for _,id in ipairs(ids) do
        if type(id)~="string" or id=="" then
            error("Invalid Scene object selection",2)
        end
        if not seen[id] then
            seen[id]=true
            local entry=objectFor(composition,id)
            if action=="delete" and
               (entry.role=="Camera" or entry.role=="Base Map") then
                error("Base Map and Camera cannot be deleted",2)
            end
            if (action=="show" or action=="hide") and entry.role=="Camera" then
                error("Camera cannot be hidden as a visual object",2)
            end
            if action~="unlock" and isLocked(composition,entry) then
                error("Object or parent Group is locked: "..entry.name,2)
            end
            if action=="unlock" and entry.role~="Group" and
               meta(entry.node,"ParentGroup") then
                local parent=objectFor(composition,meta(entry.node,"ParentGroup"))
                if parent.locked then
                    error("Unlock the parent Group first: "..parent.name,2)
                end
            end
            selected[#selected+1]=entry
            if action=="delete" then drop[id]=true end
        end
    end
    return transaction(composition,"CartoRig: "..action.." selected objects",function()
        if action=="show" or action=="hide" then
            local visible=action=="show"
            for _,entry in ipairs(selected) do
                stamp(entry.node,"Visible",visible)
            end
            -- Recalculate effective group visibility, but preserve each
            -- object's independent local Visible state and all keyframes.
            for _,entry in ipairs(owned(composition))do
                if entry.role~="Camera" and entry.role~="Group" then
                    local parent=meta(entry.node,"ParentGroup")
                    local effective=meta(entry.node,"Visible")~=false
                    if parent and parent~="" then
                        local group=objectFor(composition,parent)
                        effective=effective and group.visible
                    end
                    input(entry.node,"Visible",effective and 1 or 0)
                end
            end
        elseif action=="lock" or action=="unlock" then
            for _,entry in ipairs(selected)do
                stamp(entry.node,"Locked",action=="lock")
            end
        elseif action=="delete" then
            for _,entry in ipairs(owned(composition)) do
                if not drop[entry.id] then
                    local parent=meta(entry.node,"ParentGroup")
                    if parent and drop[parent] then
                        stamp(entry.node,"ParentGroup","")
                        if entry.role~="Group" then
                            input(entry.node,"Visible",entry.visible and 1 or 0)
                        end
                    end
                end
            end
            local tail=base
            for _,entry in ipairs(owned(composition)) do
                if not drop[entry.id] and entry.role~="Base Map"
                   and entry.role~="Camera" and entry.role~="Group" then
                    connect(entry.node,tail)
                    tail=entry.node
                end
            end
            connect(output,tail)
            for _,entry in ipairs(selected) do
                assertHost(entry.node:Delete(),"Delete owned CartoRig node")
                persistRegistry(composition,entry.node,entry.role,true)
            end
        end
        return #selected
    end)
end
-- Organize multiple selected visuals using one host Undo unit. Draw order,
-- coordinates, and animation stay unchanged.
function M.groupMany(ids,groupId)
    if type(ids)~="table" or #ids==0 then
        error("Select objects to group",2)
    end
    local composition=current()
    getCore(composition)
    local group=objectFor(composition,groupId)
    if group.role~="Group" or isLocked(composition,group) then
        error("Destination must be an unlocked Group",2)
    end
    local seen,selected={},{}
    for _,id in ipairs(ids) do
        if not seen[id] then
            seen[id]=true
            local entry=objectFor(composition,id)
            if entry.role=="Base Map" or entry.role=="Camera"
               or entry.role=="Group" or isLocked(composition,entry) then
                error("Only unlocked authored visuals may enter a Group",2)
            end
            selected[#selected+1]=entry
        end
    end
    return transaction(composition,"CartoRig: Group selected objects",function()
        for _,entry in ipairs(selected) do
            stamp(entry.node,"ParentGroup",groupId)
            input(entry.node,"Visible",
                  (entry.visible and group.visible) and 1 or 0)
        end
        return #selected
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
