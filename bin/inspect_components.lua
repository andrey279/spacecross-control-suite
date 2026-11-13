-- Usage: inspect_components.lua [literal type/address filter ...]
-- This command only queries component inventory and documentation; it calls no hardware method.
local component = require("component")
local Inspector = require("spacecross.hal.component_inspector")
local filters = {...}
local ok, report = pcall(Inspector.collect, component, filters)
if not ok then
  io.stderr:write("Component inspection failed: " .. tostring(report) .. "\n")
  return
end
io.write(Inspector.render(report))
