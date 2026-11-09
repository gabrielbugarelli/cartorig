-- CartoRig Host Diagnostics -- NON-DESTRUCTIVE gate for Resolve Studio 20.
-- Run ONLY in a new disposable Fusion Composition. Never writes MediaOut.
-- This script does not certify final render or UI; it tests actual host registry,
-- geometry input, Mask PaintMode and native animation key persistence.
local function main()
  local comp=rawget(_G,'comp')
  local fusion=rawget(_G,'fusion') or rawget(_G,'fu')
  if not comp and fusion and fusion.GetCurrentComp then comp=fusion:GetCurrentComp()end
  if not comp then error('CartoRig diagnostics requires a selected Fusion Composition')end
  local bmd=rawget(_G,'bmd')
  local results={}
  local function mark(id,ok,detail)
    results[#results+1]={id=id,status=ok and 'PASS' or 'FAIL',detail=tostring(detail or '')}
  end
  local tools=comp:GetToolList(false) or {}
  for _,tool in pairs(tools) do
    local attrs=tool:GetAttrs() or {}
    if attrs.TOOLS_RegID~='MediaOut' and tool.ID~='MediaOut' then
      error('Diagnostics refused: use a NEW EMPTY disposable Fusion Composition. No nodes were changed.')
    end
  end
  local created={}
  local function new(id)
    local node=comp:AddTool(id,false,4+#created,5)
    if not node then error('Registry ID unavailable: '..id)end
    created[#created+1]=node
    return node
  end
  local function gate(id,fn)
    local ok,result=pcall(fn)
    mark(id,ok,result)
  end
  local function input(node,name)
    if type(node.GetInputList)~='function' then return nil end
    local a=node:GetInputList() or {}
    return a[name]
  end
  gate('BASE_FUSE_REGISTERED',function()
    local node=new('CartoRigBase')
    assert(input(node,'DisplayMode'),'Base Fuse DisplayMode missing')
    assert(input(node,'OceanLayerOpacity'),'Base Fuse OceanLayerOpacity missing')
    return 'CartoRigBase controls exposed in real host'
  end)
  local region
  gate('REGION_FUSE_REGISTERED',function()
    region=new('CartoRigRegion')
    for _,name in ipairs({'FillRed','FillGreen','FillBlue','ObjectOpacity','HighlightStrength'}) do
      assert(input(region,name),name..' missing from Region Fuse')
    end
    return 'Region Control channels exposed'
  end)
  gate('CAMERA_FUSE_REGISTERED',function()
    local node=new('CartoRigCamera')
    for _,name in ipairs({'CenterLongitude','CenterLatitude','Zoom','Bearing'}) do
      assert(input(node,name),'Camera control missing: '..name)
    end
    return 'Geographic camera channels exposed in the host'
  end)
  for _,kind in ipairs({'Marker','Route','Label'}) do
    gate(kind:upper()..'_FUSE_REGISTERED',function()
      local node=new('CartoRig'..kind)
      assert(input(node,'ObjectOpacity'),kind..' native opacity unavailable')
      local prefix=kind=='Marker' and 'Fill' or (kind=='Route' and 'Stroke' or 'Text')
      for _,channel in ipairs({'Red','Green','Blue'}) do
        assert(input(node,prefix..channel),kind..' color input missing: '..channel)
      end
      return kind..' authorial Fuse registered with Control channels'
    end)
  end
  local outer,hole
  gate('POLYLINE_MASK',function()
    assert(bmd and type(bmd.readstring)=='function','bmd.readstring missing')
    local poly=bmd.readstring('Polyline { Closed = true, Points = { [1] = { Linear = true, X = -0.05, Y = -0.05 }, [2] = { Linear = true, X = 0.05, Y = -0.05 }, [3] = { Linear = true, X = 0.05, Y = 0.05 }, [4] = { Linear = true, X = -0.05, Y = 0.05 } } }')
    assert(poly,'native Polyline parsing failed')
    outer=new('PolylineMask')
    assert(outer:SetInput('Polyline',poly)~=false,'PolylineMask rejected geometry')
    return 'Native Polygon geometry loaded without a global constructor'
  end)
  gate('POLYGON_HOLE_SUBTRACT',function()
    assert(outer,'outer PolygonMask unavailable')
    local sub=bmd.readstring('FuID { "Subtract" }')
    assert(sub,'Fuse FuID Subtract parsing failed')
    hole=new('PolylineMask')
    assert(hole:SetInput('Polyline',bmd.readstring('Polyline { Closed = true, Points = { [1] = { Linear = true, X = -0.01, Y = -0.01 }, [2] = { Linear = true, X = 0.01, Y = -0.01 }, [3] = { Linear = true, X = 0.01, Y = 0.01 }, [4] = { Linear = true, X = -0.01, Y = 0.01 } } }'))~=false)
    assert(hole:SetInput('PaintMode',sub)~=false,'PaintMode rejected Subtract')
    assert(hole:ConnectInput('EffectMask',outer)~=false,'EffectMask chain refused')
    return 'Subtract mask chained to outer mask'
  end)
  gate('SPLINE_NATIVE',function()
    assert(region,'Region Fuse absent')
    assert(region:AddModifier('FillRed','BezierSpline')~=false,'AddModifier failed')
    assert(region:SetInput('FillRed',0.25,5)~=false,'first key refused')
    assert(region:SetInput('FillRed',0.75,20)~=false,'second key refused')
    local field=input(region,'FillRed')
    if field and type(field.GetKeyFrames)=='function' then
      local keys=field:GetKeyFrames()
      assert(keys and next(keys),'No native Spline keys reported')
      return 'Native keyframes available via GetKeyFrames'
    end
    return 'SetInput keys accepted; GetKeyFrames method unavailable: visual Spline test required'
  end)
  -- Cleanup is unconditional, even when individual gates fail. Delete backwards
  -- to avoid leaving dependent mask/Fuse nodes in a test composition.
  local cleanup_errors={}
  for i=#created,1,-1 do
    local ok,why=pcall(function()created[i]:Delete()end)
    if not ok then cleanup_errors[#cleanup_errors+1]=tostring(why)end
  end
  mark('CLEANUP',#cleanup_errors==0,table.concat(cleanup_errors,' | '))
  local temp=os.getenv('TEMP') or os.getenv('TMP') or os.getenv('TMPDIR') or '.'
  local path=temp..'/CartoRig_Host_Diagnostics.txt'
  local f=io.open(path,'w')
  if f then
    f:write('CartoRig Resolve Studio 20 host diagnostics (not a render certification)\n')
    for _,r in ipairs(results) do f:write(r.id..' '..r.status..' '..r.detail..'\n') end
    f:close()
  end
  local passed=0
  for _,r in ipairs(results) do
    print('[CartoRig Host] '..r.id..': '..r.status..' '..r.detail)
    if r.status=='PASS' then passed=passed+1 end
  end
  print('[CartoRig Host] '..passed..'/'..#results..' basic gates passed; report: '..path)
  return passed==#results
end
local ok,result=xpcall(main,function(e)return debug.traceback(tostring(e),2)end)
if not ok then print('[CartoRig Host] FAIL: '..tostring(result))end
