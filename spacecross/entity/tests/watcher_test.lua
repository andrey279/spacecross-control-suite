local Watcher = require("spacecross.entity.watcher")
local P = require("tests.stubs.platform")
local HAL = require("spacecross.hal.hal")
local Detector = require("spacecross.hal.drivers.opensecurity_detector")
local Radar = require("spacecross.hal.drivers.computronics_radar")
local H = require("tests.support")
local function merges_sources_expires_and_marks_failures_incomplete()
  local p, bad = P.new(), false
  p.components.a = {type = "os_entdetector", scanPlayers = function() return {{name = "Owner"}} end}
  p.components.b = {type = "os_entdetector", scanPlayers = function()
    if bad then return false, "power failure" end
    return {{name = "owner"}, {name = "Guest"}}
  end}
  p.hal = HAL.new(p, {Detector}); p.hal:start()
  local watcher = Watcher.new(p, {range = 32, ttl = 5})
  local first = watcher:poll()
  assert(first.complete and first.count == 2)
  assert(#first.entities[2].sources == 2)
  first.entities[1].name = "mutated"
  assert(watcher:snapshot().entities[1].name == "Guest")
  bad = true; assert(not watcher:poll().complete)
  p.time = 6
  local expired = watcher:snapshot()
  return H.truth(not expired.complete and expired.count == 0)
end
local function hot_removed_detector_does_not_leave_ghost_players()
  local p = P.new()
  p.components.a = {type = "os_entdetector", scanPlayers = function() return {{name = "Guest"}} end}
  p.hal = HAL.new(p, {Detector}); p.hal:start()
  local watcher = Watcher.new(p, {range = 32}); watcher:start()
  assert(watcher:snapshot().count == 1)
  p.components.a = nil; p.event.push("component_removed", "a"); p:pump(); p:advance(2)
  local result = watcher:snapshot(); watcher:stop()
  return H.truth(result.count == 0 and not result.complete and not watcher.running)
end
local function merges_opensecurity_and_configured_computronics_sources()
  local p = P.new()
  p.components.os = {type = "os_entdetector", scanPlayers = function() return {{name = "Owner"}} end}
  p.components.radar = {type = "radar_test", getPlayers = function() return {{player = "Guest"}} end}
  local alternate = Radar.configure({types = {"radar_test"}, nameField = "player"})
  p.hal = HAL.new(p, {Detector, alternate}); p.hal:start()
  local watcher = Watcher.new(p, {range = 32})
  local result = watcher:poll()
  return H.truth(result.complete and result.count == 2 and result.expectedSources == 2)
end
local all_tests = {
  {test_name = "merges_sources_expires_and_marks_failures_incomplete", test = merges_sources_expires_and_marks_failures_incomplete},
  {test_name = "hot_removed_detector_does_not_leave_ghost_players", test = hot_removed_detector_does_not_leave_ghost_players},
  {test_name = "merges_opensecurity_and_configured_computronics_sources", test = merges_opensecurity_and_configured_computronics_sources},
}
return all_tests
