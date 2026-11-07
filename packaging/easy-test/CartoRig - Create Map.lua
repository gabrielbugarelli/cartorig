-- CartoRig Studio: native Resolve Edit authoring command, offline.
local src = assert(debug.getinfo(1, "S").source)
assert(src:sub(1,1)=="@", "Run from Workspace > Scripts > Utility")
local dir = assert(src:sub(2):match("^(.*[\\/])"))
local core = assert(loadfile(dir .. "CartoRigSupport\\core.lua"))()
core.run("Create")
