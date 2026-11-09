local root=assert(arg[1]);local env={CT_Tool=1,CARTORIG_GEO_TEST_ROOT=root..'/tests/fixtures/layer_index',CARTORIG_GEO_TEST_SOURCE=root..'/src/cartorig'}
setmetatable(env,{__index=_G});env._G=env
-- Exercise the Fuse render call; the seek-based layer catalogue has its own
-- independent tests. Supply deterministic indexed feature records here.
function env.dofile(path)
 if path:match('/layer_catalog%.lua$') then
  return {
   load_index=function()return {features={{id='a'},{id='b'}}}end,
   query=function(index)return index.features end,
   load_feature=function(_,_,row)
    local x=row.id=='a' and -62 or 30
    return {geometry={type='Polygon',coordinates={{{x,-10},{x+2,-10},{x+2,10},{x,10},{x,-10}}}}}
   end,
  }
 end
 return dofile(path)
end
local registered=false
function env.FuRegisterClass(id,typ,attrs)
  assert(id=='CartoRigGeoMatte' and typ==1 and attrs.REGS_Category=='CartoRig\\Internal')
  registered=true
end
assert(loadfile(root..'/fuses/CartoRigGeoMatte.fuse','t',env))()
local inputs,outputs={},{}
local mock={}
function mock:AddControlPage(name)assert(name=='Control')end
function mock:AddInput(_,id,attrs)
  local x={value=attrs.INP_Default}
  function x:GetValue()if id=='Input' then return self.image end;return {Value=self.value}end
  inputs[id]=x;return x
end
function mock:AddOutput()
  local x={};function x:Set(_,img)outputs[#outputs+1]=img or 'NIL' end;return x
end
env.self=mock;env.Create()
assert(registered and inputs.Layer and inputs.StrokePx and inputs.Input)
local draws,shapes=0,0
function env.Shape()
  local shape={points={},closed=0}
  function shape:MoveTo(x,y)self.points[#self.points+1]={x,y} end
  function shape:LineTo(x,y)self.points[#self.points+1]={x,y}end
  function shape:Close()self.closed=self.closed+1 end
  function shape:OutlineOfShape(...)self.outlined=true;return self end
  shapes=shapes+1
  return shape
end
function env.ImageChannel(img,quality)
  local ic={}
  function ic:SetStyleFill(_)end
  function ic:ShapeFill(shape)assert(#shape.points>=3 and shape.closed==2)end
  function ic:PutToImage(mode,style)
    assert(mode=='CM_Merge' and style.Color.A==1)
    draws=draws+1
  end
  return ic
end
function env.Pixel(color)return color end
function env.FillStyle()return {} end
function env.ChannelStyle()return {} end
inputs.Input.image={Width=100,Height=50,XScale=1,YScale=1,Copy=function(self)
 local img={Width=self.Width,Height=self.Height,XScale=1,YScale=1}
 function img:Clear()self.cleared=true end
 return img
end}
env.Process({})
assert(draws==1 and shapes==1)
assert(outputs[#outputs].cleared)
inputs.Layer.value=100;env.Process({});assert(outputs[#outputs]=='NIL')
inputs.Layer.value=0;inputs.Input.image=nil;env.Process({});assert(outputs[#outputs]=='NIL')
print('PASS GeoMatte Fuse: indexed offline Shape drawing, output matte, invalid layer & missing image fail closed')
