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
  local Motion=module('motion')
  local Writer=module('motion_apply')
  local Authoring=module('authoring')
  local GraphOps=module('graph_ops')
  local Manifest=module('manifest')
  local fus=rawget(_G,'fusion') or rawget(_G,'fu')
  local comp=rawget(_G,'comp')
  if not comp and fus and fus.GetCurrentComp then comp=fus:GetCurrentComp() end
  if not comp then error('Open a Fusion Composition before launching CartoRig Scene') end
  local bridge=rawget(_G,'bmd')
  local ui=fus and fus.UIManager
  if not ui or not bridge or type(bridge.UIDispatcher)~='function' then error('Resolve Fusion UIManager is unavailable') end
  local bundleId=Manifest.load(dir..'/CartoRig/data/manifest.json',Json).id
  local engine=Authoring.new(comp,{Scene=Scene,Repository=Repository,Json=Json,Host=Host,Objects=Objects,Geo=Geo,Motion=Motion,Writer=Writer,GraphOps=GraphOps},bridge,bundleId)
  local host=engine.host
  local entries={};local results={};local displayed={}
  local state=engine:current()
  local dataDir=dir..'/CartoRig/data'
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
      ui:HGroup{ui:Button{ID='CR_RouteFrom',Text='Route From'},ui:Button{ID='CR_RouteTo',Text='Route To'},ui:Button{ID='CR_CreateRoute',Text='Create Route'}},
      ui:Label{ID='CR_RouteState',Text='Route: choose explicit point endpoints'},
      ui:Label{Text='SCENE OBJECTS'},
      ui:Tree{ID='CR_Objects',ColumnCount=1,SortingEnabled=false,MinimumSize={320,200}},
      ui:HGroup{ui:Button{ID='CR_Reveal',Text='Reveal in Fusion'},ui:Button{ID='CR_Refresh',Text='Refresh'}},
      ui:HGroup{ui:LineEdit{ID='CR_RenameField',PlaceholderText='New object name'},ui:Button{ID='CR_Rename',Text='Rename'}},
      ui:HGroup{ui:Button{ID='CR_MoveUp',Text='Move Up'},ui:Button{ID='CR_MoveDown',Text='Move Down'}},
      ui:HGroup{ui:Button{ID='CR_Visibility',Text='Hide / Show'},ui:Button{ID='CR_Lock',Text='Lock / Unlock'}},
      ui:Label{ID='CR_Status',Text='Ready'},
      ui:Button{ID='CR_Close',Text='Close Scene'},
    })
  local w=win:GetItems()
  local chosen=nil;local selected_id=nil
  local routeFrom,routeTo=nil,nil
  local filters={'All','Continent','Country','State','City'}
  for _,kind in ipairs(filters) do w.CR_Filter:AddItem(kind) end
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
    local index=item_index(w.CR_Objects.CurrentItem)
    selected_id=index and displayed[index] and displayed[index].id or nil
    if selected_id then guarded(function()engine:select(selected_id);return 'Selected object in Fusion Inspector' end) end
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
  win.On.CR_AddMarker.Clicked=function()add_point('Marker')end
  win.On.CR_AddLabel.Clicked=function()add_point('Label')end
  local function choose_endpoint(target)
    guarded(function()
      if not chosen then error('Select a City with an explicit point') end
      local feature=Catalog.load_feature(dataDir,chosen,Json)
      if feature.geometryType~='Point' or not feature.point then
        error('A Country or State is an area. Select a City or specify coordinates; no implicit capital/centroid.')
      end
      if target=='from' then routeFrom=feature.point else routeTo=feature.point end
      w.CR_RouteState.Text='Route: From '..(routeFrom and 'set' or 'missing')..' / To '..(routeTo and 'set' or 'missing')
      return 'Route '..target..' selected: '..feature.name
    end)
  end
  win.On.CR_RouteFrom.Clicked=function()choose_endpoint('from')end
  win.On.CR_RouteTo.Clicked=function()choose_endpoint('to')end
  win.On.CR_CreateRoute.Clicked=function()
    guarded(function()
      if not routeFrom or not routeTo then error('Specify both route point endpoints') end
      local draft,object=engine:add_route(routeFrom,routeTo)
      state=draft;refresh_objects()
      return 'Added Route '..object.id..' with native Fusion line mask.'
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
