local P = require("tests.stubs.platform")
local HAL = require("spacecross.hal.hal")
local Buffer = require("spacecross.hal.drivers.enderio_capacitor")
local NC = require("spacecross.hal.drivers.nc_reactor")
local Thermal = require("spacecross.hal.drivers.thermal_generator")
local Redstone = require("spacecross.hal.drivers.redstone")
local Enan = require("spacecross.hal.drivers.enan_reactor")
local H = require("tests.support")
local function rf_bindings_keep_buffer_and_generators_independent()
  local p, outputs = P.new(), {}
  for _, address in ipairs({"buffer", "nc1", "nc2"}) do
    p.components[address] = {type = "energy_handler", getEnergyStored = function() return 50 end,
      getMaxEnergyStored = function() return 100 end}
  end
  p.components.thermal = {type = "energy_info", getEnergy = function() return 75 end, getMaxEnergy = function() return 100 end}
  p.components.switch = {type = "redstone", setOutput = function(side, value) outputs[side] = value; return 0 end}
  local hal = HAL.new(p, {Redstone, Buffer.configure({devices = {buffer = {}}}),
    NC.configure({devices = {nc1 = {controlAddress = "switch", side = 1}, nc2 = {controlAddress = "switch", side = 2}}}),
    Thermal.configure({devices = {thermal = {controlAddress = "switch", side = 3}}})})
  hal:start()
  assert(#hal.registry:list("buffer") == 1 and #hal.registry:list("power") == 3)
  assert(hal:call("nc1", "turn_on") and outputs[1] == 15 and outputs[2] == nil)
  local result = hal.power.turnOffAll()
  assert(result.nc1.ok and result.nc2.ok and result.thermal.ok)
  assert(outputs[1] == 0 and outputs[2] == 0 and outputs[3] == 0)
  return H.equal(hal:call("thermal", "getEnergyLevel").stored, 75)
end
local function overlapping_rf_bindings_are_rejected_instead_of_guessed()
  local p = P.new()
  p.components.shared = {type = "energy_handler", getEnergyStored = function() return 1 end, getMaxEnergyStored = function() return 10 end}
  local hal = HAL.new(p, {Buffer, NC.configure({devices = {shared = {controlAddress = "switch", side = 1}}})})
  hal:start()
  assert(not hal.registry.instances.shared)
  return H.equal(p.errors[1].fields.error, "ERR_AMBIGUOUS_DRIVER")
end
local function enan_instances_resume_hold_and_disable_independently()
  local p, polled = P.new(), 0
  for _, address in ipairs({"a", "b"}) do
    local proxy = {type = "warpdriveEnanReactorCore", enabled = false, output = false}
    proxy.enable = function(value) proxy.enabled = value; return value end
    proxy.energy = function() return 100, 1000, 20 end
    proxy.instability = function() polled = polled + 1; return 1, 2, 3, 4 end
    proxy.release = function(value) proxy.output = value; return value end
    proxy.state = function() return "OK", proxy.enabled end
    p.components[address] = proxy
  end
  local hal = HAL.new(p, {Enan}); hal:start()
  assert(hal:call("a", "turn_on"))
  assert(p.components.a.enabled and not p.components.b.enabled and p.components.a.output)
  assert(hal.power.turnOffAll().a.ok and not p.components.a.enabled)
  return H.equal(polled, 1)
end
local all_tests = {
  {test_name = "rf_bindings_keep_buffer_and_generators_independent", test = rf_bindings_keep_buffer_and_generators_independent},
  {test_name = "overlapping_rf_bindings_are_rejected_instead_of_guessed", test = overlapping_rf_bindings_are_rejected_instead_of_guessed},
  {test_name = "enan_instances_resume_hold_and_disable_independently", test = enan_instances_resume_hold_and_disable_independently},
}
return all_tests
