local root=arg[1]
local C=assert(loadfile(root..'/fusion/CartoRig/catalog.lua'))()
local G=assert(loadfile(root..'/fusion/CartoRig/graph.lua'))()
local f=C.load(root..'/fusion/CartoRig/data')
assert(#f>=178)
assert(C.search(f,'Brasil','Country',5)[1].name=='Brazil')
local x,y=C.project(-47.917998,-15.781394)
assert(math.abs(x-0.36689445)<1e-7 and y>0 and y<1)
local nodes, data, undos={}, {}, {}
_G.Polyline=function(p) assert(type(p.Points)=='table');return p end
local tool={}
tool.__index=tool
function tool:GetAttrs()return {TOOLS_RegID=self.regid} end
function tool:SetAttrs(a) self.Name=a.TOOLS_Name end
function tool:SetData(k,v)self.data[k]=v end
function tool:GetData(k)return self.data[k] end
function tool:SetInput(k,v,t)
   self.inputs[k]=self.inputs[k] or {}
   self.inputs[k][t or 'static']=v
end
function tool:GetInput(k,t)
   return self.inputs[k] and self.inputs[k][t or 'static']
end
function tool:AddModifier(k,kind)
   assert(kind=='BezierSpline' or kind=='XYPath');self.modifiers[k]=kind
   return true
end
function tool:ConnectInput(k,src)
   assert(src and src~=self);self.connections[k]=src
   return true
end
function tool:Delete()
    for i,t in ipairs(nodes) do if t==self then table.remove(nodes,i);break end end
end
local function new(kind)
   local n=setmetatable({regid=kind,ID=kind,Name=kind..tostring(#nodes+1),data={},inputs={},modifiers={},connections={}},tool)
   nodes[#nodes+1]=n;return n
end
new('MediaOut')
local comp={CurrentTime=0}
function comp:GetData(k)return data[k]end
function comp:SetData(k,v)data[k]=v end
function comp:GetToolList()return nodes end
function comp:AddTool(kind) return new(kind) end
function comp:FindTool(name) for _,n in ipairs(nodes)do if n.Name==name then return n end end end
function comp:StartUndo(name)self.undo=name end
function comp:EndUndo(ok) assert(ok);undos[#undos+1]=self.undo end
function comp:Lock()self.locked=true end
function comp:Unlock()self.locked=false end
function comp:SetActiveTool(t)self.active=t end
local flow={Select=function(self,t) comp.selected=t end}
comp.CurrentFrame={FlowView=flow}
assert(G.ensure(comp,f)==true)
assert(G.ensure(comp,f)==false)
local world=comp:FindTool('CR2_Land')
local ocean=comp:FindTool('CR2_Ocean')
assert(world and ocean and world~=ocean)
local base=G.get_base(comp)
assert(base.land==world and base.ocean==ocean)
local brazil=C.search(f,'Brazil','Country',5)[1]
assert(brazil.id and brazil.polygons)
local id=G.add_region(comp,brazil)
assert(id=='1')
local objects=G.get_objects(comp)
assert(#objects==1 and objects[1].featureId==brazil.id)
assert(G.select(comp,objects[1].node))
assert(comp.selected==objects[1].node)
G.set_fill(comp,objects[1],'#C92A2A',false)
assert(math.abs(objects[1].node:GetInput('TopLeftRed')-0.788235294)<1e-6)
comp.CurrentTime=0
G.set_fill(comp,objects[1],'#C92A2A',true)
comp.CurrentTime=329
G.set_fill(comp,objects[1],'#C92A2A',true)
comp.CurrentTime=330
G.set_fill(comp,objects[1],'#20A65A',true)
assert(objects[1].node:GetInput('TopLeftRed',330)~=objects[1].node:GetInput('TopLeftRed',329))
assert(world:GetInput('TopLeftRed',330)==nil)
G.set_opacity(comp,objects[1],64,true)
assert(math.abs(objects[1].node:GetInput('TopLeftAlpha',330)-0.64)<1e-9)
local city={id='city:fake',kind='City',name='Test location',parent='Brazil',lat=-23.55,lon=-46.63}
local state={id='state:fake',kind='State',name='Test state',parent='Brazil',lat=0.3,lon=-51.2}
local marker=G.add_marker(comp,city)
assert(marker=='2')
local route=G.add_route(comp,city,state)
assert(route=='3')
objects=G.get_objects(comp)
assert(#objects==3)
assert(objects[3].kind=='Route')
comp.CurrentTime=0
G.route_reveal(comp,objects[3],0)
comp.CurrentTime=30
G.route_reveal(comp,objects[3],100)
local route_mask=comp:FindTool(objects[3].node:GetData('CartoRig.RouteMask'))
assert(route_mask:GetInput('WriteLength',0)==0)
assert(route_mask:GetInput('WriteLength',30)==1)
comp.CurrentTime=0
G.camera_focus(comp,city,3,false)
local cam=comp:FindTool('CR2_Camera')
assert(cam and cam:GetInput('Size')==3)
comp.CurrentTime=45
G.camera_focus(comp,state,5,true)
assert(cam:GetInput('Size',45)==5)
assert(cam:GetInput('Center',45))
assert(cam.connections.Input==comp:FindTool(data['CartoRig.Scene.LastLayer']))
assert(comp:FindTool('MediaOut1').connections.Input==cam)
assert(comp.locked==false)
assert(#undos>=9)
print('PASS: Greenfield geographic scene, 177 countries, 3 independent objects, route, camera, keyframes and persistence gates simulated')
