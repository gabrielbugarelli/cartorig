local r=assert(arg[1]);local function load(n)return dofile(r..'/src/cartorig/'..n..'.lua')end
local m={Scene=load('scene'),Repository=load('repository'),Json=load('json'),Host=load('fusion_host'),
Objects=load('fusion_objects'),Geo=load('geo'),Motion=load('motion'),Writer=load('motion_apply')}
local A=load('authoring')
local function mock()
 local comp={nodes={},data={},failMetadata=false}
 local t={};t.__index=t
 function t:SetAttrs(a)self.Name=a.TOOLS_Name end
 function t:GetAttrs()return {TOOLS_RegID=self.ID,TOOLS_Name=self.Name}end
 function t:GetData(k)return self.data[k]end
 function t:SetData(k,v)self.data[k]=v end
 function t:SetInput(k,v,f)self.inputs[k]=self.inputs[k] or {};self.inputs[k][f or 'static']=v;return true end
 function t:ConnectInput(k,src)self.links[k]=src;return true end
 function t:AddModifier(k,v)self.mods[k]=v;return true end
 function t:Delete()self.deleted=true end
 function comp:AddTool(kind) local x=setmetatable({ID=kind,Name=kind..#self.nodes,data={},inputs={},links={},mods={}},t);self.nodes[#self.nodes+1]=x;return x end
 function comp:GetToolList()local a={};for _,n in ipairs(self.nodes)do if not n.deleted then a[#a+1]=n end end;return a end
 function comp:FindTool(name)for _,n in ipairs(self.nodes)do if not n.deleted and n.Name==name then return n end end end
 function comp:GetData(k)return self.data[k]end
 function comp:SetData(k,v)if self.failMetadata then return false end;self.data[k]=v;return true end
 function comp:StartUndo()end;function comp:EndUndo()end
 comp:AddTool('MediaOut')
 return comp
end
local bridge={readstring=function(txt)return txt end}
local comp=mock();local engine=A.new(comp,m,bridge)
local scene=engine:initialize('fresh-2026-0001','natural-earth-local')
assert(scene.hostInitialized and scene.lastLayerRef)
assert(engine:current().id=='fresh-2026-0001')
local city={id='point:BR:Rio',name='Rio de Janeiro',kind='City',source={dataset='NE',version='10m'},geometryType='Point',point={lon=-43.2,lat=-22.9}}
local new,marker=engine:add_location(city,'Marker')
assert(marker.hostToolRef and engine:current().objects[3].id==marker.id)
local newer,label=engine:add_location(city,'Label')
assert(label.hostToolRef and engine:current().objects[4].kind=='Label')
local routed,route=engine:add_route({lon=-47.9,lat=-15.8},{lon=-51.5,lat=1.5})
assert(route.hostToolRef and engine:current().objects[5].id==route.id)
local plan=engine:motion(marker.id,'MO-MRK-02',{start=20,frameCount=400})
assert(plan.channels.size and #plan.channels.size==3)
assert(comp:FindTool(marker.maskToolRef).inputs.Width[38])
local before=#comp:GetToolList()
comp.failMetadata=true
assert(not pcall(function() engine:add_location(city,'Marker') end))
assert(#comp:GetToolList()==before)
assert(engine:current().serial==routed.serial)
-- First-scene persistence failure must also leave no owned tools.
local failcomp=mock();failcomp.failMetadata=true
local failing=A.new(failcomp,m,bridge)
assert(not pcall(function()failing:initialize('fresh-2026-bad','missing')end))
assert(#failcomp:GetToolList()==1)
print('PASS authoring: persisted scene, Marker/Label/Route, native Pop, rollback on metadata failure')
