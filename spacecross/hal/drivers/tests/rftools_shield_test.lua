local Driver = require("spacecross.hal.drivers.rftools_shield")
local H = require("tests.support")

local function instance(proxy, options, registry)
  local definition = Driver.configure(options)
  local driver = definition.new({registry = registry or {call = function() return nil, "ENOTSUP" end}})
  driver.address = "shield-1"
  assert(driver:init(proxy))
  return driver
end

local function reads_status_and_composes_without_claiming_health()
  local composed, active, mode, formed = false, false, "Ignored", 0
  local driver = instance({
    isShieldActive = function() return active end,
    isShieldComposed = function() return composed end,
    getRedstoneMode = function() return mode end,
    setRedstoneMode = function(value) mode = value end,
    composeShield = function() composed, formed = true, formed + 1; return true end,
    decomposeShield = function() composed = false; return true end,
  })
  assert(driver:isOperational())
  local before = assert(driver:getStatus())
  assert(before.active == false and before.composed == false and before.health == nil)
  assert(driver:turn_on() == nil) -- formation is explicit and separate from activation.
  assert(driver:compose() and driver:compose() and formed == 1)
  local on, onErr = driver:turn_on()
  assert(on == nil and onErr == "ENOTSUP") -- no redstone output was configured.
  assert(driver:getStatus().composed)
  assert(driver:decompose() and driver:decompose())
  assert(driver:getEnergyLevel() == nil)
  return H.success()
end

local function redstone_control_uses_explicit_mode_and_confirms_actions_via_hal()
  local active, composed, mode = false, true, "Ignored"
  local output = {}
  local registry = {call = function(_, address, method, side, value)
    assert(address == "rs-1" and method == "setOutput" and side == 3)
    output[#output + 1] = value
    active = value == 15
    return true
  end}
  local driver = instance({
    isShieldActive = function() return active end,
    isShieldComposed = function() return composed end,
    getRedstoneMode = function() return mode end,
    setRedstoneMode = function(value) mode = value end,
    composeShield = function() return true end,
    decomposeShield = function() return true end,
  }, {devices = { ["shield-1"] = {controlAddress = "rs-1", side = 3} }}, registry)
  assert(driver:turn_on() and mode == "On" and output[1] == 15)
  assert(driver:turn_off() and output[2] == 0)
  return H.success()
end

local function invalid_status_and_unsafe_output_configuration_are_rejected()
  local driver = instance({
    isShieldActive = function() return "yes" end,
    isShieldComposed = function() return false end,
    getRedstoneMode = function() return "Unknown" end,
    setRedstoneMode = function() end,
    composeShield = function() end,
    decomposeShield = function() end,
  })
  assert(driver:getStatus() == nil)
  assert(not pcall(Driver.configure, {devices = {x = {controlAddress = "rs", side = 6}}}))
  return H.success()
end

local all_tests = {
  {test_name = "reads_status_and_composes_without_claiming_health", test = reads_status_and_composes_without_claiming_health},
  {test_name = "redstone_control_uses_explicit_mode_and_confirms_actions_via_hal", test = redstone_control_uses_explicit_mode_and_confirms_actions_via_hal},
  {test_name = "invalid_status_and_unsafe_output_configuration_are_rejected", test = invalid_status_and_unsafe_output_configuration_are_rejected},
}
return all_tests
