local root=assert(arg[1])
local fuses={}
function FuRegisterClass(name,kind,attrs)fuses[#fuses+1]={name=name,kind=kind,attrs=attrs}end
CT_Tool={}
local file=assert(loadfile(root..'/fuses/CartoRigCamera.fuse'))
file()
assert(#fuses==1 and fuses[1].name=='CartoRigCamera')
local inputs,output={},nil
self={}
function self:AddControlPage(name)self.pages=self.pages or {};self.pages[#self.pages+1]=name end
function self:AddInput(label,name,props)
  local obj={name=name,props=props,keys={}}
  function obj:GetValue(req)
    local v=self.keys[req.Time]
    if v==nil then v=self.props.INP_Default end
    return {Value=v}
  end
  inputs[name]=obj;return obj
end
function self:CloneInput(input,name,props)
  self.clones=self.clones or {};self.clones[name]=input
end
function self:AddOutput(label,name,props)
  local out={name=name}
  function out:Set(req,value)self.result=value end
  output=out;return out
end
Create() -- Fusion Fuse Create uses `self` global
assert(self.pages[1]=='Control' and self.pages[2]=='Motion')
assert(inputs.CenterLongitude and inputs.CenterLatitude and inputs.Zoom and inputs.Bearing)
assert(self.clones.MotionZoom==inputs.Zoom)
local frame={Time=100}
inputs.CenterLongitude.keys[100]=-46.63
inputs.CenterLatitude.keys[100]=-23.55
inputs.Zoom.keys[100]=4
inputs.Bearing.keys[100]=0
local image={Width=1920,Height=1080}
function image:Transform(dst,options)
  assert(dst==nil)
  return {opts=options}
end
inputs.Input.GetValue=function()return image end
Process(frame)
local options=assert(output.result.opts)
assert(math.abs(options.XF_XSize - (2*1080/1920)*4)<1e-10)
assert(options.XF_YSize==4)
assert(options.XF_EdgeMode=='Black')
local x=(-46.63+180)/360
local y=(-23.55+90)/180
assert(math.abs(options.XF_XOffset+(x-.5)*options.XF_XSize-.5)<1e-10)
assert(math.abs(options.XF_YOffset+(y-.5)*options.XF_YSize-.5)<1e-10)
frame.Time=300
inputs.Zoom.keys[300]=2
Process(frame)
assert(output.result.opts.XF_YSize==2)
assert(output.result.opts.XF_XSize==(2*1080/1920)*2)
-- Vertical video: camera world coords still have the same geographic aspect.
image.Width=1080;image.Height=1920
Process(frame)
assert(math.abs(output.result.opts.XF_XSize-(2*1920/1080)*2)<1e-10)
assert(output.result.opts.XF_YSize==2)
print('PASS CartoRigCamera Fuse: Control/Motion, per-frame geographic center and zoom, 16:9 and 9:16')
