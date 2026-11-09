local root=assert(arg[1]);local env={CT_Tool=1};setmetatable(env,{__index=_G})
function env.FuRegisterClass(id)assert(id=='CartoRigRegion')end
assert(loadfile(root..'/fuses/CartoRigRegion.fuse','t',env))()
local controls={};local output
local tool={}
function tool:AddControlPage()end
function tool:AddInput(label,id,attrs)
  local c={id=id,value=attrs.INP_Default,attrs=attrs}
  function c:GetValue(req)if id=='Input' or id=='StrokeInput' then return self.image end;return {Value=self.value}end
  controls[id]=c;return c
end
function tool:CloneInput(input) return input end
function tool:AddOutput()
  local o={};function o:Set(_,image)output=image end;return o
end
env.self=tool;env.Create()
assert(controls.StrokeRed.attrs.INPID_InputControl=='ColorControl')
assert(controls.StrokeInput.attrs.INP_Required==false)
local function img()
 local v={};function v:Copy()
   local o={};function o:Gain(r,g,b,a)self.gain={r,g,b,a}end
   function o:Merge(stroke,attrs)self.stroke=stroke;self.mode=attrs end
   return o
 end;return v
end
controls.Input.image=img();controls.StrokeInput.image=img()
controls.FillRed.value=1;controls.FillGreen.value=0;controls.FillBlue.value=0
controls.FillAlpha.value=0.4;controls.ObjectOpacity.value=0.5
controls.StrokeRed.value=0;controls.StrokeGreen.value=1;controls.StrokeBlue.value=0
controls.StrokeAlpha.value=0.8;controls.StrokeVisible.value=1
env.Process({})
assert(math.abs(output.gain[4]-0.2)<1e-9,'fill alpha')
assert(output.stroke and math.abs(output.stroke.gain[4]-0.4)<1e-9,'independent stroke alpha')
assert(output.stroke.gain[2]==0.4 and output.stroke.gain[1]==0)
assert(output.mode.MO_ApplyMode=='Merge' and output.mode.MO_ApplyOperator=='Over')
controls.StrokeVisible.value=0;env.Process({})
assert(output.stroke==nil,'disabled stroke must not composite')
controls.StrokeVisible.value=1;controls.StrokeInput.image=nil;env.Process({})
assert(output.stroke==nil,'missing optional stroke matte is safe')
print('PASS Region Stroke Fuse: independent contour RGBA and visibility over Fill')
