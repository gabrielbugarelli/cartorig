-- Every authorial object has a real Fusion effect with independent Color,
-- ObjectOpacity and Control/Motion pages; sample its actual Process callback.
local root=assert(arg[1]);local defaults={Marker='Fill',Route='Stroke',Label='Text'}
for kind,prefix in pairs(defaults) do
  local env={CT_Tool=1};setmetatable(env,{__index=_G})
  local registered=false
  env.FuRegisterClass=function(id,typeid,attrs)
    assert(id=='CartoRig'..kind and typeid==1)
    assert(attrs.REGS_Category=='CartoRig\\Map Objects')
    registered=true
  end
  assert(loadfile(root..'/fuses/CartoRig'..kind..'.fuse','t',env))()
  assert(registered)
  local pages,inputs,clones,output={},{},{},{}
  local mock={}
  function mock:AddControlPage(p)pages[#pages+1]=p end
  function mock:AddInput(label,id,attrs)
    local input={value=attrs.INP_Default,id=id,attrs=attrs}
    function input:GetValue()
      if id=='Input' then return self.image end
      return {Value=self.value}
    end
    inputs[id]=input;return input
  end
  function mock:CloneInput(src,name)
    assert(src and src.id);clones[#clones+1]={source=src.id,name=name};return src
  end
  function mock:AddOutput()
    return {Set=function(_,_,img)output[#output+1]=img or 'NIL' end}
  end
  env.self=mock;env.Create()
  assert(pages[1]=='Control' and pages[2]=='Motion' and #clones==1)
  assert(clones[1].source=='ObjectOpacity')
  local input=inputs.Input
  local original={}
  function original:Copy()
    return {Gain=function(self,r,g,b,a)self.pixel={r,g,b,a} end}
  end
  input.image=original
  inputs[prefix..'Red'].value=0.8
  inputs[prefix..'Green'].value=0.6
  inputs[prefix..'Blue'].value=0.4
  inputs.ObjectOpacity.value=0.5
  if kind~='Label' then inputs[prefix..'Alpha'].value=0.4 end
  env.Process({})
  local pixel=output[#output].pixel
  local alpha=kind=='Label' and 0.5 or 0.2
  assert(math.abs(pixel[1]-0.8*alpha)<1e-10)
  assert(math.abs(pixel[2]-0.6*alpha)<1e-10)
  assert(math.abs(pixel[3]-0.4*alpha)<1e-10)
  assert(math.abs(pixel[4]-alpha)<1e-10)
  -- Zero alpha emits zero premultiplied RGB even when color remains bright.
  inputs.ObjectOpacity.value=0
  env.Process({})
  for _,v in ipairs(output[#output].pixel) do assert(v==0)end
  input.image=nil
  env.Process({});assert(output[#output]=='NIL')
end
print('PASS Marker/Route/Label Fuse: separate Control/Motion, animated opacity, independent premultiplied RGBA')
