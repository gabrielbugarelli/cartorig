-- CartoRig Hybrid Test — run from DaVinci Resolve > Workspace > Scripts.
-- No Python, terminal or Natural Earth download needed.
-- Creates a NEW, disposable QA project. Never edits existing timeline items.
-- This is an architecture test, NOT the CartoRig final editor.
local function assert_ok(v, label)
    if v == nil or v == false then error(label .. " failed or unsupported in this Resolve installation", 2) end
    return v
end
local function set_input(tool, id, value, frame)
    local result
    if frame == nil then
        result = tool:SetInput(id, value)
    else
        result = tool:SetInput(id, value, frame)
    end
    assert_ok(result ~= false, "Fusion SetInput " .. id)
end
local function connect(tool, id, upstream)
    assert_ok(tool:ConnectInput(id, upstream) ~= false, "Fusion connection " .. id)
end
local function rename(tool, name)
    assert_ok(tool:SetAttrs({ TOOLS_Name = name }) ~= false, "Fusion tool rename")
    assert_ok(tool:GetAttrs().TOOLS_Name == name, "Fusion tool name readback")
end
local createdProject, createdTimeline, projectManager
local function main()
    local r = (bmd and bmd.scriptapp and bmd.scriptapp("Resolve")) or resolve
    assert_ok(r, "Resolve scripting connection")
    local version = assert_ok(r:GetVersion(), "Resolve version")
    assert_ok(tonumber(version[1]) == 20, "DaVinci Resolve Studio 20 required")
    projectManager = assert_ok(r:GetProjectManager(), "Project manager")

    -- Unique name. A duplicate project is rejected, not modified or overwritten.
    local projectName = "CartoRig_Fusion_QA_" .. os.date("%Y%m%d_%H%M%S")
    createdProject = assert_ok(projectManager:CreateProject(projectName),
                               "Create new isolated " .. projectName)
    local pool = assert_ok(createdProject:GetMediaPool(), "Get media pool")
    createdTimeline = assert_ok(pool:CreateEmptyTimeline("CartoRig Fusion Container Test"),
                                "Create test timeline")
    assert_ok(createdProject:SetCurrentTimeline(createdTimeline), "Select QA timeline")
    -- Resolve 20 may refuse to change an existing timeline's resolution
    -- through Timeline.SetSetting(). Resolution is irrelevant to the
    -- core Fusion+OFX integration proof. Respect the user's project default.
    local successW, width = pcall(function()
        return createdTimeline:GetSetting("timelineResolutionWidth")
    end)
    local successH, height = pcall(function()
        return createdTimeline:GetSetting("timelineResolutionHeight")
    end)
    if successW and successH and width and height then
        print("[CartoRig Hybrid Test] Using default timeline: " ..
              tostring(width) .. "x" .. tostring(height))
    else
        print("[CartoRig Hybrid Test] Using Resolve default timeline resolution.")
    end

    -- The OFX Generator cannot accept AddFusionComp in Resolve Studio 20.
    -- Instead, place a Fusion Composition on Edit, and add CartoRig Overlay
    -- inside it as a Fusion OpenFX tool (experimental, host verification required).
    local clip = assert_ok(createdTimeline:InsertFusionCompositionIntoTimeline(),
                           "Insert Fusion Composition on Edit")
    local count = tonumber(clip:GetFusionCompCount() or 0)
    local comp
    if count > 0 then
        comp = assert_ok(clip:GetFusionCompByIndex(1), "Read Fusion Composition")
    else
        comp = assert_ok(clip:AddFusionComp(), "Initialize Fusion Composition")
        if type(comp) == "boolean" then
            comp = assert_ok(clip:GetFusionCompByIndex(1), "Read initialized Fusion Composition")
        end
    end
    local mediaOut = comp:FindTool("MediaOut1") or comp:FindToolByID("MediaOut")
    if not mediaOut then
        mediaOut = assert_ok(comp:AddTool("MediaOut", 4, 1), "Create MediaOut")
    end
    local bg = assert_ok(comp:AddTool("Background", -5, 1), "Create map source")
    set_input(bg, "TopLeftAlpha", 1)
    local map = assert_ok(comp:AddTool("ofx.com.cartorig.native.overlay", -3, 1),
                          "Add CartoRig Overlay as Fusion OFX tool")
    rename(map, "CR_Spike_Map_Overlay")
    local linked = false
    for _, socket in ipairs({"Source", "Input", "Image"}) do
        local ok, reply = pcall(function() return map:ConnectInput(socket, bg) end)
        if ok and reply ~= false then
            linked = true
            break
        end
    end
    assert_ok(linked, "Connect Fusion background to CartoRig Overlay")
    local mediaIn = map

    local start = 0
    local attrs = comp:GetAttrs()
    if type(attrs) == "table" and tonumber(attrs.COMPN_GlobalStart) then
        start = tonumber(attrs.COMPN_GlobalStart)
    end
    local usingUndo = (type(comp.StartUndo) == "function")
    if usingUndo then comp:StartUndo("CartoRig Hybrid Test") end
    local success, reason = pcall(function()
        local brazil = assert_ok(comp:AddTool("TextPlus", -4, 1), "Add BRA Text+")
        local venezuela = assert_ok(comp:AddTool("TextPlus", -4, 3), "Add VEN Text+")
        local a = assert_ok(comp:AddTool("Merge", -1, 1), "Add BRA Merge")
        local b = assert_ok(comp:AddTool("Merge", 1, 3), "Add VEN Merge")
        rename(brazil, "CR_Spike_BRA")
        rename(venezuela, "CR_Spike_VEN")
        rename(a, "CR_Spike_BRA_Merge")
        rename(b, "CR_Spike_VEN_Merge")
        set_input(brazil, "StyledText", "BRA — architecture test")
        set_input(venezuela, "StyledText", "VEN — architecture test")
        set_input(a, "Center", { [1] = 0.32, [2] = 0.50 })
        set_input(b, "Center", { [1] = 0.68, [2] = 0.50 })
        connect(a, "Background", mediaIn)
        connect(a, "Foreground", brazil)
        connect(b, "Background", a)
        connect(b, "Foreground", venezuela)
        connect(mediaOut, "Input", b)
        for _, data in ipairs({ {a, 0, 12}, {b, 24, 36} }) do
            local merge, first, last = data[1], data[2], data[3]
            assert_ok(merge:AddModifier("Blend", "BezierSpline") ~= false,
                      "Create independent Blend keyframes")
            set_input(merge, "Blend", 0, start)
            set_input(merge, "Blend", 0, start + first)
            set_input(merge, "Blend", 1, start + last)
        end
    end)
    if usingUndo then comp:EndUndo(success) end
    if not success then error(reason, 0) end

    if type(createdTimeline.AddMarker) == "function" then
        createdTimeline:AddMarker(0, "Green", "CartoRig Hybrid Test",
            "BRA appears from frame 0–12; VEN from frame 24–36. Verify map/labels visually.", 1)
    end
    assert_ok(projectManager:SaveProject(), "Save QA project")
    r:OpenPage("edit")
    print("CartoRig hybrid test project created: " .. projectName)
    print("Review the Edit viewer at frame 18 and 40. This does NOT certify actual pixel output.")
end

local ok, message = pcall(main)
local output = ok and
    "CREATED: Fusion Composition with CartoRig Overlay and two Text+ objects; inspect the Viewer." or
    ("BLOCKED: " .. tostring(message))
print("[CartoRig Hybrid Test] " .. output)
if not ok and createdTimeline and type(createdTimeline.AddMarker) == "function" then
    pcall(function()
        createdTimeline:AddMarker(0, "Red", "CartoRig Hybrid Test BLOCKED",
                                  tostring(message), 1)
        if projectManager then projectManager:SaveProject() end
    end)
end
local path = os.getenv("TEMP") or os.getenv("TMP")
if path then
    pcall(function()
        local f = io.open(path .. "\\CartoRig-Hybrid-Test-Result.txt", "w")
        if f then
            f:write(output, "\n")
            f:close()
        end
    end)
end
