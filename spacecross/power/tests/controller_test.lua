local P = require("tests.stubs.platform")
local HAL = require("spacecross.hal.hal")
local Buffer = require("spacecross.hal.drivers.enderio_capacitor")
local Redstone = require("spacecross.hal.drivers.redstone")
local Reactor = require("spacecross.hal.drivers.enan_reactor")
local Power = require("spacecross.power.controller")
local H = require("tests.support")
local function fixture()
  local p = P.new(); p.calls = {}
  p.components.buffer = {type = "energy_handler", stored = 5, capacity = 100}
  p.components.buffer.getEnergyStored = function() return p.components.buffer.stored end
  p.components.buffer.getMaxEnergyStored = function() return p.components.buffer.capacity end
  p.components.reactor = {type = "warpdriveEnanReactorCore", enabled = false,
    energy = function() return 100, 1000, 10 end, instability = function() return 5, 6, 7, 8 end,
    release = function() return true end}
  p.components.reactor.enable = function(value)
    p.components.reactor.enabled = value; p.calls[#p.calls + 1] = value and "reactor_on" or "reactor_off"; return value
  end
  p.components.reactor.state = function() return "OK", p.components.reactor.enabled end
  p.components.switch = {type = "redstone", setOutput = function(side, value)
    if p.brokenSide == side then error("load controller broken") end
    p.calls[#p.calls + 1] = side .. ":" .. value; return 0
  end}
  p.hal = HAL.new(p, {Buffer, Redstone, Reactor}); p.hal:start()
  p.entities, p.scanComplete = {}, true
  p.watcher = {snapshot = function() return {complete = p.scanComplete, entities = p.entities} end}
  local config = {owners = {"Owner"}, buffers = {"buffer"}, sources = {"reactor"}, loads = {}}
  for group = 1, 3 do
    config.loads[group] = {id = "group" .. group, group = group, address = "switch",
      on = {method = "setOutput", args = {group, 15}}, off = {method = "setOutput", args = {group, 0}}}
  end
  return p, Power.new(p, config)
end
local function deficit_sheds_in_priority_order_and_recovers_in_reverse()
  local p, power = fixture()
  local state = assert(power:tick())
  assert(state.generating and state.telemetry.fraction == 0.05)
  assert(table.concat(p.calls, ",") == "reactor_on,1:0,2:0,3:0")
  p.calls = {}; p.components.buffer.stored = 90
  state = assert(power:tick())
  assert(not state.generating and not next(state.disabled))
  return H.equal(table.concat(p.calls, ","), "reactor_off,3:15,2:15,1:15")
end
local function owner_protects_main_production_and_return_restores_it()
  local p, power = fixture()
  p.entities = {{name = "owner"}}
  local state = assert(power:tick())
  assert(state.disabled.group1 and not state.disabled.group2 and state.disabled.group3)
  p.entities = {}; power:tick(); assert(power.disabled.group2)
  p.entities = {{name = "Owner"}}; p.calls = {}; power:tick()
  return H.truth(not power.disabled.group2 and table.concat(p.calls, ","):find("2:15", 1, true))
end
local function unknown_presence_preserves_main_production()
  local p, power = fixture(); p.scanComplete = false
  local state = assert(power:tick())
  return H.truth(state.disabled.group1 and not state.disabled.group2 and state.disabled.group3)
end
local function bad_buffer_never_stops_sources_or_restores_loads()
  local p, power = fixture(); power:tick()
  p.components.buffer.stored = 0 / 0; p.calls = {}
  local state = assert(power:tick())
  assert(not state.telemetry.complete and #state.faults == 1 and #p.calls == 0)
  return H.truth(state.generating and state.disabled.group1)
end
local function load_failure_does_not_stop_remaining_channels()
  local p, power = fixture(); p.brokenSide = 1
  local state = assert(power:tick())
  assert(not state.disabled.group1 and state.disabled.group2 and state.disabled.group3)
  assert(#state.faults == 1)
  p.brokenSide = nil; power:tick()
  return H.truth(power.disabled.group1)
end
local function hysteresis_does_not_toggle_in_middle_band()
  local p, power = fixture(); power:tick()
  p.components.buffer.stored = 50; p.time = 2; power:tick()
  assert(power.generating and power.disabled.group1)
  p.components.buffer.stored = 90; p.time = 4; power:tick()
  p.components.buffer.stored = 60; p.time = 6
  local state = assert(power:tick())
  assert(state.telemetry.deficit == 15)
  return H.truth(not state.generating and not next(state.disabled))
end
local function returning_owner_restores_production_despite_buffer_fault()
  local p, power = fixture(); power:tick(); assert(power.disabled.group2)
  p.entities, p.components.buffer.stored = {{name = "Owner"}}, 0 / 0
  local state = assert(power:tick())
  return H.truth(not state.telemetry.complete and state.telemetry.ownerPresent and not state.disabled.group2)
end
local all_tests = {
  {test_name = "deficit_sheds_in_priority_order_and_recovers_in_reverse", test = deficit_sheds_in_priority_order_and_recovers_in_reverse},
  {test_name = "owner_protects_main_production_and_return_restores_it", test = owner_protects_main_production_and_return_restores_it},
  {test_name = "unknown_presence_preserves_main_production", test = unknown_presence_preserves_main_production},
  {test_name = "bad_buffer_never_stops_sources_or_restores_loads", test = bad_buffer_never_stops_sources_or_restores_loads},
  {test_name = "load_failure_does_not_stop_remaining_channels", test = load_failure_does_not_stop_remaining_channels},
  {test_name = "hysteresis_does_not_toggle_in_middle_band", test = hysteresis_does_not_toggle_in_middle_band},
  {test_name = "returning_owner_restores_production_despite_buffer_fault", test = returning_owner_restores_production_despite_buffer_fault},
}
return all_tests
