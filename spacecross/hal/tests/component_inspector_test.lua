local Inspector = require("spacecross.hal.component_inspector")
local H = require("tests.support")

local function inventory_is_sorted_filtered_and_documented_without_invocation()
  local calls = 0
  local entries = {z = "radar", a = "os_entdetector", ignored = "gpu"}
  local component = {
    list = function()
      local keys, i = {"z", "a", "ignored"}, 0
      return function()
        i = i + 1
        local key = keys[i]
        if key then return key, entries[key] end
      end
    end,
    methods = function(address)
      return address == "z" and {getPlayers = false} or {scanPlayers = true}
    end,
    doc = function(_, method)
      calls = calls + 1
      return method .. "([range]) -> table"
    end,
  }
  local report = Inspector.collect(component, {"radar", "os_entdetector"})
  assert(#report == 2 and report[1].address == "a" and report[2].address == "z")
  assert(report[2].methods[1].name == "getPlayers" and not report[2].methods[1].direct)
  assert(report[1].methods[1].direct and report[1].methods[1].documentation == "scanPlayers([range]) -> table")
  assert(calls == 2)
  local rendered = Inspector.render(report)
  assert(rendered:find("COMPONENT type=radar address=z", 1, true))
  assert(rendered:find("METHOD getPlayers dispatch=invoke", 1, true))
  return H.truth(not rendered:find("address=ignored", 1, true))
end

local function component_errors_are_reported_and_empty_filters_match_none()
  local component = {
    list = function()
      local done = false
      return function() if not done then done = true; return "bad", "radar" end end
    end,
    methods = function() error("device removed") end,
  }
  local report = Inspector.collect(component)
  assert(#report == 1 and report[1].error:find("METHOD_ENUMERATION_FAILED", 1, true))
  local absent = Inspector.collect(component, {"not-installed"})
  return H.truth(#absent == 0 and Inspector.render(absent):find("No matching components.", 1, true))
end

return {
  {test_name = "inventory_is_sorted_filtered_and_documented_without_invocation", test = inventory_is_sorted_filtered_and_documented_without_invocation},
  {test_name = "component_errors_are_reported_and_empty_filters_match_none", test = component_errors_are_reported_and_empty_filters_match_none},
}
