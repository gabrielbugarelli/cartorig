local root=assert(arg[1]);local M=dofile(root..'/src/cartorig/manifest.lua');local J=dofile(root..'/src/cartorig/json.lua')
local m=M.load(root..'/data/manifest.json',J)
assert(m.id:match('^natural%-earth%-110m%-preview:[a-f0-9]+$'))
assert(M.assert_compatible({manifestId=m.id},m.id))
assert(not pcall(function()M.assert_compatible({manifestId='other'},m.id)end))
assert(not pcall(function()M.identify({bundle='ne',datasets={{sha256='fake'}}})end))
local d={bundle='natural-earth-10m',datasets={{output_sha256=string.rep('a',64)}},catalog_index={sha256=string.rep('f',64)}}
assert(M.identify(d)=='natural-earth-10m:'..string.rep('f',64))
print('PASS manifest: immutable source IDs, dataset mismatch prevention, 10m + preview formats')
