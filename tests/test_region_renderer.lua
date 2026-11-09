local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local Host=dofile(root..'/src/cartorig/fusion_host.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local comp={nodes={},out=nil};local tool={};tool.__index=tool
function tool:SetAttrs(v)self.Name=v.TOOLS_Name end
function tool:GetAttrs()return {TOOLS_Name=self.Name,TOOLS_RegID=self.ID}end
function tool:SetData(k,v)self.data[k]=v end
function tool:GetData(k)return self.data[k]end
function tool:SetInput(k,v,f)self.inputs[k]=self.inputs[k]or{};self.inputs[k][f or 'static']=v;return true end
function tool:ConnectInput(k,v)self.links[k]=v;return true end
function tool:AddModifier(k,v)self.mods[k]=v;return true end
function tool:Delete()self.deleted=true end
function comp:AddTool(kind)
  if self.failStyle and kind=='CartoRigRegion' then return nil end
  local n=setmetatable({ID=kind,Name='T'..#self.nodes,data={},inputs={},links={},mods={}},tool)
  self.nodes[#self.nodes+1]=n;return n
end
function comp:GetToolList()local list={}for _,n in ipairs(self.nodes)do if not n.deleted then list[#list+1]=n end end return list end
function comp:FindTool(name)for _,n in ipairs(self.nodes)do if n.Name==name and not n.deleted then return n end end end
function comp:StartUndo(x)self.undo=x end
function comp:EndUndo(ok)self.result=ok end
local out=comp:AddTool('MediaOut')
local host=Host.new(comp,{readstring=function(source)
  assert(source:find('Polyline {',1,true) or source:find('FuID {',1,true));return {value=source}
end})
local scene=Scene.new('region-scene-0001','naturalearth-10m')
assert(host:init_base(scene))
local feature={id='islands',name='Islands',type='Country',geometryType='MultiPolygon',
geometry={type='MultiPolygon',coordinates={
  {{{-55,-20},{-50,-20},{-50,-15},{-55,-20}}},
  {{{-47,0},{-43,0},{-43,4},{-47,0}}}
}}}
local obj=Scene.add_location(scene,feature,'Region')
assert(host:add_region(scene,obj,feature))
local style=host:tool_for(obj)
assert(style and style.ID=='CartoRigRegion' and style:GetData('CartoRig.V2.Kind')=='Region')
assert(style.inputs.FillAlpha.static==1, 'independent Fill Alpha from canonical Region style')
assert(style.inputs.ObjectOpacity.static==1)
assert(style.links.Input and style.links.Input.ID=='Merge')
assert(style.links.StrokeInput and style.links.StrokeInput.ID=='Merge')
assert(style.inputs.StrokeRed.static and style.inputs.StrokeAlpha.static==1)
assert(obj.compositeToolRef and comp:FindTool(obj.compositeToolRef).links.Foreground==style)
assert(comp:FindTool('CR2_CAMERA_'..scene.id).links.Input==comp:FindTool(obj.compositeToolRef))
local fragments,strokeMasks=0,0
for _,t in ipairs(comp:GetToolList())do
  if t.ID=='PolylineMask' and t:GetData('CartoRig.V2.ObjectId')==obj.id then
    if t:GetData('CartoRig.V2.Kind')=='InternalMask' then fragments=fragments+1 end
    if t:GetData('CartoRig.V2.Kind')=='InternalStrokeMask' then
      strokeMasks=strokeMasks+1
      assert(t.inputs.Solid.static==0 and math.abs(t.inputs.BorderWidth.static-1.5/1080)<1e-9)
    end
  end
end
assert(fragments==2 and strokeMasks==2,'all islands require independent fill and stroke masks')
local color=Motion.prepare(obj,'MO-REG-03',{start=0,frameCount=90,targetColor='#00FF00'}, {})
assert(Writer.apply(host,obj,color))
assert(style.inputs.FillRed[24]==0 and style.inputs.FillGreen[24]==1)
local fade=Motion.prepare(obj,'MO-REG-01',{start=25,frameCount=90},{})
assert(Writer.apply(host,obj,fade))
assert(style.inputs.ObjectOpacity[25]==0 and style.inputs.ObjectOpacity[49]==1)
local pulse=Motion.prepare(obj,'MO-REG-06',{start=0,frameCount=90,pulseCount=2,cycle=18,peak=35},{})
assert(Writer.apply(host,obj,pulse))
assert(math.abs(style.inputs.HighlightStrength[9]-0.35)<1e-9)
-- Geographic seam wrapping is clipped into separate native mask pieces, with
-- both hole masks preserved instead of drawing a world-spanning edge.
local seamFeature={id='seam-island',name='Seam Island',type='Country',geometryType='Polygon',
  geometry={type='Polygon',coordinates={
    {{170,-10},{-170,-10},{-170,10},{170,10},{170,-10}},
    {{175,-4},{-175,-4},{-175,4},{175,4},{175,-4}},
  }}}
local seamObject=Scene.add_location(scene,seamFeature,'Region')
assert(host:add_region(scene,seamObject,seamFeature))
local seamOuter,seamHoles=0,0
for _,t in ipairs(comp:GetToolList())do
  if t:GetData('CartoRig.V2.ObjectId')==seamObject.id
    and t:GetData('CartoRig.V2.Kind')=='InternalMask' then
    local source=t.inputs.Polyline and t.inputs.Polyline.static
    assert(source and type(source.value)=='string')
    if (t.Name or ''):find('Hole',1,true) then seamHoles=seamHoles+1
    else seamOuter=seamOuter+1 end
  end
end
assert(seamOuter==2 and seamHoles==2,'antimeridian clipped outer+hole rings on both sides')
-- Fail-closed: when the real Fuse is missing, no extra scene nodes may remain.
comp.failStyle=true
local before=#comp:GetToolList()
local failed=Scene.add_location(scene,feature,'Region')
local prev=scene.lastLayerRef
assert(not pcall(function()host:add_region(scene,failed,feature)end))
assert(#comp:GetToolList()==before)
assert(comp:FindTool('CR2_CAMERA_'..scene.id).links.Input==comp:FindTool(prev))
print('PASS Region renderer: 2 polygons one Fuse Control/Motion tool, 3 native motions, rollback')
