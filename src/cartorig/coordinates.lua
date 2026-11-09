-- Explicit user-authored WGS84 coordinates; no city or capital inference.
local C={}
local function number(value,label,min,max)
  if type(value)~='string' then error(label..' must be entered as decimal degrees',2) end
  local trimmed=value:match('^%s*(.-)%s*$')
  if not trimmed:match('^[+-]?%d+%.?%d*$') and not trimmed:match('^[+-]?%.%d+$') then
    error(label..' must be decimal degrees using a dot, with no other characters',2)
  end
  local n=tonumber(trimmed)
  if not n or n~=n or n<min or n>max then error(label..' outside '..min..'..'..max,2) end
  return n
end
function C.parse(lon,lat)
  return {lon=number(lon,'Longitude',-180,180),lat=number(lat,'Latitude',-90,90)}
end
return C
