-- CartoRig Fusion-first integration proof (greenfield, version 0.1).
-- The graphics are test rectangles, NOT geographic data or a production map.
-- Run on a newly inserted Fusion Composition in DaVinci Resolve Studio 20.
-- All operations remain inside the currently active Fusion composition.

local VERSION = "0.1"
local PREFIX = "CRP_"
local SCENE_MARKER = "CartoRigPOC.Version"
local function fail(message)
    error("CartoRig proof: " .. message, 0)
end

local host = rawget(_G, "fusion") or rawget(_G, "fu")
local comp = rawget(_G, "comp")
if not comp and host and host.GetCurrentComp then
    comp = host:GetCurrentComp()
end
if not comp then
    fail("Open a Fusion Composition in the Fusion page first.")
end

local function find(name)
    return comp:FindTool(name)
end

local function get_media_out()
    for _, tool in pairs(comp:GetToolList(false) or {}) do
        local attrs = tool:GetAttrs() or {}
        if attrs.TOOLS_RegID == "MediaOut" or tool.ID == "MediaOut" then
            return tool
        end
    end
    return nil
end

local function name_tool(tool, name, id)
    if not tool then fail("Cannot create " .. name) end
    tool:SetAttrs({TOOLS_Name = name})
    if id then tool:SetData("CartoRigPOC.ObjectId", id) end
    return tool
end

local function connect(tool, input, target)
    local ok = tool:ConnectInput(input, target)
    if ok == false then fail("Could not connect " .. input) end
end

local function set_color(tool, r, g, b)
    tool:SetInput("TopLeftRed", r)
    tool:SetInput("TopLeftGreen", g)
    tool:SetInput("TopLeftBlue", b)
    tool:SetInput("TopLeftAlpha", 1.0)
end

local function make_rect(created, x, y, width, height)
    local mask = comp:AddTool("RectangleMask", x, y)
    if not mask then fail("RectangleMask is unavailable") end
    created[#created + 1] = mask
    mask:SetInput("Center", {0.5, 0.5})
    mask:SetInput("Width", width)
    mask:SetInput("Height", height)
    return mask
end

local function make_layer(created, name, id, color, mask_center, width, height, x, y)
    local background = comp:AddTool("Background", x, y)
    if not background then fail("Background tool is unavailable") end
    created[#created + 1] = background
    name_tool(background, name, id)
    set_color(background, color[1], color[2], color[3])

    local mask = make_rect(created, x, y - 1, width, height)
    name_tool(mask, name .. "_Mask")
    mask:SetInput("Center", {mask_center[1], mask_center[2]})
    return background, mask
end

local function build_scene()
    local marker = comp:GetData(SCENE_MARKER)
    if marker ~= nil then
        if tostring(marker) ~= VERSION then
            fail("An incompatible proof scene already exists; do not migrate it automatically")
        end
        if not (find(PREFIX .. "Brazil") and find(PREFIX .. "Rio") and find(PREFIX .. "Camera")) then
            fail("Proof metadata exists but nodes are missing; no automatic overwrite will occur")
        end
        return false
    end

    local media_out = get_media_out()
    if not media_out then fail("No MediaOut found. Create an empty Fusion Composition in Edit.") end
    for _, tool in pairs(comp:GetToolList(false) or {}) do
        if tool ~= media_out then
            fail("Composition is not empty. Create a NEW Fusion Composition for this proof.")
        end
    end

    local created = {}
    local success, message
    if comp.StartUndo then comp:StartUndo("CartoRig: create integration proof") end
    success, message = xpcall(function()
        local ocean = comp:AddTool("Background", -5, 0)
        if not ocean then fail("Cannot create base Background") end
        created[#created + 1] = ocean
        name_tool(ocean, PREFIX .. "BaseMap", "base")
        set_color(ocean, 0.045, 0.105, 0.18)

        local brazil, brazil_mask = make_layer(created, PREFIX .. "Brazil", "brazil",
            {0.79, 0.16, 0.16}, {0.46, 0.51}, 0.54, 0.60, -4, 2)
        local brazil_merge = comp:AddTool("Merge", -2, 0)
        if not brazil_merge then fail("Merge tool is unavailable") end
        created[#created + 1] = brazil_merge
        name_tool(brazil_merge, PREFIX .. "BrazilComposite")
        connect(brazil_merge, "Background", ocean)
        connect(brazil_merge, "Foreground", brazil)
        connect(brazil_merge, "EffectMask", brazil_mask)

        local rio, rio_mask = make_layer(created, PREFIX .. "Rio", "rio-state",
            {0.90, 0.68, 0.18}, {0.61, 0.34}, 0.10, 0.085, -1, 3)
        local rio_merge = comp:AddTool("Merge", 1, 0)
        if not rio_merge then fail("Second Merge tool is unavailable") end
        created[#created + 1] = rio_merge
        name_tool(rio_merge, PREFIX .. "RioComposite")
        connect(rio_merge, "Background", brazil_merge)
        connect(rio_merge, "Foreground", rio)
        connect(rio_merge, "EffectMask", rio_mask)

        local camera = comp:AddTool("Transform", 3, 0)
        if not camera then fail("Transform tool is unavailable") end
        created[#created + 1] = camera
        name_tool(camera, PREFIX .. "Camera", "camera")
        connect(camera, "Input", rio_merge)
        connect(media_out, "Input", camera)  -- commit the visible output last
        comp:SetData(SCENE_MARKER, VERSION)
    end, function(err) return tostring(err) end)
    if not success then
        for i = #created, 1, -1 do
            pcall(function() created[i]:Delete() end)
        end
    end
    if comp.EndUndo then comp:EndUndo(success) end
    if not success then fail("Creation failed: " .. tostring(message)) end
    return true
end

local function selected_tool(id)
    local names = {
        base = PREFIX .. "BaseMap",
        brazil = PREFIX .. "Brazil",
        rio = PREFIX .. "Rio",
        camera = PREFIX .. "Camera",
    }
    local name = names[id]
    local tool = name and find(name)
    if not tool then fail("The tool for " .. tostring(id) .. " is missing") end
    return tool
end

local function select_in_fusion(id)
    local tool = selected_tool(id)
    local frame = comp.CurrentFrame
    local flow = frame and frame.FlowView
    if not flow then
        return false, "FlowView is unavailable in this host. Selection was not confirmed."
    end
    -- Important: selecting a node is NOT the same as switching active tool.
    -- Clear the previous selection so the Spline panel can filter one tool.
    local ok, message = pcall(function()
        flow:Select()
        flow:Select(tool, true)
        comp:SetActiveTool(tool)
    end)
    if not ok then return false, tostring(message) end
    return true, "Selected " .. tostring(tool.Name or id) .. " in Fusion."
end

local function current_time()
    local t = tonumber(comp.CurrentTime)
    if not t then fail("Cannot read the current Fusion frame") end
    return t
end

local function animate_color(id, rgb)
    if id ~= "brazil" and id ~= "rio" then
        fail("Choose Brazil or Rio de Janeiro before recording color keys")
    end
    local tool = selected_tool(id)
    local t = current_time()
    if comp.StartUndo then comp:StartUndo("CartoRig: keyframe region color") end
    local ok, message = pcall(function()
        if tool:GetData("CartoRigPOC.ColorAnimated") ~= true then
            local channels = {"TopLeftRed", "TopLeftGreen", "TopLeftBlue"}
            for _, channel in ipairs(channels) do
                if tool:AddModifier(channel, "BezierSpline") == false then
                    fail("Could not attach BezierSpline to " .. channel)
                end
            end
            tool:SetData("CartoRigPOC.ColorAnimated", true)
        end
        tool:SetInput("TopLeftRed", rgb[1], t)
        tool:SetInput("TopLeftGreen", rgb[2], t)
        tool:SetInput("TopLeftBlue", rgb[3], t)
    end)
    if comp.EndUndo then comp:EndUndo(ok) end
    if not ok then fail("Keyframe failed: " .. tostring(message)) end
    return t
end

local function animate_camera_scale(value)
    local camera = selected_tool("camera")
    local t = current_time()
    if comp.StartUndo then comp:StartUndo("CartoRig: keyframe shared camera") end
    local ok, message = pcall(function()
        if camera:GetData("CartoRigPOC.ScaleAnimated") ~= true then
            if camera:AddModifier("Size", "BezierSpline") == false then
                fail("Could not animate Transform.Size")
            end
            camera:SetData("CartoRigPOC.ScaleAnimated", true)
        end
        camera:SetInput("Size", value, t)
    end)
    if comp.EndUndo then comp:EndUndo(ok) end
    if not ok then fail("Camera keyframe failed: " .. tostring(message)) end
    return t
end

local function create_window()
    local ui = host and host.UIManager
    local bmd_host = rawget(_G, "bmd")
    if not ui or not bmd_host or not bmd_host.UIDispatcher then
        fail("Fusion UIManager/UIDispatcher is unavailable in this context")
    end
    local dispatcher = bmd_host.UIDispatcher(ui)
    local win = dispatcher:AddWindow({
        ID = "CRP_Window",
        WindowTitle = "CartoRig — Fusion-first integration proof",
        Geometry = {120, 90, 460, 560},
    }, ui:VGroup{
        ID = "CRP_Root", Spacing = 8,
        ui:Label{ID = "CRP_Intro", Text = "TEST SCENE · Rectangles only · No Natural Earth data"},
        ui:LineEdit{ID = "CRP_Search", PlaceholderText = "Filter: Brazil, Rio de Janeiro, Camera..."},
        ui:Tree{ID = "CRP_Objects", ColumnCount = 1, MinimumSize = {390, 160}},
        ui:Label{ID = "CRP_Selection", Text = "Select an object above to activate its Fusion node"},
        ui:HGroup{
            ui:Button{ID = "CRP_Red", Text = "Key Red @ playhead"},
            ui:Button{ID = "CRP_Green", Text = "Key Green @ playhead"},
        },
        ui:HGroup{
            ui:Button{ID = "CRP_Zoom1", Text = "Camera Size 1.0"},
            ui:Button{ID = "CRP_Zoom2", Text = "Camera Size 1.3"},
        },
        ui:Label{ID = "CRP_Help", Text = "For hold: select Brazil > Spline > Step In. Test 0 / 329 / 330."},
        ui:Label{ID = "CRP_Status", Text = "Ready. Viewer output comes from Fusion MediaOut."},
        ui:Button{ID = "CRP_Close", Text = "Close proof window"},
    })
    if not win then fail("UIManager could not create window") end
    local items = win:GetItems()
    local objects = {
        {id = "base", label = "Base Map (test)"},
        {id = "brazil", label = "Brazil — Country (test rectangle)"},
        {id = "rio", label = "Rio de Janeiro — State (test rectangle)"},
        {id = "camera", label = "Shared Camera (screen-space test)"},
    }
    local active = nil

    local function status(msg) items.CRP_Status.Text = msg end
    local function repopulate(query)
        local tree = items.CRP_Objects
        tree:Clear()
        query = (query or ""):lower()
        for _, row in ipairs(objects) do
            if query == "" or row.label:lower():find(query, 1, true) then
                local item = tree:NewItem()
                item.Text[0] = row.label
                tree:AddTopLevelItem(item)
            end
        end
    end
    repopulate("")

    win.On.CRP_Search.TextChanged = function(_)
        active = nil
        repopulate(items.CRP_Search.Text)
    end
    win.On.CRP_Objects.CurrentItemChanged = function(_)
        local item = items.CRP_Objects:CurrentItem()
        if not item then return end
        local label = tostring(item.Text[0] or "")
        for _, row in ipairs(objects) do
            if row.label == label then
                active = row.id
                local ok, msg = select_in_fusion(row.id)
                items.CRP_Selection.Text = row.label
                status((ok and "OK: " or "HOST CHECK: ") .. msg)
                return
            end
        end
    end
    local function key_color(rgb, label)
        if not active then status("Select Brazil or Rio first") return end
        local ok, result = pcall(animate_color, active, rgb)
        status(ok and ("Keyframed " .. label .. " at Fusion frame " .. tostring(result))
            or tostring(result))
    end
    win.On.CRP_Red.Clicked = function(_) key_color({0.79, 0.16, 0.16}, "red") end
    win.On.CRP_Green.Clicked = function(_) key_color({0.12, 0.64, 0.28}, "green") end
    local function key_camera(size)
        local ok, result = pcall(animate_camera_scale, size)
        status(ok and ("Keyframed shared Transform.Size at " .. tostring(result)) or tostring(result))
    end
    win.On.CRP_Zoom1.Clicked = function(_) key_camera(1.0) end
    win.On.CRP_Zoom2.Clicked = function(_) key_camera(1.3) end
    win.On.CRP_Close.Clicked = function(_) dispatcher:ExitLoop() end
    win.On.CRP_Window.Close = function(_) dispatcher:ExitLoop() end
    win:Show()
    dispatcher:RunLoop()
    win:Hide()
end

build_scene()
create_window()
