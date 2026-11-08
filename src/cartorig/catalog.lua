-- Offline geographic search from explicit GeoJSON FeatureCollections; input is never executable.
local M={}
local function fail(msg)error('CartoRig catalog: '..msg,2)end
local accents={['á']='a',['à']='a',['â']='a',['ã']='a',['ä']='a',['Á']='a',['À']='a',['Â']='a',['Ã']='a',['Ä']='a',
 ['é']='e',['ê']='e',['è']='e',['ë']='e',['É']='e',['Ê']='e',['È']='e',['Ë']='e',
 ['í']='i',['ì']='i',['î']='i',['ï']='i',['Í']='i',['Ì']='i',['Î']='i',['Ï']='i',
 ['ó']='o',['ô']='o',['ò']='o',['õ']='o',['ö']='o',['Ó']='o',['Ô']='o',['Ò']='o',['Õ']='o',['Ö']='o',
 ['ú']='u',['ù']='u',['û']='u',['ü']='u',['Ú']='u',['Ù']='u',['Û']='u',['Ü']='u',['ç']='c',['Ç']='c',['ñ']='n',['Ñ']='n'}
function M.normalize(s)
  if type(s)~='string' then return '' end
  for a,b in pairs(accents) do s=s:gsub(a,b) end
  return s:lower():gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
end
local function field(p,keys)
  for _,k in ipairs(keys) do
    local v=p[k]
    if v~=nil and v~='' and v~='-99' and v~=-99 then return tostring(v) end
  end
end
local function point(xy)
  return type(xy)=='table' and type(xy[1])=='number' and type(xy[2])=='number' and {lon=xy[1],lat=xy[2]} or nil
end
local function list_aliases(p,name)
  local aliases={};local seen={}
  for _,v in ipairs({name,p.NAME_ALT,p.NAMEASCII,p.NAME_EN,p.NAME_LONG,p.ADMIN,p.SOVEREIGNT,p.name_alt}) do
    if type(v)=='string' and v~='' and not seen[v] then aliases[#aliases+1]=v;seen[v]=true end
  end
  if name=='Brazil' and not seen.Brasil then aliases[#aliases+1]='Brasil' end
  return aliases
end
function M.from_geojson(document,kind,source)
  if type(document)~='table' or document.type~='FeatureCollection' or type(document.features)~='table' then fail('not a GeoJSON FeatureCollection') end
  if kind~='Country' and kind~='State' and kind~='City' then fail('invalid catalog type') end
  source=source or {}
  local result={};local seen={}
  for i,f in ipairs(document.features) do
    local p=f.properties or {}; local geo=f.geometry or {}
    if type(p)~='table' or type(geo)~='table' then fail('bad feature '..i) end
    local geom=geo.type
    if (kind=='City' and geom=='Point') or (kind~='City' and (geom=='Polygon' or geom=='MultiPolygon')) then
      local name=field(p,{'NAME','NAME_EN','NAME_LONG','ADMIN','name','name_en'})
      if name then
        local iso=field(p,{'ADM0_A3','SOV_A3','ISO_A3','adm0_a3','POSTAL','ISO_3166_2','postal','NE_ID'}) or tostring(i)
        local id=(source.dataset or 'unknown')..':'..iso..':'..tostring(i)
        if seen[id] then fail('duplicate feature id '..id) end
        seen[id]=true
        local country=field(p,{'ADMIN','SOVEREIGNT','admin','ADM0NAME','SOV0NAME'})
        local region=field(p,{'name_adm1','ADM1NAME','REGION','region'})
        local parent=(kind=='State' and country or kind=='City' and ((region and region..', ' or '')..(country or ''))) or 'World'
        local pt=geom=='Point' and point(geo.coordinates) or nil
        local lon,lat=tonumber(p.LABEL_X or p.label_x or p.LONGITUDE or p.longitude),tonumber(p.LABEL_Y or p.label_y or p.LATITUDE or p.latitude)
        if not pt and lon and lat then pt={lon=lon,lat=lat} end
        result[#result+1]={id=id,name=name,kind=kind,parent=parent,aliases=list_aliases(p,name),code=iso,
          geometryType=geom,geometry=geo,point=pt,source={dataset=source.dataset,version=source.version,scale=source.scale,license=source.license or 'Natural Earth public domain'}}
      end
    end
  end
  table.sort(result,function(a,b)return a.name<b.name end)
  return result
end
function M.search(entries,query,kind,limit)
  assert(type(entries)=='table','catalog entries required')
  local q=M.normalize(query)
  if #q==0 then return {} end
  limit=limit or 50
  if limit<1 or limit>500 then fail('invalid result limit') end
  local found={}
  for _,entry in ipairs(entries) do
    if not kind or kind=='All' or kind==entry.kind then
      local score=nil
      for _,text in ipairs(entry.aliases or {entry.name}) do
        local n=M.normalize(text)
        if n==q then score=math.min(score or 99,0)
        elseif n:sub(1,#q)==q then score=math.min(score or 99,1)
        elseif n:find(q,1,true) then score=math.min(score or 99,2) end
      end
      if score~=nil then found[#found+1]={entry=entry,score=score} end
    end
  end
  table.sort(found,function(a,b)
    if a.score~=b.score then return a.score<b.score end
    if a.entry.name~=b.entry.name then return a.entry.name<b.entry.name end
    return a.entry.id<b.entry.id
  end)
  local out={};for i=1,math.min(limit,#found) do out[i]=found[i].entry end
  return out
end
function M.load_bundle(path,json)
  assert(type(path)=='string' and path~='' and type(json)=='table','invalid bundle path')
  local file,err=io.open(path,'rb')
  if not file then fail('cannot open offline bundle: '..tostring(err)) end
  local raw=file:read('*a');file:close()
  return json.decode(raw)
end
function M.load_index(data_root,json)
  if type(data_root)~='string' or type(json)~='table' then fail('invalid offline catalog directory') end
  local f,err=io.open(data_root..'/catalog_index.json','rb')
  if not f then fail('cannot open offline index: '..tostring(err)) end
  local raw=f:read('*a');f:close()
  local parsed=json.decode(raw,30000000)
  if parsed.schema~='cartorig.offline.catalog/1' or type(parsed.locations)~='table' then fail('invalid catalog index schema') end
  local seen={}
  for _,v in ipairs(parsed.locations) do
    if type(v.id)~='string' or seen[v.id] then fail('invalid/duplicate catalog feature ID') end
    if type(v.featureFile)~='string' or not v.featureFile:match('^features_%w+%.jsonl$') then fail('invalid feature file name') end
    if type(v.featureOffset)~='number' or v.featureOffset<0 or type(v.featureBytes)~='number' or v.featureBytes<=0 or v.featureBytes>30000000 then fail('invalid feature offset') end
    seen[v.id]=true
  end
  return parsed.locations
end
function M.load_feature(data_root,entry,json)
  if not entry or not entry.featureFile then return entry end
  if not entry.featureFile:match('^features_%w+%.jsonl$') then fail('untrusted feature path') end
  local f,err=io.open(data_root..'/'..entry.featureFile,'rb')
  if not f then fail('geographic feature source unavailable: '..tostring(err)) end
  local ok=f:seek('set',entry.featureOffset)
  if not ok then f:close();fail('geographic feature offset unavailable') end
  local content=f:read(entry.featureBytes);f:close()
  if not content or #content~=entry.featureBytes then fail('geographic feature truncated') end
  local feature=json.decode(content,30000000)
  if feature.type~='Feature' or type(feature.geometry)~='table' then fail('invalid feature at index offset') end
  local copy={};for k,v in pairs(entry) do copy[k]=v end
  copy.geometry=feature.geometry
  return copy
end
return M
