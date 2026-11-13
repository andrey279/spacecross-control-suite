local C = require("spacecross.core.codec")
local H = require("tests.support")
local util = require("spacecross.core.util")

local function roundtrip_binary_nested()
  local original = {name = "Привет\0\255", list = {1, false, {x = -1.25}}, empty = {}}
  local decoded = assert(C.decode(C.encode(original)))
  return H.equal(C.encode(decoded), C.encode(original))
end
local function rejects_untrusted_code_and_truncation()
  for _, value in ipairs({"return os.execute('bad')", "s20:short", "a999999999:", "a2:s1:xts1:xf", "n3:nan", "tt"}) do
    local result, err = C.decode(value)
    if result ~= nil or not err then return {status = false, error_code = "accepted " .. value} end
  end
  return H.success()
end
local function rejects_cycles_and_limits()
  local cycle = {}; cycle.self = cycle
  local ok = pcall(C.encode, cycle)
  assert(not ok)
  local value, err = C.decode("s4:data", 3)
  return H.truth(value == nil and err ~= nil)
end
local function safe_relative_paths()
  for _, path in ipairs({"../foo", "/etc/passwd", "a/../b", "a//b", "a/./b", "a\\b", "a\n.lua", "x/"}) do
    if util.relativePath(path) then return {status = false, error_code = "accepted path " .. path} end
  end
  return H.truth(util.relativePath("spacecross/core/util.lua"))
end
local all_tests = {
  {test_name = "roundtrip_binary_nested", test = roundtrip_binary_nested},
  {test_name = "rejects_untrusted_code_and_truncation", test = rejects_untrusted_code_and_truncation},
  {test_name = "rejects_cycles_and_limits", test = rejects_cycles_and_limits},
  {test_name = "safe_relative_paths", test = safe_relative_paths},
}
return all_tests
