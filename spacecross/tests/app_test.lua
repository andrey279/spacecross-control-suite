local App = require("spacecross.app")
local P = require("tests.stubs.platform")
local H = require("tests.support")
local function headless_services_are_independent_of_ui()
  local p = P.new()
  local app = App.new(p, {owners = {"owner"}, logging = {root = "/logs"}})
  assert(app:start() and app.bus.running and app.hal.registry.running)
  p:advance(2)
  assert(app.logger.lastError == "ENCRYPTION_UNAVAILABLE")
  assert(app.model:request("hardware", "snapshot", "owner").count == 0)
  assert(not app.model:request("hardware", "snapshot", "intruder"))
  assert(app:stop())
  assert(not next(p.timers))
  return H.equal(#p.listeners.spacecross_message, 0)
end
local function startup_failure_unwinds_services_and_restart_is_clean()
  local p = P.new()
  local config = {owners = {"owner"}, logging = {root = "/logs"},
    panels = {{id = "main", gpu = "missing", screen = "missing", player = "owner"}}}
  local app = App.new(p, config)
  assert(not pcall(app.start, app))
  assert(not app.running and not next(p.timers) and #p.listeners.spacecross_message == 0)
  config.panels = {}
  assert(app:start()); app:stop(); assert(app:start()); app:stop()
  return H.equal(#p.listeners.component_added, 0)
end
local function autonomous_defense_runs_without_ui_and_enforces_model_roles()
  local p, fired = P.new(), 0
  p.components.detector = {type = "os_entdetector", scanPlayers = function() return {{name = "Guest"}} end}
  p.components.redstone = {type = "redstone", setOutput = function(side, value)
    assert(side == 1 and value == 15); fired = fired + 1; return 0
  end}
  local app = App.new(p, {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
    drivers = {"spacecross.hal.drivers.opensecurity_detector", "spacecross.hal.drivers.redstone"},
    watcher = {enabled = true, range = 32},
    defense = {enabled = true, channels = {{address = "redstone", side = 1}}}})
  app:start(); p:advance(1)
  assert(fired == 0 and not app.model:request("defense", "arm", "Admin"))
  assert(app.model:request("defense", "arm", "Owner")); p:advance(1)
  assert(fired == 1 and app.defense.fired)
  assert(app.model:request("entities", "snapshot", "Admin").count == 1)
  app:stop()
  return H.truth(not next(p.timers))
end
local function shield_model_is_owner_only_and_uses_configured_redstone_hal()
  local p, active, composed, mode = P.new(), false, true, "Ignored"
  p.components["shield-1"] = {
    type = "shield_projector",
    isShieldActive = function() return active end,
    isShieldComposed = function() return composed end,
    getRedstoneMode = function() return mode end,
    setRedstoneMode = function(value) mode = value end,
    composeShield = function() composed = true; return true end,
    decomposeShield = function() composed = false; return true end,
  }
  p.components.redstone = {type = "redstone", setOutput = function(side, value)
    assert(side == 3); active = value == 15; return 0
  end}
  local app = App.new(p, {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
    drivers = {"spacecross.hal.drivers.redstone", {module = "spacecross.hal.drivers.rftools_shield",
      options = {devices = {["shield-1"] = {controlAddress = "redstone", side = 3}}}}},
    shields = {enabled = true}})
  app:start()
  assert(app.model:request("shields", "snapshot", "Admin").shields[1].status.active == false)
  assert(app.model:request("shields", "turn_on", "Admin", {address = "shield-1"}) == nil)
  assert(app.model:request("shields", "turn_on", "Owner", {address = "shield-1"}))
  assert(mode == "On" and active)
  assert(app.model:request("shields", "turn_off", "Owner", {address = "shield-1"}) and not active)
  app:stop()
  return H.truth(not next(p.timers))
end
local function turret_model_is_owner_only_and_reads_configured_driver_status()
  local p, active, mode = P.new(), false, 2
  p.components["turret-1"] = {
    type = "omt_turret",
    getActive = function() return active end,
    getMode = function() return mode end,
    setMode = function(value) mode = value; return true end,
    toggle = function() active = not active; return true end,
  }
  local app = App.new(p, {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
    drivers = {{module = "spacecross.hal.drivers.omt_turret", options = {
      types = {"omt_turret"}, activeMethod = "getActive", getModeMethod = "getMode", modes = {1, 2},
    }}}, turrets = {enabled = true}})
  app:start()
  local snapshot = app.model:request("turrets", "snapshot", "Admin")
  assert(snapshot.turrets[1].status.active == false and snapshot.turrets[1].status.mode == 2)
  assert(app.model:request("turrets", "turn_on", "Admin", {address = "turret-1"}) == nil)
  assert(app.model:request("turrets", "turn_on", "Owner", {address = "turret-1"}) and active)
  assert(app.model:request("turrets", "setMode", "Owner", {address = "turret-1", mode = 1}) and mode == 1)
  local denied = app.model:request("turrets", "setMode", "Admin", {address = "turret-1", mode = 2})
  assert(denied == nil and mode == 1)
  app:stop()
  return H.truth(not next(p.timers))
end
local function satellite_model_limits_control_to_owners()
  local p = P.new()
  local app = App.new(p, {owners = {"Owner"}, admins = {"Admin"}, logging = {root = "/logs"},
    satellite = {enabled = true, mode = "jump", heartbeatInterval = 10}})
  app:start()
  assert(app.model:request("satellite", "snapshot", "Admin").mode == "jump")
  assert(app.model:request("satellite", "setMode", "Admin", {mode = "charges"}) == nil)
  assert(app.model:request("satellite", "setMode", "Owner", {mode = "charges"}))
  assert(app.model:request("satellite", "snapshot", "Owner").mode == "charges")
  app:stop()
  return H.truth(not next(p.timers))
end
local all_tests = {
  {test_name = "headless_services_are_independent_of_ui", test = headless_services_are_independent_of_ui},
  {test_name = "startup_failure_unwinds_services_and_restart_is_clean", test = startup_failure_unwinds_services_and_restart_is_clean},
  {test_name = "autonomous_defense_runs_without_ui_and_enforces_model_roles", test = autonomous_defense_runs_without_ui_and_enforces_model_roles},
  {test_name = "shield_model_is_owner_only_and_uses_configured_redstone_hal", test = shield_model_is_owner_only_and_uses_configured_redstone_hal},
  {test_name = "turret_model_is_owner_only_and_reads_configured_driver_status", test = turret_model_is_owner_only_and_reads_configured_driver_status},
  {test_name = "satellite_model_limits_control_to_owners", test = satellite_model_limits_control_to_owners},
}
return all_tests
