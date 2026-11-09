local root=assert(arg[1])
local S=dofile(root..'/src/cartorig/scene.lua')
local M=dofile(root..'/src/cartorig/motion.lua')
local W=dofile(root..'/src/cartorig/motion_apply.lua')
local sc=S.new('input-introspection-1');local region=S.add_location(sc,
 {id='BR',name='Brazil',type='Country',geometryType='Polygon'},'Region')
local plan=M.prepare(region,'MO-REG-03',{start=20,frameCount=200,targetColor='#FF0000'},{})
local field={}
function field:GetAttrs()return {INPS_ID='FillRed'}end
function field:GetKeyFrames()return {[10]={0.1}}end
function field:GetConnectedOutput()return nil end
local tool={data={},calls=0}
function tool:GetData(k)return self.data[k]end
function tool:SetData(k,v)self.data[k]=v end
function tool:GetInputList()return {[1]=field}end
function tool:AddModifier()self.calls=self.calls+1;return true end
function tool:SetInput()self.calls=self.calls+1;return true end
local comp={StartUndo=function()error('native preflight must run before undo')end}
local host={comp=comp,tool_for=function()return tool end}
local ok,msg=pcall(function()W.apply(host,region,plan)end)
assert(not ok and tostring(msg):find('CONFLICT',1,true) and tool.calls==0)
function field:GetKeyFrames()return {}end
function field:GetConnectedOutput()return {some='external expression'}end
ok,msg=pcall(function()W.apply(host,region,plan)end)
assert(not ok and tostring(msg):find('CONFLICT',1,true) and tool.calls==0)
function field:GetConnectedOutput()error('host cannot inspect connection')end
ok,msg=pcall(function()W.apply(host,region,plan)end)
assert(not ok and tostring(msg):find('could not inspect existing Fusion connection',1,true))
print('PASS Native Motion indexed input enumeration and external modifier conflict detection')
