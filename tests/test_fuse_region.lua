-- Test actual authored Fuse callbacks, with a mocked Fusion image/GUI facade.
local root=assert(arg[1])
local env={CT_Tool=1};setmetatable(env,{__index=_G})
local registered=false
function env.FuRegisterClass(id,kind,attrs)
  assert(id=='CartoRigRegion' and kind==1)
  assert(attrs.REGS_Category=='CartoRig\\Map Objects')
  registered=true
end
assert(loadfile(root..'/fuses/CartoRigRegion.fuse','t',env))()
assert(registered)
local pages,inputs,outs,clones={},{},{},{}
local mock={}
function mock:AddControlPage(name)pages[#pages+1]=name end
function mock:AddInput(name,id,attrs)
  local input={id=id,value=attrs.INP_Default,attrs=attrs}
  function input:GetValue(req)
    if id=='Input' then return self.image end
    return {Value=self.value}
  end
  inputs[id]=input
  return input
end
function mock:CloneInput(source,id,attrs)
  assert(source and source.id and id)
  clones[#clones+1]={id=id,source=source.id}
  return source
end
function mock:AddOutput()
  local output={}
  function output:Set(_,image)outs[#outs+1]=(image==nil and 'NIL' or image)end
  return output
end
env.self=mock
env.Create()
assert(pages[1]=='Control' and pages[2]=='Motion')
assert(#clones==2 and clones[1].source=='ObjectOpacity' and clones[2].source=='HighlightStrength')
assert(inputs.FillRed.attrs.INPID_InputControl=='ColorControl')
for i,n in ipairs({'FillRed','FillGreen','FillBlue'}) do assert(inputs[n].attrs.IC_ControlID==i-1) end
assert(inputs.ObjectOpacity.attrs.INP_Default==1)
assert(inputs.FillAlpha.attrs.INP_Default==1)
local img={}
function img:Copy()
  local out={}
  function out:Gain(r,g,b,a) self.gain={r,g,b,a} end
  return out
end
inputs.Input.image=img
inputs.FillRed.value=1;inputs.FillGreen.value=0.2;inputs.FillBlue.value=0
inputs.ObjectOpacity.value=0.5;inputs.HighlightStrength.value=0
env.Process({})
local result=outs[#outs];assert(result~=img)
assert(math.abs(result.gain[1]-0.5)<1e-9)
assert(math.abs(result.gain[2]-0.1)<1e-9)
assert(result.gain[3]==0 and result.gain[4]==0.5)
inputs.HighlightStrength.value=0.6
inputs.HighlightRed.value=0;inputs.HighlightGreen.value=1;inputs.HighlightBlue.value=0.5
env.Process({})
local blend=outs[#outs].gain
assert(math.abs(blend[1]-0.2)<1e-9)
assert(math.abs(blend[2]-0.34)<1e-9)
assert(math.abs(blend[3]-0.15)<1e-9)
assert(blend[4]==0.5)
-- Fill alpha is independent of Object Opacity and highlight strength.
inputs.FillAlpha.value=0.4;inputs.ObjectOpacity.value=0.5
inputs.HighlightStrength.value=0;env.Process({})
assert(math.abs(outs[#outs].gain[4]-0.2)<1e-9)
assert(math.abs(outs[#outs].gain[1]-0.2)<1e-9)
assert(inputs.ObjectOpacity.value==0.5 and inputs.FillAlpha.value==0.4)
inputs.ObjectOpacity.value=0;env.Process({})
assert(outs[#outs].gain[4]==0 and outs[#outs].gain[1]==0)
inputs.Input.image=nil;env.Process({});assert(outs[#outs]=='NIL')
print('PASS CartoRigRegion Fuse: Color picker + Control/Motion clone channels + RGBA premult + highlight')
