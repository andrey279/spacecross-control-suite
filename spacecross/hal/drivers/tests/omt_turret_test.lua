local OMT = require("spacecross.hal.drivers.omt_turret")
local H = require("tests.support")

local function driver_for(proxy, options)
  options = options or {}
  options.types = {"omt_test_base"}
  local instance = OMT.configure(options).new({})
  assert(instance:init(proxy))
  return instance
end

local function safe_idempotent_on_off_with_configured_active_probe()
  local active, mode, calls = false, 0, 0
  local driver = driver_for({
    getActive = function() return active end,
    getCurrentEnergyStorage = function() return 6 end,
    getMaxEnergyStorage = function() return 10 end,
    getMode = function() return mode end,
    setMode = function(value) mode = value end,
    toggle = function() calls = calls + 1; active = not active end,
  }, {activeMethod = "getActive", currentEnergyMethod = "getCurrentEnergyStorage",
    maxEnergyMethod = "getMaxEnergyStorage", getModeMethod = "getMode", modes = {0, 3}})
  assert(driver:isOperational())
  assert(driver:turn_on() and calls == 1)
  assert(driver:turn_on() and calls == 1)
  assert(driver:turn_off() and calls == 2)
  assert(driver:setMode(3) and driver:getMode() == 3)
  assert(driver:getEnergyLevel().stored == 6)
  assert(driver:setMode(3) and driver:getMode() == 3)
  assert(driver:getStatus().active == false and driver:getStatus().mode == 3 and driver:getStatus().modes[2] == 3)
  local invalidMode, modeErr = driver:setMode(4)
  assert(invalidMode == nil and modeErr == "EINVAL_MODE")
  assert(not pcall(driver.setMode, driver, 1.5))
  return H.success()
end

local function missing_toggle_fails_closed_and_bad_telemetry_is_rejected()
  local driver = driver_for({
    toggle = function() end,
    getActive = function() return true end,
    getCurrentEnergyStorage = function() return 12 end,
    getMaxEnergyStorage = function() return 10 end,
    getMode = function() return 1 end,
    setMode = function() end,
  }, {activeMethod = "getActive", currentEnergyMethod = "getCurrentEnergyStorage",
    maxEnergyMethod = "getMaxEnergyStorage", getModeMethod = "getMode", modes = {0, 1}})
  driver.proxy.toggle = nil
  local off, err = driver:turn_off()
  assert(off == nil and err == "ENOTSUP")
  local energy, energyErr = driver:getEnergyLevel()
  assert(energy == nil and energyErr == "INVALID_ENERGY_TELEMETRY")
  return H.success()
end

local all_tests = {
  {test_name = "safe_idempotent_on_off_with_configured_active_probe", test = safe_idempotent_on_off_with_configured_active_probe},
  {test_name = "missing_toggle_fails_closed_and_bad_telemetry_is_rejected", test = missing_toggle_fails_closed_and_bad_telemetry_is_rejected},
}
return all_tests
