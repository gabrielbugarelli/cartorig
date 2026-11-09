-- Indexed Natural Earth base-layer geometry access. No runtime Python/network.
-- Original coordinates are immutable; viewport filters never invent geometry.
local M={}
local allowed={
  land={Polygon=true,MultiPolygon=true},
  lakes={Polygon=true,MultiPolygon=true},
  coastline={LineString=true,MultiLineString=true},
  boundaries={LineString=true,MultiLineString=true},
}
local function fail(message)error('CartoRig base layers: '..message,2)end
local function finite(n)return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
local function valid_bbox(b)
  return type(b)=='table' and #b==4
    and finite(b[1]) and finite(b[2]) and finite(b[3]) and finite(b[4])
    and b[1]>=-180 and b[1]<=180 and b[3]>=-180 and b[3]<=180
    and b[2]>=-90 and b[2]<=90 and b[4]>=-90 and b[4]<=90
    and b[2]<=b[4]
end
function M.load_index(root,dataset,json)
  if type(root)~='string' or root=='' or not allowed[dataset] then fail('invalid base layer location') end
  if type(json)~='table' or type(json.decode)~='function' then fail('JSON codec unavailable') end
  local file=io.open(root..'/index_'..dataset..'.json','rb')
  if not file then fail('layer index missing: '..dataset) end
  local content=file:read(16000001);file:close()
  if not content or #content>16000000 then fail('layer index exceeds safe size') end
  local doc=json.decode(content,16000000)
  if type(doc)~='table' or doc.schema~='cartorig.offline.layers/1'
    or doc.dataset~=dataset or type(doc.version)~='string'
    or doc.featureFile~='features_'..dataset..'.jsonl' or type(doc.features)~='table' then
    fail('layer index schema mismatch')
  end
  local ids={};local lastEnd=0
  for i,row in ipairs(doc.features)do
    if type(row.id)~='string' or ids[row.id] or not allowed[dataset][row.geometryType]
      or not valid_bbox(row.bbox) or type(row.crossesAntimeridian)~='boolean'
      or not finite(row.featureOffset) or row.featureOffset%1~=0 or row.featureOffset<lastEnd
      or not finite(row.featureBytes) or row.featureBytes%1~=0
      or row.featureBytes<1 or row.featureBytes>30000000 then
      fail('invalid indexed layer entry '..i)
    end
    ids[row.id]=true
    lastEnd=row.featureOffset+row.featureBytes
  end
  return doc
end
local function x_intersects(row,viewport)
  if row.crossesAntimeridian then return true end
  local box=row.bbox
  if viewport[1]<=viewport[3] then return box[1]<=viewport[3] and box[3]>=viewport[1] end
  -- Viewer wraps past 180 degrees: [left..180] union [-180..right].
  return box[3]>=viewport[1] or box[1]<=viewport[3]
end
function M.query(index,viewport,limit)
  if type(index)~='table' or type(index.features)~='table'
    or not valid_bbox(viewport) then fail('invalid layer viewport query') end
  limit=limit or 1000
  if type(limit)~='number' or limit%1~=0 or limit<1 or limit>10000 then fail('invalid query limit') end
  local matches={}
  for _,row in ipairs(index.features) do
    if row.bbox[2]<=viewport[4] and row.bbox[4]>=viewport[2] and x_intersects(row,viewport) then
      if #matches>=limit then fail('viewport exceeds layer feature budget') end
      matches[#matches+1]=row
    end
  end
  return matches
end
function M.load_feature(root,index,row,json)
  if type(root)~='string' or root=='' or type(index)~='table'
    or not allowed[index.dataset] or type(row)~='table'
    or type(row.featureOffset)~='number' or type(row.featureBytes)~='number'
    or row.featureOffset<0 or row.featureOffset%1~=0 or row.featureBytes<1
    or row.featureBytes>30000000 or row.featureBytes%1~=0 then
    fail('invalid feature reference')
  end
  if index.featureFile~='features_'..index.dataset..'.jsonl' then fail('untrusted layer filename') end
  local file=io.open(root..'/'..index.featureFile,'rb')
  if not file then fail('indexed layer source unavailable') end
  local positioned=file:seek('set',row.featureOffset)
  if not positioned then file:close();fail('invalid layer offset') end
  local text=file:read(row.featureBytes);file:close()
  if not text or #text~=row.featureBytes then fail('truncated indexed layer feature') end
  local feature=json.decode(text,30000000)
  if type(feature)~='table' or feature.type~='Feature'
    or type(feature.geometry)~='table' or feature.geometry.type~=row.geometryType
    or not allowed[index.dataset][feature.geometry.type] then fail('indexed layer geometry mismatch') end
  return feature
end
return M
