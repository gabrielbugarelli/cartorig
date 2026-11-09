-- Immutable source fingerprint for a CartoRig scene. Never silently replace its geometry bundle.
local M={}
local function fail(s)error('CartoRig manifest: '..s,2)end
local function hex(v)return type(v)=='string' and #v==64 and v:match('^[a-fA-F0-9]+$')~=nil end
function M.identify(manifest)
  if type(manifest)~='table' or type(manifest.bundle)~='string' or not manifest.bundle:match('^[%w%-_]+$')
      or type(manifest.datasets)~='table' or #manifest.datasets<1 then fail('invalid source manifest') end
  local digest=manifest.catalog_index and manifest.catalog_index.sha256
  if not digest then digest=manifest.datasets[1].sha256 or manifest.datasets[1].output_sha256 end
  if not hex(digest) then fail('source manifest lacks a valid version checksum') end
  return manifest.bundle..':'..digest:lower()
end
function M.load(path,json)
  if type(path)~='string' or type(json)~='table' then fail('manifest path/decoder required') end
  local f,err=io.open(path,'rb');if not f then fail('manifest missing: '..tostring(err)) end
  local raw=f:read('*a');f:close()
  local ok,value=pcall(json.decode,raw)
  if not ok then fail('manifest is not valid JSON') end
  return {id=M.identify(value),raw=value}
end
function M.assert_compatible(scene,installed_id)
  if not scene then fail('no active scene') end
  if scene.manifestId~=installed_id then
    fail('scene requires '..tostring(scene.manifestId)..' but installed data is '..tostring(installed_id)..'; do not substitute borders or points')
  end
  return true
end
return M
