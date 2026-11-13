local H = require("tests.support")
local P = require("tests.stubs.platform")
local function requests_check_status_limit_and_close()
  local originals, p = {}, P.new()
  local names = {"component", "computer", "event", "filesystem", "internet"}
  for _, name in ipairs(names) do originals[name] = package.loaded[name] end
  local status, chunks, closed = 200, {"abc", "def"}, 0
  package.loaded.component, package.loaded.event = p.component, p.event
  package.loaded.filesystem = {exists = p.fs.exists, rename = p.fs.rename, remove = p.fs.remove,
    makeDirectory = p.fs.mkdir, isDirectory = p.fs.isDirectory, list = function() return function() end end}
  package.loaded.computer = {uptime = p.clock, address = function() return "node" end, shutdown = function() end}
  package.loaded.internet = {request = function()
    local pos = 0
    return setmetatable({}, {__call = function()
      pos = pos + 1; return chunks[pos]
    end, __index = {response = function() return status end, close = function() closed = closed + 1 end}})
  end}
  local ok, err = pcall(function()
    local deps = require("spacecross.runtime.openos").new({})
    assert(deps.request("https://example.test", 6) == "abcdef")
    assert(not deps.request("https://example.test", 3))
    status = 404
    assert(not deps.request("https://example.test", 6))
    assert(closed == 3)
  end)
  for _, name in ipairs(names) do package.loaded[name] = originals[name] end
  if not ok then error(err) end
  return H.success()
end
local all_tests = {
  {test_name = "requests_check_status_limit_and_close", test = requests_check_status_limit_and_close},
}
return all_tests
