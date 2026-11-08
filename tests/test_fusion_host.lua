local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua');local Host=dofile(root..'/src/cartorig/fusion_host.lua')
local comp={nodes={},state={}};local mt={}
mt.__index=mt
function mt:SetAttrs(attrs)self.Name=attrs.TOOLS_Name end
function mt:GetAttrs()return {TOOLS_RegID=self.regid,TOOLS_Name=self.Name}end
function mt:SetData(k,v)self.data[k]=v end
function mt:GetData(k)return self.data[k] end
function mt:SetInput(k,v,frame)self.inputs[k]=self.inputs[k] or {};self.inputs[k][frame or 'static']=v end
function mt:ConnectInput(k,t)self.connections[k]=t;return true end
function mt:Delete()self.deleted=true end
function mt:AddModifier(k,v)self.modifiers[k]=v;return true end
function comp:AddTool(id) local n=setmetatable({regid=id,ID=id,Name=id..#self.nodes,data={},inputs={},connections={},modifiers={}},mt);self.nodes[#self.nodes+1]=n;return n end
function comp:GetToolList()return self.nodes end
function comp:FindTool(name)for _,n in ipairs(self.nodes)do if n.Name==name and not n.deleted then return n end end end
function comp:StartUndo(_)end
function comp:EndUndo(_)end
local output=comp:AddTool('MediaOut')
local host=Host.new(comp,{readstring=function(s)assert(s:find('Polyline {',1,true));return {serialized=s} end})
local state=Scene.new('scene-0001')
assert(host:init_base(state))
assert(state.lastLayerRef and state.hostInitialized)
local feature={id='Brazil',name='Brazil',type='Country',geometryType='Polygon',geometry={type='Polygon',coordinates={{{-54,-30},{-30,-30},{-30,6},{-54,6}}}}}
local obj=Scene.add_location(state,feature,'Region')
assert(host:add_region(state,obj,feature))
assert(obj.hostToolRef and host:tool_for(obj))
assert(output.connections.Input and output.connections.Input.regid=='Transform')
local plan={channels={fill={{frame=329,value='#C92A2A'},{frame=330,value='#20A65A'}}}}
host:apply_color_plan(obj,plan)
local tool=host:tool_for(obj)
assert(tool.inputs.TopLeftRed[329]~=tool.inputs.TopLeftRed[330])
assert(tool.modifiers.TopLeftRed=='BezierSpline')
assert(tool:GetData('CartoRig.V2.ObjectId')==obj.id)
print('PASS Fusion host mock: initialize, polygon mask via readstring, scene object, native RGB splines')
