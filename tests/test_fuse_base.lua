local root=assert(arg[1]);local env={CT_Tool=1};setmetatable(env,{__index=_G})
local count=0
function env.FuRegisterClass(id,kind,attrs)
  assert(id=='CartoRigBase' and kind==1 and attrs.REGS_Category=='CartoRig\\Map Objects');count=count+1
end
assert(loadfile(root..'/fuses/CartoRigBase.fuse','t',env))()
local pages,inputs,outs,clones={},{},{},{}
local mock={}
function mock:AddControlPage(n)pages[#pages+1]=n end
function mock:AddInput(_,id,attrs)
 local x={value=attrs.INP_Default,attrs=attrs}
 function x:GetValue(req) if id=='Input' or id:sub(-5)=='Input' then return self.image end;return {Value=self.value} end
 inputs[id]=x;return x
end
function mock:CloneInput(input,id)clones[#clones+1]=id;return input end
function mock:AddOutput()
 local x={};function x:Set(_,img)outs[#outs+1]=(img==nil and 'NIL' or img)end;return x
end
env.self=mock;env.Create()
assert(count==1 and pages[1]=='Control' and pages[2]=='Motion')
assert(#clones==5 and clones[5]=='MotionOceanLayerOpacity')
assert(inputs.LandInput and inputs.CoastlineInput and inputs.CountryBordersInput and inputs.StateBordersInput)
local img={}
function img:Copy()
 local o={merges={}}
 function o:Gain(r,g,b,a)self.gain={r,g,b,a}end
 function o:Merge(fg,mode)self.merges[#self.merges+1]={fg=fg,mode=mode}end
 return o
end
inputs.Input.image=img
inputs.OceanRed.value=0.2;inputs.OceanGreen.value=0.3;inputs.OceanBlue.value=0.4
env.Process({})
assert(outs[#outs].gain[4]==1)
assert(outs[#outs].gain[1]==0.2 and outs[#outs].gain[2]==0.3)
inputs.OceanLayerOpacity.value=0.5
inputs.BaseOpacity.value=0.8
env.Process({})
assert(math.abs(outs[#outs].gain[4]-0.4)<1e-8)
inputs.DisplayMode.value=1
env.Process({})
for _,v in ipairs(outs[#outs].gain)do assert(v==0)end
inputs.DisplayMode.value=0
env.Process({})
assert(math.abs(outs[#outs].gain[4]-0.4)<1e-8)
inputs.LandInput.image=img
inputs.LandLayerOpacity.value=0.25
inputs.LandRed.value=0.8
inputs.DisplayMode.value=0
inputs.BaseOpacity.value=0.8
inputs.OceanLayerOpacity.value=1
inputs.CoastlineInput.image=img
inputs.CoastlineLayerOpacity.value=0
inputs.CountryBordersInput.image=img
inputs.CountryBordersLayerOpacity.value=0.5
env.Process({})
local layered=outs[#outs]
assert(#layered.merges==2,'only present nonzero-opacity masks are composited')
assert(math.abs(layered.merges[1].fg.gain[4]-0.2)<1e-8)
assert(math.abs(layered.merges[1].fg.gain[1]-0.16)<1e-8)
assert(math.abs(layered.merges[2].fg.gain[4]-0.4)<1e-8)
assert(layered.merges[1].mode.MO_ApplyOperator=='Over')
inputs.DisplayMode.value=1;env.Process({})
assert(#outs[#outs].merges==0,'overlay must suppress every base matte')
for _,v in ipairs(outs[#outs].gain) do assert(v==0) end
inputs.Input.image=nil;env.Process({});assert(outs[#outs]=='NIL')
print('PASS Base Map Fuse: Control/Motion, Full Map, Transparent Overlay zero RGBA, independent Ocean Layer Fade')
