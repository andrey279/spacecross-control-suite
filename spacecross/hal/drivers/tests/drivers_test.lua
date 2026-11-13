local Detector = require("spacecross.hal.drivers.opensecurity_detector")
local Radar = require("spacecross.hal.drivers.computronics_radar")
local Redstone = require("spacecross.hal.drivers.redstone")
local H = require("tests.support")
local function normalizes_detector_and_supplies_range_every_time()
  local calls = 0
  local driver = Detector.new()
  driver:init({scanPlayers = function(range, offset)
    calls = calls + 1; assert(range == 64 and offset == false)
    return {{name = "Owner", x = 1, y = 2, z = 3, range = 4}}
  end})
  assert(driver:scanPlayers(32)[1].name == "Owner")
  assert(driver:scanPlayers(32)[1].x == 1)
  return H.equal(calls, 2)
end
local function detector_power_failure_is_not_an_empty_scan()
  local driver = Detector.new()
  driver:init({scanPlayers = function() return false, "Not enough power" end})
  local value, err = driver:scanPlayers(32)
  return H.truth(value == nil and err == "Not enough power")
end
local function computronics_adapter_requires_explicit_type_and_mapping()
  local definition = Radar.configure({types = {"configured_radar"}, nameField = "player", xField = "dx"})
  local calls = 0
  local driver = definition.new()
  driver:init({getPlayers = function(...)
    calls = calls + 1; assert(select("#", ...) == 1 and (...) == 32)
    return {{player = "Guest", dx = 12}}
  end})
  local result = driver:scanPlayers(32)
  return H.truth(result and result[1].name == "Guest" and result[1].x == 12 and result[1].y == nil and calls == 1)
end
local function computronics_adapter_handles_keyed_results_and_failures()
  local definition = Radar.configure({types = {"configured_radar"}, nameFromKey = true, passRange = true})
  local driver = definition.new()
  driver:init({getPlayers = function(range) assert(range == 48); return {Guest = {distance = 7}} end})
  assert(driver:scanPlayers(48)[1].name == "Guest")
  local failed = definition.new()
  failed:init({getPlayers = function() return nil, "scan failed" end})
  local result, err = failed:scanPlayers(48)
  assert(result == nil and err == "scan failed")
  local malformed = definition.new()
  malformed:init({getPlayers = function() return {{noName = true}} end})
  local bad, badErr = malformed:scanPlayers(48)
  return H.truth(bad == nil and badErr == "INVALID_RADAR_NAME")
end
local function computronics_verified_defaults_match_upstream_radar_contract()
  local definition = Radar.configure()
  local driver = definition.new()
  local received
  driver:init({getPlayers = function(distance) received = distance; return {{name = "Owner", x = 1, y = 2, z = 3, distance = 4}} end})
  local result = driver:scanPlayers(32)
  return H.truth(definition.types[1] == "radar" and received == 32 and result[1].name == "Owner")
end
local function redstone_validates_sides_and_handles_zero_return()
  local driver, outputs = Redstone.new(), {}
  driver:init({setOutput = function(side, value) outputs[side] = value; return 0 end})
  assert(driver:setOutput(3, 15))
  assert(outputs[3] == 15 and not pcall(driver.setOutput, driver, 6, 15))
  assert(driver:turn_off())
  for side = 0, 5 do assert(outputs[side] == 0) end
  return H.success()
end
local all_tests = {
  {test_name = "normalizes_detector_and_supplies_range_every_time", test = normalizes_detector_and_supplies_range_every_time},
  {test_name = "detector_power_failure_is_not_an_empty_scan", test = detector_power_failure_is_not_an_empty_scan},
  {test_name = "computronics_adapter_requires_explicit_type_and_mapping", test = computronics_adapter_requires_explicit_type_and_mapping},
  {test_name = "computronics_adapter_handles_keyed_results_and_failures", test = computronics_adapter_handles_keyed_results_and_failures},
  {test_name = "computronics_verified_defaults_match_upstream_radar_contract", test = computronics_verified_defaults_match_upstream_radar_contract},
  {test_name = "redstone_validates_sides_and_handles_zero_return", test = redstone_validates_sides_and_handles_zero_return},
}
return all_tests
