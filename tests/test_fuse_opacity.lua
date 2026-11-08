local root=assert(arg[1]);local env={CT_Tool=1}
setmetatable(env,{__index=_G})
env.FuRegisterClass=function(id,kind,attrs)
  assert(id=='CartoRigOpacity' and kind==1 and attrs.REGS_Category=='CartoRig\\Experimental')
end
assert(loadfile(root..'/fuses/CartoRigOpacity.fuse','t',env))()
local pages,controls,outs={},{},{}
local mock={}
function mock:AddControlPage(page)pages[#pages+1]=page end
function mock:AddInput(label,id,attrs)
  local obj={id=id,attrs=attrs,value=attrs.INP_Default}
  function obj:GetValue(_)if id=='Input' then return self.image end;return {Value=self.value} end
  controls[id]=obj
  return obj
end
function mock:AddOutput(label,id,attrs)
  local obj={};function obj:Set(_,image)outs[#outs+1]=(image==nil and "NIL" or image) end
  return obj
end
env.self=mock
env.Create()
assert(pages[1]=='Control' and pages[2]=='Motion')
assert(controls.ObjectOpacity and controls.FadeFactor and controls.Input)
local img={}
function img:Copy()
  local o={}
  function o:Gain(r,g,b,a)self.gain={r,g,b,a}end
  return o
end
controls.Input.image=img
-- At full opacity the input image is forwarded unchanged.
env.Process({})
assert(outs[#outs]==img)
controls.ObjectOpacity.value=0.5;controls.FadeFactor.value=0.4
env.Process({})
assert(outs[#outs]~=img)
for _,v in ipairs(outs[#outs].gain)do assert(math.abs(v-0.2)<1e-8)end
controls.FadeFactor.value=0
env.Process({})
assert(outs[#outs].gain[4]==0)
controls.Input.image=nil
env.Process({})
assert(outs[#outs]=="NIL")
print('PASS experimental Fuse: native Control/Motion pages, opacity*fade, premultiplied RGBA, nil input')
