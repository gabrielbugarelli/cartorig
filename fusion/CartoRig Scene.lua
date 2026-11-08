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
  local fus=rawget(_G,'fusion') or rawget(_G,'fu')
  local comp=rawget(_G,'comp')
  if not comp and fus and fus.GetCurrentComp then comp=fus:GetCurrentComp() end
  if not comp then error('Open a Fusion Composition before launching CartoRig Scene') end
  local bridge=rawget(_G,'bmd')
  local ui=fus and fus.UIManager
  if not ui or not bridge or type(bridge.UIDispatcher)~='function' then error('Resolve Fusion UIManager is unavailable') end
  local host=Host.new(comp,bridge)
  local entries={};local results={};local displayed={}
  local state=Repository.read(comp,Scene,Json)
  local bundle_path=dir..'/CartoRig/data/ne_110m_admin_0_countries.geojson'
  local ok_data,load_error=pcall(function()
    local doc=Catalog.load_bundle(bundle_path,Json)
    entries=Catalog.from_geojson(doc,'Country',{dataset='Natural Earth Admin 0',version='110m-preview',scale='110m'})
  end)
  if not ok_data then log('BUNDLE ERROR: '..tostring(load_error)) end
  local dispatcher=bridge.UIDispatcher(ui)
  local win=dispatcher:AddWindow({ID='CartoRigSceneWindow',WindowTitle='CartoRig — Scene (Rewrite Preview)',Geometry={120,120,470,680}},
    ui:VGroup{Spacing=7,
      ui:Label{ID='CR_Header',Text='CARTORIG — SCENE'},
      ui:Label{ID='CR_Context',Text='Fusion Composition'},
      ui:Button{ID='CR_Initialize',Text='Initialize Map Scene'},
      ui:HGroup{ui:LineEdit{ID='CR_Search',PlaceholderText='Search location'},ui:Button{ID='CR_SearchBtn',Text='Find'}},
      ui:Label{Text='OFFLINE LOCATIONS (Admin-0 preview)'},
      ui:Tree{ID='CR_Results',ColumnCount=1,SortingEnabled=false,MinimumSize={320,160}},
      ui:Button{ID='CR_AddRegion',Text='Add as Region'},
      ui:Label{Text='SCENE OBJECTS'},
      ui:Tree{ID='CR_Objects',ColumnCount=1,SortingEnabled=false,MinimumSize={320,200}},
      ui:HGroup{ui:Button{ID='CR_Reveal',Text='Reveal in Fusion'},ui:Button{ID='CR_Refresh',Text='Refresh'}},
      ui:Label{ID='CR_Status',Text='Ready'},
      ui:Button{ID='CR_Close',Text='Close Scene'},
    })
  local w=win:GetItems()
  local chosen=nil;local selected_id=nil
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
    results=Catalog.search(entries,w.CR_Search.Text,'All',50)
    local items={};for _,f in ipairs(results) do items[#items+1]={label=f.name..' — '..f.kind..' / '..(f.parent or 'World')} end
    populate_tree(w.CR_Results,items,'Search results')
    chosen=nil
    if #results==0 and #w.CR_Search.Text>0 then status('Location not found in bundled offline data.') end
  end
  local function refresh_objects()
    state=Repository.read(comp,Scene,Json)
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
      local new_scene=Scene.new('cr2-'..tostring(os.time())..'-'..tostring(math.random(100000,999999)),'natural-earth-110m-preview')
      host:init_base(new_scene)
      Repository.write(comp,new_scene,Scene,Json)
      state=new_scene;refresh_objects()
      return 'Initialized Map Scene; select a country and Add as Region.'
    end)
  end
  win.On.CR_SearchBtn.Clicked=search
  win.On.CR_Search.TextChanged=search
  win.On.CR_Results.CurrentItemChanged=function(ev)
    local index=item_index(w.CR_Results.CurrentItem)
    chosen=index and results[index] or nil
    if chosen then status('Selected '..chosen.name..' — '..chosen.kind..'; no scene changes yet.') end
  end
  win.On.CR_Objects.CurrentItemChanged=function()
    local index=item_index(w.CR_Objects.CurrentItem)
    selected_id=index and displayed[index] and displayed[index].id or nil
  end
  win.On.CR_AddRegion.Clicked=function()
    guarded(function()
      if not state then error('Initialize Map Scene first') end
      if not chosen then error('Choose a location in search results') end
      if chosen.geometryType~='Polygon' and chosen.geometryType~='MultiPolygon' then error('Location has no polygon') end
      local draft=Scene.snapshot(state)
      local object=Scene.add_location(draft,{id=chosen.id,name=chosen.name,type=chosen.kind,geometryType=chosen.geometryType,
        version=chosen.source.version,dataset=chosen.source.dataset},'Region')
      host:add_region(draft,object,chosen)
      Repository.write(comp,draft,Scene,Json)
      state=draft;refresh_objects()
      return 'Added '..chosen.name..'; select its Fusion node to edit native properties.'
    end)
  end
  win.On.CR_Reveal.Clicked=function()
    guarded(function()
      if not state or not selected_id then error('Select a scene object') end
      local object=Scene.get(state,selected_id)
      host:select(object)
      return 'Selected '..object.name..' in Fusion Node Editor/Inspector.'
    end)
  end
  win.On.CR_Refresh.Clicked=function()guarded(function()refresh_objects();return 'Scene refreshed' end)end
  win.On.CR_Close.Clicked=function()dispatcher:ExitLoop()end
  win.On.CartoRigSceneWindow.Close=function()dispatcher:ExitLoop()end
  if not ok_data then status('Offline location bundle missing or invalid; see diagnostics.') end
  refresh_objects();search()
  win:Show();dispatcher:RunLoop();win:Hide()
end
local ok,err=xpcall(run,debug.traceback)
if not ok then
  log('FATAL: '..tostring(err))
  pcall(function()print('[CartoRig rewrite] '..tostring(err))end)
end
