-- Usage: inspect_components.lua [literal type/address filter ...]
-- This command only queries component inventory and documentation; it calls no hardware method.
local arguments = rawget(_G, "arg") or {...}
local script = arguments[0] or "bin/inspect_components.lua"
local root = (script:match("^(.*)/bin/[^/]+$") or ".")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local component = require("component")
local Inspector = require("spacecross.hal.component_inspector")
local filters = {}
for index = 1, #arguments do filters[#filters + 1] = arguments[index] end
local ok, report = pcall(Inspector.collect, component, filters)
if not ok then
  io.stderr:write("Component inspection failed: " .. tostring(report) .. "\n")
  return
end
io.write(Inspector.render(report))
