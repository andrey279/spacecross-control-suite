local App = require("spacecross.app")
local System = require("spacecross.tests.stubs.ship_system")
local H = require("tests.support")
local function target_models_own_navigation_state_and_power_outlives_navigation()
  local p, config = System()
  local app = App.new(p, config); app:start()
  local args = {target = {x = 5, y = 64, z = 0}}
  assert(not app.model:request("autopilot", "setTarget", "Intruder", args))
  assert(app.model:request("autopilot", "setTarget", "Owner", args))
  args.target.x = 999
  local view = app.model:request("autopilot", "snapshot", "Owner")
  assert(view.draft.x == 5); view.draft.x = 777
  assert(app.model:request("autopilot", "snapshot", "Owner").draft.x == 5)
  assert(app.model:request("autopilot", "go", "Owner", {}))
  p:advance(1)
  assert(app.autopilot.state == "waiting")
  assert(app.model:request("autopilot", "stopAutopilot", "Owner", {}))
  assert(not app.autopilot.running and app.coreDaemon.running and app.power.running)
  p:advance(4)
  assert(p.components.ship.mode == "OFFLINE")
  assert(app.model:request("power", "snapshot", "Owner").disabled.expensive)
  assert(app.model:request("autopilot", "startAutopilot", "Owner", {}))
  assert(app.model:request("autopilot", "navigate", "Owner", {target = {x = 10, y = 64, z = 0}}))
  p:advance(6); assert(app.autopilot.state == "done")
  app:stop()
  return H.truth(not next(p.timers))
end
local function unavailable_autopilot_does_not_stop_life_support()
  local p, config = System()
  p.files["/tmp/app-autopilot.lock"], p.liveProcesses[99] = "99", true
  local app = App.new(p, config)
  assert(app:start())
  assert(app.running and app.power.running and app.bus.running and app.coreDaemon.running)
  assert(not app.autopilot.running and app.autopilot.error == "EBUSY")
  p:advance(4)
  assert(app.power:snapshot().disabled.expensive)
  app:stop()
  return H.equal(p.files["/tmp/app-autopilot.lock"], "99")
end
local all_tests = {
  {test_name = "target_models_own_navigation_state_and_power_outlives_navigation", test = target_models_own_navigation_state_and_power_outlives_navigation},
  {test_name = "unavailable_autopilot_does_not_stop_life_support", test = unavailable_autopilot_does_not_stop_life_support},
}
return all_tests
