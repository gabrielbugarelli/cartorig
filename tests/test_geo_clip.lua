local root=assert(arg[1]);local G=dofile(root..'/src/cartorig/geo_clip.lua')
local function assert_segment_safe(ring)
  for i,p in ipairs(ring) do
    assert(p[1]>=-180 and p[1]<=180 and p[2]>=-90 and p[2]<=90)
    local nextp=ring[i%#ring+1]
    assert(math.abs(p[1]-nextp[1])<=180+1e-7,'long seam segment')
  end
end
local basic={{{-60,-20},{-40,-20},{-40,0},{-60,0},{-60,-20}}}
local out=G.split_polygon(basic)
assert(#out==1 and #out[1]==1 and #out[1][1]==4)
local seam={
 {{170,-10},{-170,-10},{-170,10},{170,10},{170,-10}},
 {{175,-4},{-175,-4},{-175,4},{175,4},{175,-4}}
}
local pieces=G.split_polygon(seam)
assert(#pieces==2,'seam crossing must create two world pieces')
local east,west=false,false
for _,polygon in ipairs(pieces) do
 assert(#polygon==2,'clipped hole must accompany outer ring')
 for _,ring in ipairs(polygon)do assert_segment_safe(ring)end
 local x=polygon[1][1][1]
 if x>0 then east=true else west=true end
end
assert(east and west)
local combined=G.split_polygons({seam,basic})
assert(#combined==3)
local other=G.split_polygon({{{179,-2},{-179,-2},{-179,2},{179,2}}})
assert(#other==2)
assert(not pcall(function()G.split_polygon({{{0,0},{0,0},{0,0}}})end))
assert(not pcall(function()G.split_polygon({{{181,0},{0,0},{0,5}}})end))
assert(not pcall(function()G.split_polygon({{{0,0},{0/0,0},{0,5}}})end))
assert(not pcall(function()G.split_polygon({{{0,0},{0,100},{5,0}}})end))
print('PASS geographic polygon seam clipping: islands, preserved holes, no world-spanning edges, invalid coordinates refused')
