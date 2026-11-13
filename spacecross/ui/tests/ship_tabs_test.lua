local UI = require("spacecross.ui.framework")
local GPU = require("spacecross.ui.tests.stubs.gpu")
local AutopilotTab = require("spacecross.ui.autopilot_tab")
local PowerTab = require("spacecross.ui.power_tab")
local App = require("spacecross.app")
local System = require("spacecross.tests.stubs.ship_system")
local H = require("tests.support")
local function tab_input_changes_target_model_and_returns_fresh_snapshot()
  local p, config = System(); local app = App.new(p, config); app:start()
  local ui = UI.new({authorize = function(player) return player == "Owner" end,
    request = function(endpoint, action, player, args) return app.model:request(endpoint.model, action, player, args) end})
  local gpu = GPU(); gpu.width, gpu.height = 40, 14
  ui:addPanel("main", gpu, "screen", "Owner")
  local tab = AutopilotTab({host = "localhost", model = "autopilot"})
  ui:addTab("main", tab)
  ui:addTab("main", PowerTab({{host = "localhost", model = "power"}}))
  ui:select("main", "autopilot")
  assert(not ui:input("main", {"touch", "screen", 6, 5, 0, "Intruder"}))
  assert(ui:input("main", {"touch", "screen", 6, 5, 0, "Owner"}))
  assert(app.model:request("autopilot", "snapshot", "Owner").draft.x == 10)
  assert(ui:input("main", {"key_down", "keyboard", 0, 205, "Owner"}))
  assert(ui.panels.main.active == "power")
  assert(app.model:request("autopilot", "setTarget", "Owner", {target = {x = 25, y = 64, z = 0}}))
  ui:input("main", {"scroll", "screen", 2, 2, 1, "Owner"})
  assert(ui.panels.main.active == "autopilot")
  local found = false
  for _, call in ipairs(gpu.calls) do if call[1] == "set" and call[4]:find("x: 25", 1, true) then found = true end end
  assert(tab.state == nil and tab.snapshot == nil)
  app:stop()
  return H.truth(found)
end
local all_tests = {
  {test_name = "tab_input_changes_target_model_and_returns_fresh_snapshot", test = tab_input_changes_target_model_and_returns_fresh_snapshot},
}
return all_tests
