-- CartoRig greenfield: scene graph adapter for Fusion 20.
-- Render, keyframe and geometry tools live in Fusion; no offscreen image sequence.
local G={}
local PREFIX='CR2_'
local VERSION='0.2'
local MARKER='CartoRig.Scene.Version'
local function errorf(message) error('CartoRig: '..message,2) end
local function find(comp,name) return comp:FindTool(name) end
local function tag(node,name,kind,id)
    assert(node,'Fusion could not create '..name)
    node:SetAttrs({TOOLS_Name=name})
    node:SetData('CartoRig.Kind',kind or '')
    node:SetData('CartoRig.FeatureId',id or '')
    return node
end
local function add(comp,registry,name,kind,id,x,y)
    local node=comp:AddTool(registry,x or -32768,y or -32768)
    return tag(node,name,kind,id)
end
local function connect(node,input,source)
    if not source then errorf('Missing upstream node for '..tostring(input)) end
    local ok=node:ConnectInput(input,source)
    if ok==false then errorf('Could not connect '..tostring(input)) end
end
local function setrgb(node,rgb)
    local channels={'TopLeftRed','TopLeftGreen','TopLeftBlue','TopLeftAlpha'}
    for i,k in ipairs(channels) do node:SetInput(k,rgb[i] or (i==4 and 1 or 0)) end
end
local function make_polyline(comp,id,ring,closed,node_x,node_y)
    if #ring<3 and closed then errorf('Polygon requires at least three vertices') end
    if #ring<2 and not closed then errorf('Route requires two points') end
    if #ring>5000 then errorf('Geometry exceeds safe Fusion mask budget') end
    local ctor=rawget(_G,'Polyline')
    if not ctor then
        errorf('Fusion Polyline constructor unavailable; cannot create geographic mask')
    end
    local points={}
    for _,coord in ipairs(ring) do
        local x,y = coord[1],coord[2]
        -- World geographic coordinates are transformed once for the full map.
        x,y=(x+180)/360,(y+90)/180
        points[#points+1]={Linear=true,X=x-0.5,Y=y-0.5}
    end
    local name=PREFIX..'Mask_'..id
    local node=add(comp,'PolylineMask',name,'Mask',id,node_x,node_y)
    node:SetInput('Center',{0.5,0.5})
    local ok,poly=pcall(function() return ctor{Closed=closed,Points=points} end)
    if not ok then errorf('Could not make Polyline geometry: '..tostring(poly)) end
    local set_ok,why=pcall(function() return node:SetInput('Polyline',poly) end)
    if not set_ok or why==false then
        errorf('Fusion rejected geographic Polyline input: '..tostring(why))
    end
    if not closed then
        node:SetInput('Solid',0)
        node:SetInput('BorderWidth',0.005)
    end
    return node
end
local function find_media_out(comp)
    for _,node in pairs(comp:GetToolList(false) or {}) do
        local attrs=node:GetAttrs() or {}
        if attrs.TOOLS_RegID=='MediaOut' or node.ID=='MediaOut' then return node end
    end
    return nil
end
function G.ensure(comp,features)
    local existing=comp:GetData(MARKER)
    if existing then
        if existing~=VERSION then errorf('Scene schema '..tostring(existing)..' is incompatible with '..VERSION) end
        local camera=find(comp,PREFIX..'Camera')
        local tail=find(comp,comp:GetData('CartoRig.Scene.LastLayer') or '')
        if not camera or not tail then errorf('Scene graph is damaged. CartoRig will not overwrite it.') end
        return false
    end
    local out=find_media_out(comp)
    if not out then errorf('Open an empty Fusion Composition with MediaOut') end
    for _,tool in pairs(comp:GetToolList(false) or {}) do
        if tool~=out then errorf('Use a fresh Fusion Composition; existing nodes will not be replaced') end
    end
    if comp.Lock then comp:Lock() end
    if comp.StartUndo then comp:StartUndo('CartoRig: create geographic scene') end
    local created={}
    local function new(registry,name,kind,id,x,y)
        local t=add(comp,registry,name,kind,id,x,y)
        created[#created+1]=t
        return t
    end
    local ok,err=xpcall(function()
        local ocean=new('Background',PREFIX..'Ocean','BaseMap','ocean',-9,0)
        setrgb(ocean,{0.043,0.118,0.192,1})
        local land=new('Background',PREFIX..'Land','BaseMap','land',-8,2)
        setrgb(land,{0.18,0.25,0.30,1})
        local tail=ocean
        local world=nil
        for _,f in ipairs(features) do if f.id=='ne110:world-land' then world=f break end end
        if not world then errorf('Natural Earth land geometry unavailable') end
        local count=0
        local holes={}
        for _,polygon in ipairs(world.polygons) do
            local mask=make_polyline(comp,'Land_'..tostring(count+1),polygon[1],true,-7,count%18)
            created[#created+1]=mask
            local merge=new('Merge',PREFIX..'LandComposite_'..tostring(count+1),'BaseMerge','land',-5,count%18)
            connect(merge,'Background',tail)
            connect(merge,'Foreground',land)
            connect(merge,'EffectMask',mask)
            tail=merge
            count=count+1
            for i=2,#polygon do holes[#holes+1]=polygon[i] end
        end
        for i,ring in ipairs(holes) do
            local mask=make_polyline(comp,'WaterHole_'..i,ring,true,-7,i%18)
            created[#created+1]=mask
            local merge=new('Merge',PREFIX..'WaterHoleComposite_'..i,'BaseMerge','ocean',-4,i%18)
            connect(merge,'Background',tail)
            connect(merge,'Foreground',ocean)
            connect(merge,'EffectMask',mask)
            tail=merge
        end
        local camera=new('Transform',PREFIX..'Camera','Camera','camera',6,0)
        connect(camera,'Input',tail)
        connect(out,'Input',camera)
        comp:SetData('CartoRig.Scene.LastLayer',tail.Name)
        comp:SetData(MARKER,VERSION)
    end,debug.traceback)
    if not ok then
        for i=#created,1,-1 do pcall(function() created[i]:Delete() end) end
    end
    if comp.EndUndo then comp:EndUndo(ok) end
    if comp.Unlock then comp:Unlock() end
    if not ok then errorf('Scene creation failed: '..tostring(err)) end
    return true
end
local function next_id(comp)
    local n=tonumber(comp:GetData('CartoRig.Scene.Serial')) or 0
    n=n+1; comp:SetData('CartoRig.Scene.Serial',n)
    return tostring(n)
end
function G.get_objects(comp)
    local rows={}
    for _,t in pairs(comp:GetToolList(false) or {}) do
        local kind=t:GetData('CartoRig.Kind')
        if kind=='Region' or kind=='Marker' or kind=='Route' then
            rows[#rows+1]={id=t:GetData('CartoRig.ObjectId'),kind=kind,featureId=t:GetData('CartoRig.FeatureId'),label=t:GetData('CartoRig.Label') or t.Name,node=t}
        end
    end
    table.sort(rows,function(a,b) return tonumber(a.id or 0)<tonumber(b.id or 0) end)
    return rows
end
function G.select(comp,node)
    if not node then return false,'No object' end
    local view=comp.CurrentFrame and comp.CurrentFrame.FlowView
    if not view then return false,'Fusion FlowView unavailable' end
    local ok,msg=pcall(function() view:Select(); view:Select(node,true); comp:SetActiveTool(node) end)
    return ok,ok and 'Selected in Fusion Inspector' or tostring(msg)
end
local function add_to_scene(comp,fg,mask,label,kind,featureId)
    local tail=find(comp,comp:GetData('CartoRig.Scene.LastLayer') or '')
    local camera=find(comp,PREFIX..'Camera')
    if not tail or not camera then errorf('Create a CartoRig scene first') end
    local serial=next_id(comp)
    -- NOTE: one object may use several masks/merges but has a single editable Background.
    tag(fg,PREFIX..'Object_'..serial,kind,featureId)
    fg:SetData('CartoRig.ObjectId',serial)
    fg:SetData('CartoRig.Label',label)
    for i,m in ipairs(mask) do
        local merge=add(comp,'Merge',PREFIX..'ObjectComposite_'..serial..'_'..i,'ObjectMerge',serial,3+i,3)
        connect(merge,'Background',tail)
        connect(merge,'Foreground',fg)
        connect(merge,'EffectMask',m)
        tail=merge
    end
    connect(camera,'Input',tail)
    comp:SetData('CartoRig.Scene.LastLayer',tail.Name)
    return serial
end
local function transaction(comp,title,callback)
    if comp.StartUndo then comp:StartUndo(title) end
    local ok,result=pcall(callback)
    if comp.EndUndo then comp:EndUndo(ok) end
    if not ok then errorf(result) end
    return result
end
function G.add_region(comp,feature)
    if not feature or type(feature.polygons)~='table' then errorf('Selected locality has no administrative polygon') end
    if #feature.polygons==0 then errorf('No polygon available') end
    for _,p in ipairs(feature.polygons) do
        if #p>1 then errorf('Region contains holes; current renderer requires validated hole masks') end
    end
    if #feature.polygons>250 then errorf('Region contains more than 250 pieces; needs optimized rendering') end
    return transaction(comp,'CartoRig: add '..feature.name,function()
        local serial=(tonumber(comp:GetData('CartoRig.Scene.Serial')) or 0)+1
        local fg=add(comp,'Background',PREFIX..'Pending_'..serial,'Pending','',0,5)
        setrgb(fg,{0.78,0.16,0.17,1})
        local masks={}
        for i,p in ipairs(feature.polygons) do
            masks[#masks+1]=make_polyline(comp,'Region_'..serial..'_'..i,p[1],true,1+i,5)
        end
        local id=add_to_scene(comp,fg,masks,feature.name..' — '..feature.kind, 'Region',feature.id)
        return id
    end)
end
function G.add_marker(comp,feature)
    if not feature or not feature.lon or not feature.lat then errorf('Selected locality has no point') end
    return transaction(comp,'CartoRig: add marker',function()
        local serial=(tonumber(comp:GetData('CartoRig.Scene.Serial')) or 0)+1
        local fg=add(comp,'Background',PREFIX..'MarkerPending_'..serial,'Pending','',1,6)
        setrgb(fg,{1,0.72,0.20,1})
        local mask=add(comp,'EllipseMask',PREFIX..'MarkerMask_'..serial,'Mask','',2,6)
        local x,y=(feature.lon+180)/360,(feature.lat+90)/180
        mask:SetInput('Center',{x,y})
        mask:SetInput('Width',0.008)
        mask:SetInput('Height',0.008)
        return add_to_scene(comp,fg,{mask},feature.name..' — Marker','Marker',feature.id)
    end)
end
function G.add_route(comp,from,to)
    if not from or not to or not from.lon or not to.lon then errorf('Choose point endpoints first') end
    if math.abs(to.lon-from.lon)>180 then errorf('Route crosses the antimeridian: this first 2D renderer cannot draw it correctly') end
    if math.abs(to.lon-from.lon)+math.abs(to.lat-from.lat)<0.00001 then errorf('Route origin and destination coincide') end
    return transaction(comp,'CartoRig: add geographic route',function()
        local serial=(tonumber(comp:GetData('CartoRig.Scene.Serial')) or 0)+1
        local fg=add(comp,'Background',PREFIX..'RoutePending_'..serial,'Pending','',1,7)
        setrgb(fg,{0.97,0.69,0.20,1})
        local mask=make_polyline(comp,'Route_'..serial,{{from.lon,from.lat},{to.lon,to.lat}},false,2,7)
        -- Build the arrowhead from geographic endpoints (not a fixed screen coordinate).
        local dx=(to.lon-from.lon)/360
        local dy=(to.lat-from.lat)/180
        local len=math.sqrt(dx*dx+dy*dy)
        if len<1e-8 then errorf('Route origin and destination coincide') end
        local ux,uy=dx/len,dy/len
        local lx,ly=-uy,ux
        local head=0.016
        local spread=0.007
        local tx,ty=(to.lon+180)/360,(to.lat+90)/180
        local bx,by=tx-ux*head,ty-uy*head
        local arrow={
            {to.lon,to.lat},
            {(bx+lx*spread)*360-180,(by+ly*spread)*180-90},
            {(bx-lx*spread)*360-180,(by-ly*spread)*180-90},
        }
        local tip=make_polyline(comp,'RouteHead_'..serial,arrow,true,2,8)
        local id=add_to_scene(comp,fg,{mask,tip},from.name..' → '..to.name,'Route',from.id..'→'..to.id)
        fg:SetData('CartoRig.RouteMask',mask.Name)
        fg:SetData('CartoRig.RouteHeadMerge',PREFIX..'ObjectComposite_'..id..'_2')
        return id
    end)
end
function G.set_fill(comp,obj,hex,key)
    if not obj or not obj.node then errorf('Select an object') end
    hex=tostring(hex or ''):gsub('#','')
    if not hex:match('^%x%x%x%x%x%x$') then errorf('Color must be #RRGGBB') end
    local rgb={tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255}
    return transaction(comp,key and 'CartoRig: keyframe color' or 'CartoRig: set fill',function()
        local node=obj.node
        local channels={'TopLeftRed','TopLeftGreen','TopLeftBlue'}
        local t=tonumber(comp.CurrentTime)
        if key and not t then errorf('No Fusion playhead time') end
        for i,k in ipairs(channels) do
            if key then
                if node:GetData('CartoRig.Animated.'..k)~=true then
                    local ok=node:AddModifier(k,'BezierSpline')
                    if ok==false then errorf('Failed to add spline '..k) end
                    node:SetData('CartoRig.Animated.'..k,true)
                end
                node:SetInput(k,rgb[i],t)
            else
                if node:GetData('CartoRig.Animated.'..k)==true then
                    errorf('Color is already animated. Use Key Color at the playhead.')
                end
                node:SetInput(k,rgb[i])
            end
        end
    end)
end
function G.camera_focus(comp,feature,zoom,animated)
    if not feature or feature.lon==nil then errorf('Choose a point or region first') end
    local camera=find(comp,PREFIX..'Camera')
    if not camera then errorf('Camera missing') end
    local x,y=(feature.lon+180)/360,(feature.lat+90)/180
    local z=tonumber(zoom) or 1.0
    if z<1 or z>20 then errorf('Camera zoom must be in range 1..20') end
    local cx,cy=0.5-(x-0.5)*z,0.5-(y-0.5)*z
    return transaction(comp,'CartoRig: focus camera',function()
        if animated then
            local t=tonumber(comp.CurrentTime)
            if not t then errorf('No Fusion playhead time') end
            if camera:GetData('CartoRig.CameraAnimated')~=true then
                if camera:AddModifier('Size','BezierSpline')==false then errorf('Size spline unavailable') end
                if camera:AddModifier('Center','XYPath')==false then errorf('Center spline unavailable') end
                camera:SetData('CartoRig.CameraAnimated',true)
            end
            camera:SetInput('Size',z,t)
            camera:SetInput('Center',{cx,cy},t)
        else
            if camera:GetData('CartoRig.CameraAnimated')==true then errorf('Camera is animated. Record a pose at the playhead.') end
            camera:SetInput('Size',z)
            camera:SetInput('Center',{cx,cy})
        end
    end)
end
function G.set_opacity(comp,obj,percent,key)
    if not obj or not obj.node then errorf('Select an object') end
    percent=tonumber(percent)
    if not percent or percent<0 or percent>100 then errorf('Opacity must be 0..100') end
    return transaction(comp,key and 'CartoRig: keyframe opacity' or 'CartoRig: opacity',function()
        local node=obj.node
        if key then
            if not tonumber(comp.CurrentTime) then errorf('Fusion playhead not available') end
            if node:GetData('CartoRig.Animated.Alpha')~=true then
                if node:AddModifier('TopLeftAlpha','BezierSpline')==false then errorf('Opacity spline unavailable') end
                node:SetData('CartoRig.Animated.Alpha',true)
            end
            node:SetInput('TopLeftAlpha',percent/100,tonumber(comp.CurrentTime))
        else
            if node:GetData('CartoRig.Animated.Alpha')==true then errorf('Opacity is animated; use Key Opacity') end
            node:SetInput('TopLeftAlpha',percent/100)
        end
    end)
end
function G.route_reveal(comp,obj,progress)
    if not obj or obj.kind~='Route' then errorf('Select a route') end
    progress=tonumber(progress)
    if progress~=0 and progress~=100 then errorf('Use 0 or 100 percent') end
    return transaction(comp,'CartoRig: route reveal keyframe',function()
        local mask=find(comp,obj.node:GetData('CartoRig.RouteMask') or '')
        local headMerge=find(comp,obj.node:GetData('CartoRig.RouteHeadMerge') or '')
        if not mask or not headMerge then errorf('Route animation tools missing') end
        local t=tonumber(comp.CurrentTime)
        if not t then errorf('Fusion playhead unavailable') end
        if mask:GetData('CartoRig.RevealAnimated')~=true then
            if mask:AddModifier('WriteLength','BezierSpline')==false then errorf('Polyline WriteLength unavailable') end
            mask:SetData('CartoRig.RevealAnimated',true)
        end
        if headMerge:GetData('CartoRig.RevealAnimated')~=true then
            if headMerge:AddModifier('Blend','BezierSpline')==false then errorf('Arrowhead Blend unavailable') end
            headMerge:SetData('CartoRig.RevealAnimated',true)
        end
        mask:SetInput('WriteLength',progress/100,t)
        headMerge:SetInput('Blend',progress==100 and 1 or 0,t)
    end)
end
function G.get_base(comp)
    return {ocean=find(comp,PREFIX..'Ocean'),land=find(comp,PREFIX..'Land')}
end
function G.set_base_color(comp,layer,hex)
    local b=G.get_base(comp)[layer]
    if not b then errorf('Base map layer unavailable') end
    return G.set_fill(comp,{node=b},hex,false)
end
return G
