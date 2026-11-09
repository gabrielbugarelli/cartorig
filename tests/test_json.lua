local r=assert(arg[1]);local J=dofile(r..'/src/cartorig/json.lua')
local value={scene='São Paulo',nested={a=1,b=true},points={{lon=179,lat=-10},{lon=-179,lat=10}}}
local encoded=J.encode(value);local parsed=J.decode(encoded)
assert(parsed.scene=='São Paulo' and parsed.nested.b and #parsed.points==2)
assert(J.decode('"\\u00E1"')=='á')
assert(J.decode('"\\uD83D\\uDE80"')=='🚀')
for _,s in ipairs({'{bad}','{"x":1,"x":2}','[1,]','{"x":NaN}','{"x":01}','{"x":"\\uD800"}'}) do
  local ok=pcall(function()J.decode(s) end);assert(not ok,'parser accepted malformed: '..s)
end
assert(not pcall(function()J.encode({value=0/0})end))
assert(J.encode({one='x',two='y'})=='{"one":"x","two":"y"}')
print('PASS JSON: round trip, Unicode surrogate, deterministic encoding, invalid input rejection')
