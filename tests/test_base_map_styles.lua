local root=assert(arg[1]);local Scene=dofile(root..'/src/cartorig/scene.lua')
local s=Scene.new('basemap-properties-0001')
local base=s.objects[1]
assert(base.style.land=='#394C59' and base.style.coastline=='#B5C1CC')
for _,pair in ipairs({{'land','#030405'},{'coastline','#010203'},
 {'countryBorders','#112233'},{'stateBorders','#FFAA00'},
 {'landOpacity',35},{'coastlineOpacity',25},{'countryBordersOpacity',15},{'stateBordersOpacity',5}}) do
 Scene.set_style(s,base.id,pair[1],pair[2])
 assert(base.style[pair[1]]==pair[2])
end
assert(not pcall(function()Scene.set_style(s,base.id,'landOpacity',101)end))
assert(not pcall(function()Scene.set_style(s,base.id,'coastline','not-color')end))
assert(Scene.validate(s))
local Host=dofile(root..'/src/cartorig/fusion_host.lua')
assert(type(Host.prepare_style)=='function')
print('PASS Native Base Map independent style tokens and validation')
