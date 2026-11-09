local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local Writer=dofile(root..'/src/cartorig/motion_apply.lua')
local Motion=dofile(root..'/src/cartorig/motion.lua')
local scene=Scene.new('fusion-manual-keys-01')
local obj=Scene.add_location(scene,{id='country:1',name='Example',geometryType='Polygon',type='Country'},'Region')
local manual={}
local node={data={},inputs={},modifiers={}}
function node:GetData(k)return self.data[k]end
function node:SetData(k,v)self.data[k]=v end
function node:GetInputList()
  return {FillRed={GetKeyFrames=function()return manual end},FillGreen={GetKeyFrames=function()return {} end},FillBlue={GetKeyFrames=function()return {} end}}
end
function node:AddModifier(name,kind)self.modifiers[name]=kind;return true end
function node:SetInput(name,value,frame)
  self.inputs[name]=self.inputs[name] or {};self.inputs[name][frame]=value;return true
end
local comp={undo=0}
function comp:StartUndo()self.undo=self.undo+1 end
function comp:EndUndo()end
local host={comp=comp}
function host:tool_for(object)return node end
local plan=Motion.prepare(obj,'MO-REG-03',{start=10,frameCount=100,targetColor='#00FF00'}, {})
manual[25]={Value=0.5}
local ok,msg=pcall(function()Writer.apply(host,obj,plan)end)
assert(not ok and tostring(msg):find('CONFLICT',1,true))
assert(comp.undo==0 and next(node.modifiers)==nil and next(node.inputs)==nil)
manual={}
assert(Writer.apply(host,obj,plan))
assert(comp.undo==1 and node.inputs.FillGreen[34]==1)
local start=comp.undo
assert(not pcall(function()Writer.apply(host,obj,plan)end))
assert(comp.undo==start,'repeated preset must not overwrite existing Fusion curve')
print('PASS Motion native conflict preflight: manual Spline keys preserved and repeat apply blocked')
