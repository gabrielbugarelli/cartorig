-- CartoRig greenfield 0.2: searchable geographic catalog, pure Lua.
local C = {}

local accents = {
    ['á']='a',['à']='a',['â']='a',['ã']='a',['ä']='a',['Á']='a',['À']='a',['Â']='a',['Ã']='a',
    ['é']='e',['ê']='e',['è']='e',['É']='e',['Ê']='e',['í']='i',['Í']='i',
    ['ó']='o',['ô']='o',['õ']='o',['ö']='o',['Ó']='o',['Ô']='o',['Õ']='o',
    ['ú']='u',['ü']='u',['Ú']='u',['Ü']='u',['ç']='c',['Ç']='c',['ñ']='n',['Ñ']='n',
}
function C.normalize(s)
    s = tostring(s or '')
    for a,b in pairs(accents) do s=s:gsub(a,b) end
    s = s:lower():gsub('%s+',' '):gsub('^%s+',''):gsub('%s+$','')
    return s
end
function C.project(lon, lat)
    assert(type(lon)=='number' and type(lat)=='number' and lon==lon and lat==lat, 'Invalid geographic coordinate')
    assert(lon>=-180 and lon<=180 and lat>=-90 and lat<=90, 'Geographic coordinate out of range')
    return (lon+180)/360, (lat+90)/180  -- Fusion image space: lower-left is (0, 0)
end
function C.unproject(x,y) return x*360-180,y*180-90 end
-- Geographic polylines encoded as signed 1e5 coordinate deltas.
-- Each ring starts at [0, 0]; coordinate order is [longitude, latitude].
function C.decode_polyline(encoded)
    local index, lon, lat = 1, 0, 0
    local result = {}
    while index <= #encoded do
        local pair = {}
        for part = 1, 2 do
            local shift, value, more = 0, 0, true
            repeat
                local ch = encoded:byte(index)
                if not ch then error('Truncated geographic polyline') end
                index = index + 1
                local digit = ch - 63
                if digit < 0 or digit > 63 then error('Invalid encoded geographic polyline') end
                value = value + (digit % 32) * (2^shift)
                shift = shift + 5
                more = digit >= 32
                if shift > 35 then error('Oversized geographic polyline coordinate') end
            until not more
            local delta = value % 2 == 1 and -(math.floor(value/2)+1) or math.floor(value/2)
            if part == 1 then lon=lon+delta else lat=lat+delta end
        end
        local x,y=lon/100000,lat/100000
        if x < -180.00001 or x > 180.00001 or y < -90.00001 or y > 90.00001 then
            error('Encoded geographic polyline has invalid coordinate')
        end
        result[#result+1]={x,y}
    end
    return result
end
local function decode_feature(feature)
    if type(feature.polylines)=='table' then
        feature.polygons={}
        for _,poly in ipairs(feature.polylines) do
            local rings={}
            for _,encoded in ipairs(poly) do rings[#rings+1]=C.decode_polyline(encoded) end
            feature.polygons[#feature.polygons+1]=rings
        end
        feature.polylines=nil
    end
end
function C.load(folder)
    assert(type(folder)=='string','Data directory required')
    local features={}
    local datasets={'ne110m_countries.lua','ne50m_br_states.lua','ne110m_cities.lua'}
    local seen={}
    for _,name in ipairs(datasets) do
        local path=folder .. '/' .. name
        local file=io.open(path,'rb')
        if file then
            file:close()
            local chunk,err=loadfile(path)
            assert(chunk,'Data source failed to load: '..tostring(err))
            local rows=chunk()
            for _,feature in ipairs(rows) do
                assert(type(feature.id)=='string' and not seen[feature.id], 'Duplicate geographic id: '..tostring(feature.id))
                assert(type(feature.kind)=='string' and type(feature.name)=='string','Invalid geographic record')
                decode_feature(feature)
                seen[feature.id]=true
                features[#features+1]=feature
            end
        elseif name=='ne110m_countries.lua' then
            error('Required Natural Earth country catalog missing: '..path)
        end
    end
    return features
end
function C.search(features,term,kind,limit)
    term=C.normalize(term)
    local results={}
    for _,f in ipairs(features) do
        if f.kind~='Internal' and (not kind or kind=='All' or kind==f.kind) then
            local candidates={f.name,f.code or ''}
            for _,alias in ipairs(f.aliases or {}) do candidates[#candidates+1]=alias end
            local match = term==''
            local score = 5
            for _,text in ipairs(candidates) do
                local key=C.normalize(text)
                if term~='' and key==term then match=true;score=1;break end
                if term~='' and key:sub(1,#term)==term then match=true;score=math.min(score,2) end
                if term~='' and key:find(term,1,true) then match=true;score=math.min(score,3) end
            end
            if match then results[#results+1]={item=f,score=score} end
        end
    end
    table.sort(results,function(a,b)
        if a.score~=b.score then return a.score<b.score end
        if a.item.kind~=b.item.kind then return a.item.kind<b.item.kind end
        return a.item.name<b.item.name
    end)
    local out={}
    for i=1,math.min(limit or 70,#results) do out[i]=results[i].item end
    return out
end
function C.get_by_id(features,id)
    for _,f in ipairs(features) do if f.id==id then return f end end
end
function C.description(f)
    return string.format('%s — %s%s',f.name,f.kind,f.parent and (' · '..f.parent) or '')
end
return C
