local P = require("tests.stubs.platform")
local Ship = require("spacecross.autopilot.tests.stubs.ship")
local HAL = require("spacecross.hal.hal")
local Driver = require("spacecross.hal.drivers.warpdrive_ship")
local Daemon = require("spacecross.autopilot.core_daemon")
local Autopilot = require("spacecross.autopilot.autopilot_core")
local H = require("tests.support")
local sequence = 0
local function fixture(options)
  local p = P.new(); p.fs.mkdir("/tmp")
  p.components.a = Ship(p, "a", options)
  p.components.b = Ship(p, "b")
  p.hal = HAL.new(p, {Driver}); p.hal:start()
  p.coreDaemon = Daemon.new(p); p.coreDaemon:start()
  sequence = sequence + 1
  local autopilot = Autopilot.new(p, {controller = "a", lockPath = "/tmp/autopilot-" .. sequence .. ".lock", jumpTimeout = 5})
  assert(autopilot:start())
  return p, autopilot
end
local function route_respects_distance_and_world_orientation()
  for _, direction in ipairs({{1, 0}, {0, 1}, {-1, 0}, {0, -1}}) do
    local p, autopilot = fixture({ox = direction[1], oz = direction[2]})
    assert(autopilot:setRoute({{x = 25, y = 66, z = -7}, {x = 26, y = 64, z = -10}}))
    p:advance(20)
    local ship = p.components.a
    assert(autopilot.state == "done" and ship.x == 26 and ship.y == 64 and ship.z == -10)
    assert(ship.jumps >= 4 and ship.mode == "OFFLINE" and p.components.b.mode == "OFFLINE")
    assert(autopilot:stop()); p.coreDaemon:stop()
  end
  return H.success()
end
local function stopped_navigation_leaves_cooldown_daemon_alive()
  local p, autopilot = fixture()
  assert(autopilot:navigate({x = 5, y = 64, z = 0}))
  p:advance(1); assert(autopilot.state == "waiting")
  assert(autopilot:stop() and p.coreDaemon.running)
  assert(p.coreDaemon.cooling.a and p.components.a.mode == "MANUAL")
  p:advance(3)
  assert(not p.coreDaemon.cooling.a and p.components.a.mode == "OFFLINE")
  p.coreDaemon:stop()
  return H.success()
end
local function unrelated_cooldown_cannot_disable_selected_core()
  local p, autopilot = fixture()
  autopilot:navigate({x = 5, y = 64, z = 0}); p:advance(1)
  p.event.push("shipCoreCooldownDone", "b"); p.event.push("shipCoreCooldownDone", "unknown"); p:pump()
  assert(p.coreDaemon.cooling.a and p.components.a.mode == "MANUAL")
  local selected, err = p.coreDaemon:setActive("b")
  assert(not selected and err == "EBUSY_COOLDOWN")
  autopilot:stop(); p:advance(3); p.coreDaemon:stop()
  return H.success()
end
local function stalled_or_removed_core_reports_error_and_releases_on_stop()
  for _, mode in ipairs({"stalled", "removed", "energy"}) do
    local p, autopilot = fixture({stall = mode == "stalled", energy = mode == "energy" and 10 or 10000})
    autopilot:navigate({x = 5, y = 64, z = 0}); p:advance(1)
    if mode == "removed" then p.components.a = nil; p.event.push("component_removed", "a"); p:pump() end
    p:advance(7)
    assert(autopilot.state == "error", mode)
    assert(autopilot:stop())
    p.coreDaemon:stop()
  end
  return H.success()
end
local function second_program_gets_ebusy_and_plugin_can_navigate()
  local p, autopilot = fixture()
  local locked
  for path in pairs(p.files) do if path:match("autopilot") then locked = path end end
  local other = Autopilot.new(p, {lockPath = locked})
  local ok, err = other:start(); assert(not ok and err == "EBUSY")
  autopilot:registerController("survey", function(api, args) return api:navigate(args.target) end)
  assert(autopilot:control("survey", {target = {x = 3, y = 64, z = 0}}))
  p:advance(6); assert(autopilot.state == "done")
  assert(autopilot:stop()); assert(other:start()); assert(other:stop()); p.coreDaemon:stop()
  return H.success()
end
local function invalid_route_never_starts_hardware()
  local p, autopilot = fixture()
  assert(not autopilot:navigate({x = 0 / 0, y = 64, z = 0}))
  assert(not autopilot:navigate({x = 1.5, y = 64, z = 0}))
  assert(not autopilot:setRoute({}))
  assert(p.components.a.jumps == 0 and autopilot.state == "idle")
  assert(autopilot:stop()); p.coreDaemon:stop()
  return H.success()
end
local function daemon_recovers_untracked_cooldown_and_retries_failed_offline()
  local p, autopilot = fixture()
  local original, broken = p.components.b.command, true
  p.components.b.command = function(mode)
    if mode == "OFFLINE" and broken then error("broken controller") end
    return original(mode)
  end
  p.event.push("shipCoreCooldownDone", "b"); p:pump()
  assert(p.coreDaemon.failures.b)
  broken = false; p:advance(1)
  assert(p.components.b.mode == "OFFLINE" and not p.coreDaemon.failures.b)
  assert(autopilot:stop()); p.coreDaemon:stop()
  return H.success()
end
local function failed_lock_release_stops_timer_and_can_be_retried()
  local p, autopilot = fixture()
  p.fail = function(operation) return operation == "remove" end
  local ok, err = autopilot:stop()
  assert(not ok and err and not autopilot.running and autopilot.timer == nil)
  assert(p.coreDaemon.running)
  p.fail = nil
  assert(autopilot:stop()); assert(autopilot:start()); assert(autopilot:stop())
  p.coreDaemon:stop()
  return H.success()
end
local all_tests = {
  {test_name = "route_respects_distance_and_world_orientation", test = route_respects_distance_and_world_orientation},
  {test_name = "stopped_navigation_leaves_cooldown_daemon_alive", test = stopped_navigation_leaves_cooldown_daemon_alive},
  {test_name = "unrelated_cooldown_cannot_disable_selected_core", test = unrelated_cooldown_cannot_disable_selected_core},
  {test_name = "stalled_or_removed_core_reports_error_and_releases_on_stop", test = stalled_or_removed_core_reports_error_and_releases_on_stop},
  {test_name = "second_program_gets_ebusy_and_plugin_can_navigate", test = second_program_gets_ebusy_and_plugin_can_navigate},
  {test_name = "invalid_route_never_starts_hardware", test = invalid_route_never_starts_hardware},
  {test_name = "daemon_recovers_untracked_cooldown_and_retries_failed_offline", test = daemon_recovers_untracked_cooldown_and_retries_failed_offline},
  {test_name = "failed_lock_release_stops_timer_and_can_be_retried", test = failed_lock_release_stops_timer_and_can_be_retried},
}
return all_tests
