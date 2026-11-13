local args = rawget(_G, "arg") or {...}
local script = args[0] or "tools/check_manifest.lua"
local root = script:match("^(.*)/tools/[^/]+$") or "."
package.path = root .. "/?.lua;" .. package.path
local file = assert(io.open(assert(args[1], "manifest path required"), "rb"))
local raw = file:read("*a"); file:close()
local value, err = require("spacecross.update.manifest").decode(raw, args[2])
assert(value, err)
local count = 0; for _ in pairs(value.files) do count = count + 1 end
print("Manifest OK: " .. value.revision .. " " .. count .. " files")
