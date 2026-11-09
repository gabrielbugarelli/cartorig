-- CartoRig Fusion rewrite bootstrap. A Fusion Composition must be active.
-- This UI manages only scene structure; style/animation remain owned by Fusion nodes.
local function log(message)
  pcall(function()
    local temp=os.getenv('TEMP') or os.getenv('TMP') or '.'
    local f=io.open(temp..'/CartoRig_Rewrite_v2.log','a')
    if f then f:write(os.date('%Y-%m-%d %H:%M:%S')..' '..tostring(message)..'\n');f:close() end
  end)
end
local function run()
  local source=debug.getinfo(1,'S').source
  local dir=(source:sub(1,1)=='@' and source:sub(2) or source):match('^(.*)[/\\][^/\\]*$') or '.'
  local function module(name)return dofile(dir..'/CartoRig/'..name..'.lua')end
  local Scene=module('scene')
  local Json=module('json')
  local Catalog=module('catalog')
  local Repository=module('repository')
  local Host=module('fusion_host')
  local Objects=module('fusion_objects')
  local Geo=module('geo')
  local Coordinates=module('coordinates')
  local Motion=module('motion')
  local Writer=module('motion_apply')
  local Authoring=module('authoring')
  local GraphOps=module('graph_ops')
  local SceneOps=module('scene_ops')
  local Manifest=module('manifest')
  local fus=rawget(_G,'fusion') or rawget(_G,'fu')
  local comp=rawget(_G,'comp')
  if not comp and fus and fus.GetCurrentComp then comp=fus:GetCurrentComp() end
  if not comp then error('Open a Fusion Composition before launching CartoRig Scene') end
  local bridge=rawget(_G,'bmd')
  local ui=fus and fus.UIManager
  if not ui or not bridge or type(bridge.UIDispatcher)~='function' then error('Resolve Fusion UIManager is unavailable') end
  local bundleId=Manifest.load(dir..'/CartoRig/data/manifest.json',Json).id
  local engine=Authoring.new(comp,{Scene=Scene,Repository=Repository,Json=Json,Host=Host,Objects=Objects,Geo=Geo,Motion=Motion,Writer=Writer,GraphOps=GraphOps,SceneOps=SceneOps},bridge,bundleId)
  local host=engine.host
  local entries={};local results={};local displayed={}
  local state=engine:current()
  local dataDir=dir..'/CartoRig/data'
  engine.host.dataRoot=dataDir
  local bundle_path=dataDir..'/ne_110m_admin_0_countries.geojson'
  local ok_data,load_error=pcall(function()
    local index=io.open(dataDir..'/catalog_index.json','rb')
    if index then
      index:close()
      entries=Catalog.load_index(dataDir,Json)
    else
      local doc=Catalog.load_bundle(bundle_path,Json)
      entries=Catalog.from_geojson(doc,'Country',{dataset='Natural Earth Admin 0',version='110m-preview',scale='110m'})
    end
  end)
  if ok_data then
    local existing={}
    for _,e in ipairs(entries) do existing[e.id]=true end
    for _,continent in ipairs(Catalog.continent_groups(entries)) do
      if not existing[continent.id] then entries[#entries+1]=continent;existing[continent.id]=true end
    end
  else log('BUNDLE ERROR: '..tostring(load_error)) end
  local dispatcher=bridge.UIDispatcher(ui)
  local win=dispatcher:AddWindow({ID='CartoRigSceneWindow',WindowTitle='CartoRig — Scene (Rewrite Preview)',Geometry={120,120,470,680}},
    ui:VGroup{Spacing=7,
      ui:Label{ID='CR_Header',Text='CARTORIG — SCENE'},
      ui:Label{ID='CR_Context',Text='Fusion Composition'},
      ui:Button{ID='CR_Initialize',Text='Initialize Map Scene'},
      ui:HGroup{ui:LineEdit{ID='CR_Search',PlaceholderText='Search location'},ui:Button{ID='CR_SearchBtn',Text='Find'}},
      ui:HGroup{ui:Label{Text='Filter'},ui:ComboBox{ID='CR_Filter'}},
      ui:Label{Text='OFFLINE LOCATIONS (installed Natural Earth bundle)'},
      ui:Tree{ID='CR_Results',ColumnCount=1,SortingEnabled=false,MinimumSize={320,160}},
      ui:HGroup{ui:Button{ID='CR_AddRegion',Text='Add as Region'},ui:Button{ID='CR_AddMarker',Text='Add Marker'},ui:Button{ID='CR_AddLabel',Text='Add Label'}},
      ui:HGroup{ui:Button{ID='CR_FocusCamera',Text='Focus Camera'},ui:Button{ID='CR_FitLocation',Text='Fit Location'}},
      ui:HGroup{ui:Button{ID='CR_RouteFrom',Text='Route From'},ui:Button{ID='CR_RouteTo',Text='Route To'},ui:Button{ID='CR_CreateRoute',Text='Create Route'}},
      ui:HGroup{ui:Label{Text='Path Type'},ui:ComboBox{ID='CR_PathType'},
        ui:LineEdit{ID='CR_Curvature',PlaceholderText='Curvature (-100..100)',Text='0'}},
      ui:HGroup{ui:Button{ID='CR_AddWaypoint',Text='Add Waypoint (coordinates)'},
        ui:Button{ID='CR_ClearWaypoints',Text='Clear Waypoints'}},
      ui:Button{ID='CR_UpdateRoute',Text='Update Selected Route Geometry'},
      ui:Button{ID='CR_ReverseRoute',Text='Reverse Selected Route'},
      ui:HGroup{ui:LineEdit{ID='CR_CustomLon',PlaceholderText='Longitude (decimal degrees)'},
        ui:LineEdit{ID='CR_CustomLat',PlaceholderText='Latitude (decimal degrees)'}},
      ui:HGroup{ui:Button{ID='CR_CustomFrom',Text='Use as Route From'},
        ui:Button{ID='CR_CustomTo',Text='Use as Route To'}},
      ui:HGroup{ui:Button{ID='CR_CustomMarker',Text='Add Custom Marker'},
        ui:Button{ID='CR_CustomLabel',Text='Add Custom Label'},
        ui:Button{ID='CR_CustomFocus',Text='Focus Custom Point'}},
      ui:Label{ID='CR_RouteState',Text='Route: choose explicit point endpoints'},
      ui:Label{Text='SCENE OBJECTS'},
      ui:Tree{ID='CR_Objects',ColumnCount=1,SortingEnabled=false,MinimumSize={320,200}},
      ui:HGroup{ui:Button{ID='CR_Reveal',Text='Reveal in Fusion'},ui:Button{ID='CR_Refresh',Text='Refresh'}},
      ui:HGroup{ui:LineEdit{ID='CR_RenameField',PlaceholderText='New object name'},ui:Button{ID='CR_Rename',Text='Rename'}},
      ui:HGroup{ui:Button{ID='CR_MoveUp',Text='Move Up'},ui:Button{ID='CR_MoveDown',Text='Move Down'},ui:Button{ID='CR_Delete',Text='Delete Selected'}},
      ui:HGroup{ui:Button{ID='CR_Visibility',Text='Hide / Show'},ui:Button{ID='CR_Lock',Text='Lock / Unlock'}},
      ui:HGroup{ui:LineEdit{ID='CR_GroupName',PlaceholderText='Group name'},ui:Button{ID='CR_GroupSelected',Text='Group Selected'},ui:Button{ID='CR_Ungroup',Text='Ungroup'}},
      ui:Label{ID='CR_Status',Text='Ready'},
      ui:Button{ID='CR_Close',Text='Close Scene'},
    })
  local w=win:GetItems()
  local chosen=nil;local selected_id=nil;local pendingDelete=nil;local pendingReverse=nil
  local routeFrom,routeTo=nil,nil
  local routeWaypoints=nil
  local routeFromArea,routeToArea=nil,nil
  local filters={'All','Continent','Country','State','City'}
  for _,kind in ipairs(filters) do w.CR_Filter:AddItem(kind) end
  w.CR_PathType:AddItem('Straight');w.CR_PathType:AddItem('Curved')
  local function status(msg)w.CR_Status.Text=tostring(msg);log(msg) end
  local function refresh_context()
    local active=fus and fus.GetCurrentComp and fus:GetCurrentComp() or comp
    if active~=comp then status('Active composition changed. Restart Scene for the new composition.');return false end
    return true
  end
  local function guarded(f)
    if not refresh_context() then return end
    local ok,result=xpcall(f,debug.traceback)
    if ok then status(result or 'Ready') else status(('Error: '..tostring(result)):sub(1,260)) end
  end
  local function populate_tree(tree,items,kind)
    tree:Clear()
    local ok=pcall(function()tree:SetHeaderLabels({kind})end)
    for i,v in ipairs(items) do
      local item=tree:NewItem()
      item.Text[0]=string.format('%d. %s',i,v.label)
      tree:AddTopLevelItem(item)
    end
  end
  local function search()
    results=Catalog.search(entries,w.CR_Search.Text,w.CR_Filter.CurrentText or 'All',50)
    local items={};for _,f in ipairs(results) do items[#items+1]={label=f.name..' — '..f.kind..' / '..(f.parent or 'World')} end
    populate_tree(w.CR_Results,items,'Search results')
    chosen=nil
    if #results==0 and #w.CR_Search.Text>0 then status('Location not found in bundled offline data.') end
  end
  local function refresh_objects()
    selected_id=nil;pendingDelete=nil;pendingReverse=nil
    state=engine:current()
    displayed={}
    if state then
      for _,o in ipairs(state.objects) do
        displayed[#displayed+1]={id=o.id,label=o.name..' ['..o.kind..']'}
      end
    end
    populate_tree(w.CR_Objects,displayed,'Scene objects')
    w.CR_Context.Text=state and ('Active CartoRig scene: '..state.id) or 'Composition has no CartoRig scene'
  end
  local function route_options()
    local curvature=tonumber(w.CR_Curvature.Text)
    if not curvature or curvature~=curvature or curvature==math.huge or curvature==-math.huge
      or curvature<-100 or curvature>100 then error('Curvature must be between -100 and 100') end
    local pathType=w.CR_PathType.CurrentText
    if pathType~='Straight' and pathType~='Curved' then error('Choose Straight or Curved') end
    return {pathType=pathType,curvature=curvature,waypoints=routeWaypoints or {}}
  end
  local function item_index(item)
    if not item then return nil end
    local ok,t=pcall(function()return item.Text[0]end)
    return ok and tonumber(t:match('^(%d+)%.')) or nil
  end
  win.On.CR_Initialize.Clicked=function()
    guarded(function()
      if state then return 'Scene already initialized' end
      local new_scene=Scene.new('cr2-'..tostring(os.time())..'-'..tostring(math.random(100000,999999)),bundleId)
      engine:initialize(new_scene.id,new_scene.manifestId)
      state=new_scene;refresh_objects()
      return 'Initialized Map Scene; select a country and Add as Region.'
    end)
  end
  win.On.CR_SearchBtn.Clicked=search
  win.On.CR_Filter.CurrentIndexChanged=search
  win.On.CR_Search.TextChanged=search
  win.On.CR_Results.CurrentItemChanged=function(ev)
    local index=item_index(w.CR_Results.CurrentItem)
    chosen=index and results[index] or nil
    if chosen then status('Selected '..chosen.name..' — '..chosen.kind..'; no scene changes yet.') end
  end
  win.On.CR_Objects.CurrentItemChanged=function()
    pendingDelete=nil;pendingReverse=nil
    local index=item_index(w.CR_Objects.CurrentItem)
    selected_id=index and displayed[index] and displayed[index].id or nil
    if selected_id then guarded(function()
      local selected=Scene.get(engine:current(),selected_id)
      if selected and selected.kind=='Route' then
        routeFrom=Scene.copy(selected.route.from)
        routeTo=Scene.copy(selected.route.to)
        routeWaypoints=Scene.copy(selected.route.waypoints)
        w.CR_PathType.CurrentIndex=selected.route.pathType=='Curved' and 1 or 0
        w.CR_Curvature.Text=tostring(selected.route.curvature or 0)
        w.CR_RouteState.Text='Route: editing '..selected.name..' ('..#routeWaypoints..' waypoints)'
      end
      if selected and selected.kind=='Group' then return 'Organizational Group selected in Scene (no render tool)' end
      engine:select(selected_id);return 'Selected object in Fusion Inspector'
    end) end
  end
  win.On.CR_AddRegion.Clicked=function()
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      if not chosen then error('Choose a location in search results') end
      if chosen.geometryType~='Polygon' and chosen.geometryType~='MultiPolygon' then error('Location has no polygon') end
      local feature=Catalog.load_feature(dataDir,chosen,Json)
      local draft,object=engine:add_location(feature,'Region')
      state=draft;refresh_objects()
      return 'Added '..chosen.name..'; select its Fusion node to edit native properties.'
    end)
  end
  local function add_point(kind)
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      if not chosen then error('Choose an explicit location first') end
      local feature=Catalog.load_feature(dataDir,chosen,Json)
      if not feature.point then error('This location has no point; choose a City or a custom coordinate') end
      local draft,object=engine:add_location(feature,kind)
      state=draft;refresh_objects()
      return 'Added '..kind..' '..object.name..' as independent Fusion tool.'
    end)
  end
  win.On.CR_FocusCamera.Clicked=function()
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      if not chosen then error('Search and select a geographic location first') end
      local location=Catalog.load_feature(dataDir,chosen,Json)
      if not location.point then error('This location has no point for Focus; use Fit Location for polygons') end
      state=engine:focus_camera(location.point)
      -- Do not refresh the tree; preserve the user's geographic selection.
      return 'Camera focused on '..location.name..' without creating keyframes.'
    end)
  end
  win.On.CR_FitLocation.Clicked=function()
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      if not chosen then error('Search and select a geographic location first') end
      local location=Catalog.load_feature(dataDir,chosen,Json)
      local w,h=engine.host:viewport()
      state=engine:fit_location(location,w,h)
      return 'Camera fitted to '..location.name..' using '..w..' x '..h..' composition viewport; no keyframes.'
    end)
  end
  win.On.CR_AddMarker.Clicked=function()add_point('Marker')end
  win.On.CR_AddLabel.Clicked=function()add_point('Label')end
  local function choose_endpoint(target)
    guarded(function()
      if not chosen then error('Select a City with an explicit point') end
      local feature=Catalog.load_feature(dataDir,chosen,Json)
      if feature.geometryType=='Polygon' or feature.geometryType=='MultiPolygon' then
        if target=='from' then routeFrom=nil;routeFromArea=chosen
        else routeTo=nil;routeToArea=chosen end
        return 'Selected area '..feature.name..': enter coordinates inside this region and click Use as Route '..target..'.'
      end
      if feature.geometryType~='Point' or not feature.point then
        error('This geographic result is not a point or polygon endpoint')
      end
      if target=='from' then routeFrom=feature.point;routeFromArea=nil
      else routeTo=feature.point;routeToArea=nil end
      w.CR_RouteState.Text='Route: From '..(routeFrom and 'set' or 'missing')..' / To '..(routeTo and 'set' or 'missing')
      return 'Route '..target..' selected: '..feature.name
    end)
  end
  local function custom_point()
    return Coordinates.parse(w.CR_CustomLon.Text,w.CR_CustomLat.Text)
  end
  local function set_custom_endpoint(slot)
    guarded(function()
      local p=custom_point()
      local selectedArea=slot=='from' and routeFromArea or routeToArea
      if selectedArea then
        local feature=Catalog.load_feature(dataDir,selectedArea,Json)
        if not Geo.contains_geojson(p,feature.geometry) then
          error('Selected coordinate is outside '..selectedArea.name..' or inside an excluded hole')
        end
      end
      if slot=='from' then routeFrom=p;routeFromArea=nil
      else routeTo=p;routeToArea=nil end
      w.CR_RouteState.Text='Route: From '..(routeFrom and 'set' or 'missing')..' / To '..(routeTo and 'set' or 'missing')
      return 'Route '..slot..' set to explicit WGS84 coordinates.'
    end)
  end
  win.On.CR_AddWaypoint.Clicked=function()
    guarded(function()
      local p=custom_point()
      routeWaypoints=routeWaypoints or {}
      if #routeWaypoints>=100 then error('Route waypoint limit reached') end
      routeWaypoints[#routeWaypoints+1]=p
      w.CR_RouteState.Text='Route: '..#routeWaypoints..' explicit waypoints pending'
      return 'Waypoint appended. Confirm by Create Route or Update Selected Route Geometry.'
    end)
  end
  win.On.CR_ClearWaypoints.Clicked=function()
    guarded(function()
      routeWaypoints={}
      w.CR_RouteState.Text='Route waypoints cleared (not yet saved)'
      return 'Pending waypoints cleared; Confirm with Create/Update.'
    end)
  end
  win.On.CR_CustomFrom.Clicked=function()set_custom_endpoint('from')end
  win.On.CR_CustomTo.Clicked=function()set_custom_endpoint('to')end
  local function add_custom(kind)
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      local draft,object=engine:add_custom_point(kind,custom_point())
      state=draft;refresh_objects()
      return 'Added independent '..kind..' at explicitly entered coordinates.'
    end)
  end
  win.On.CR_CustomMarker.Clicked=function()add_custom('Marker')end
  win.On.CR_CustomLabel.Clicked=function()add_custom('Label')end
  win.On.CR_CustomFocus.Clicked=function()
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      state=engine:focus_camera(custom_point())
      return 'Camera focused on custom point without adding keys.'
    end)
  end
  win.On.CR_RouteFrom.Clicked=function()choose_endpoint('from')end
  win.On.CR_RouteTo.Clicked=function()choose_endpoint('to')end
  win.On.CR_CreateRoute.Clicked=function()
    guarded(function()
      if not routeFrom or not routeTo then error('Specify both route point endpoints') end
      local draft,object=engine:add_route(routeFrom,routeTo,route_options())
      state=draft;refresh_objects()
      return 'Added Route '..object.id..' with native Fusion line mask.'
    end)
  end
  win.On.CR_UpdateRoute.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an existing Route in Scene objects') end
      if not routeFrom or not routeTo then error('Select explicit Route From and Route To endpoints first') end
      local current=engine:current()
      local object=Scene.get(current,selected_id)
      if not object or object.kind~='Route' then error('Selected object is not a Route') end
      local changes=route_options()
      changes.from=routeFrom;changes.to=routeTo
      state=engine:update_route(selected_id,changes)
      refresh_objects()
      return 'Updated Route geometry in its existing Fusion mask; Draw Progress keys preserved.'
    end)
  end
  win.On.CR_ReverseRoute.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an existing Route') end
      local object=Scene.get(engine:current(),selected_id)
      if not object or object.kind~='Route' then error('Selected object is not a Route') end
      if pendingReverse~=selected_id then
        pendingReverse=selected_id
        return 'Reverse Route swaps endpoints and travel direction; click again to confirm. Motion keys remain.'
      end
      pendingReverse=nil
      state=engine:reverse_route(selected_id,true)
      refresh_objects()
      return 'Route reversed in the existing Fusion mask; saved Draw Progress animation preserved.'
    end)
  end
  win.On.CR_Reveal.Clicked=function()
    guarded(function()
      if not state or not selected_id then error('Select a scene object') end
      local object=Scene.get(state,selected_id)
      engine:select(selected_id)
      return 'Selected '..object.name..' in Fusion Node Editor/Inspector.'
    end)
  end
  win.On.CR_Rename.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an authorial scene object first') end
      local obj=Scene.get(engine:current(),selected_id)
      if not obj or obj.kind=='BaseMap' or obj.kind=='Camera' then error('Cannot rename a structural scene object') end
      state=engine:rename(selected_id,w.CR_RenameField.Text)
      refresh_objects()
      return 'Renamed object. Stable identity and Fusion tools were preserved.'
    end)
  end
  local function move_selected(delta)
    guarded(function()
      if not selected_id then error('Select an authored scene object') end
      local current=engine:current()
      local index=nil
      for i,obj in ipairs(current.objects) do if obj.id==selected_id then index=i;break end end
      if not index or index<=2 then error('Base Map and Camera have fixed structural positions') end
      local destination=index+delta
      if destination<3 or destination>#current.objects then
        return 'Object is already at the edge of the layer stack.'
      end
      state=engine:reorder(selected_id,destination)
      refresh_objects()
      return 'Fusion draw order updated and saved.'
    end)
  end
  win.On.CR_MoveUp.Clicked=function()move_selected(-1)end
  win.On.CR_MoveDown.Clicked=function()move_selected(1)end
  -- Two-step confirmation, scoped to a stable object ID. Never delete
  -- whatever happens to be in the current row after a tree refresh.
  win.On.CR_Delete.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an authored object to delete') end
      local obj=Scene.get(engine:current(),selected_id)
      if not obj or obj.kind=='Camera' or obj.kind=='BaseMap' then
        error('Base Map and Camera are structural and cannot be deleted')
      end
      if pendingDelete~=selected_id then
        pendingDelete=selected_id
        return 'Confirm deletion of '..obj.name..': click Delete Selected again. No changes yet.'
      end
      pendingDelete=nil
      state=engine:delete(selected_id)
      refresh_objects()
      return 'Deleted CartoRig object and its owned Fusion tools. External nodes preserved.'
    end)
  end
  win.On.CR_Visibility.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an authorial scene object') end
      local obj=Scene.get(engine:current(),selected_id)
      if not obj then error('Object not found') end
      state=engine:set_visible(selected_id,not obj.visible)
      refresh_objects()
      return obj.visible and 'Hidden without deleting object/animation' or 'Object shown'
    end)
  end
  win.On.CR_Lock.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an authorial scene object') end
      local obj=Scene.get(engine:current(),selected_id)
      if not obj then error('Object not found') end
      state=engine:set_lock(selected_id,not obj.locked)
      refresh_objects()
      return obj.locked and 'Unlocked in CartoRig Scene' or 'Locked for CartoRig operations'
    end)
  end
  win.On.CR_GroupSelected.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an object to place in a group') end
      local groupName=w.CR_GroupName.Text
      if not groupName or groupName=='' then error('Enter a group name') end
      local draft,group=engine:create_group(groupName,{selected_id})
      state=draft;refresh_objects()
      return 'Created group '..group.name..' and placed the selected object inside.'
    end)
  end
  win.On.CR_Ungroup.Clicked=function()
    guarded(function()
      if not selected_id then error('Select an organizational Group') end
      local selected=Scene.get(engine:current(),selected_id)
      if not selected or selected.kind~='Group' then error('Selection is not a Group') end
      state=engine:ungroup(selected_id)
      refresh_objects()
      return 'Ungrouped; children, styles, Fusion nodes and keyframes preserved.'
    end)
  end
  win.On.CR_Refresh.Clicked=function()guarded(function()refresh_objects();return 'Scene refreshed' end)end
  win.On.CR_Close.Clicked=function()dispatcher:ExitLoop()end
  win.On.CartoRigSceneWindow.Close=function()dispatcher:ExitLoop()end
  if not ok_data then status('Offline location bundle missing or invalid; see diagnostics.') end
  refresh_objects();search()
  if state and state.manifestId~=bundleId then status('Source mismatch: installed Natural Earth data differ from saved scene. Editing blocked.') end
  win:Show();dispatcher:RunLoop();win:Hide()
end
local ok,err=xpcall(run,debug.traceback)
if not ok then
  log('FATAL: '..tostring(err))
  pcall(function()print('[CartoRig rewrite] '..tostring(err))end)
end
