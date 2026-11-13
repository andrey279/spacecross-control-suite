local P = require("tests.stubs.platform")
local HAL = require("spacecross.hal.hal")
local Reactor = require("spacecross.hal.tests.stubs.reactor")
local H = require("tests.support")

local function independent_instances_and_hotplug()
  local p = P.new()
  p.components.a = {type = "stub_reactor", energy = 25, on = true}
  p.components.b = {type = "stub_reactor", energy = 75, on = true}
  local hal = HAL.new(p, {Reactor}); hal:start()
  assert(#hal.registry:list() == 2)
  assert(hal.registry.instances.a ~= hal.registry.instances.b)
  assert(hal.power.getEnergyLevels().a.value.stored == 25)
  p.components.a = nil
  p.event.push("component_removed", "a", "stub_reactor"); p:pump()
  assert(not hal.registry.instances.a)
  p.components.c = {type = "stub_reactor", energy = 10, on = true}
  p.event.push("component_added", "c", "stub_reactor"); p:pump()
  assert(hal.registry.instances.c)
  hal:stop()
  return H.equal(#hal.registry:list(), 0)
end
local function one_broken_reactor_does_not_stop_others()
  local p = P.new()
  p.components.a = {type = "stub_reactor", broken = true, on = true}
  p.components.b = {type = "stub_reactor", on = true}
  local hal = HAL.new(p, {Reactor}); hal:start()
  local result = hal.power.turnOffAll()
  assert(not result.a.ok and result.b.ok and not p.components.b.on)
  assert(p.errors[1].fields.address == "a")
  return H.equal(p.errors[1].code, "ERR_COMPONENT_UNREACHABLE")
end
local function invalid_contract_is_quarantined()
  local p = P.new(); p.components.x = {type = "bad"}
  local hal = HAL.new(p, {{id = "bad", types = {"bad"}, new = function() return {} end}})
  hal:start()
  assert(not hal.registry.instances.x and #p.errors == 1)
  return H.equal(p.errors[1].code, "ERR_COMPONENT_UNREACHABLE")
end
local function lifecycle_does_not_duplicate_listeners()
  local p = P.new(); local hal = HAL.new(p, {Reactor})
  hal:start(); hal:start()
  assert(#p.listeners.component_added == 1)
  hal:stop(); hal:start()
  return H.equal(#p.listeners.component_added, 1)
end
local all_tests = {
  {test_name = "independent_instances_and_hotplug", test = independent_instances_and_hotplug},
  {test_name = "one_broken_reactor_does_not_stop_others", test = one_broken_reactor_does_not_stop_others},
  {test_name = "invalid_contract_is_quarantined", test = invalid_contract_is_quarantined},
  {test_name = "lifecycle_does_not_duplicate_listeners", test = lifecycle_does_not_duplicate_listeners},
}
return all_tests
