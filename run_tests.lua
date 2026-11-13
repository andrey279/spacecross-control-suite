local arguments = rawget(_G, "arg") or {...}
local script = arguments[0] or "run_tests.lua"
local root = script:match("^(.*)/[^/]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local ok, native = pcall(require, "filesystem")
local fs = require("spacecross.core.fs").new(ok and native or nil)
local Runner = require("spacecross.testing.runner")
local components = dofile(root .. "/test_components.lua")
local suites, selectors, matched = {}, {}, {}
local color = true
for _, value in ipairs(arguments) do
  if value == "--no-color" then color = false else selectors[#selectors + 1] = value end
end
local function collect(directory)
  for _, name in ipairs(fs.list(root .. "/" .. directory)) do
    local path = directory .. "/" .. name
    if fs.isDirectory(root .. "/" .. path) then
      if name ~= "stubs" then collect(path) end
    elseif name:match("_test%.lua$") then
      suites[#suites + 1] = {file = path, load = function() return dofile(root .. "/" .. path) end}
    end
  end
end
for _, component in ipairs(components) do collect(component .. "/tests") end
table.sort(suites, function(a, b) return a.file < b.file end)
local function selected(path)
  if #selectors == 0 then return true end
  local result = false
  for _, value in ipairs(selectors) do
    if path:find(value, 1, true) then matched[value], result = true, true end
  end
  return result
end
local rows, stats = Runner.run(suites, selected)
Runner.print(rows, stats, nil, color)
local missing = false
for _, value in ipairs(selectors) do
  if not matched[value] then io.stderr:write("No matching tests: " .. value .. "\n"); missing = true end
end
if stats.total == 0 or stats.failed > 0 or stats.crashed > 0 or missing then os.exit(1) end
