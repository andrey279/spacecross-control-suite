local UI = require("spacecross.ui.framework")
local GPU = require("spacecross.ui.tests.stubs.gpu")
local Tab = require("spacecross.ui.shield_tab")
local H = require("tests.support")

local function shield_panel_renders_fresh_state_and_routes_owner_button()
  local gpu, calls = GPU(), {}
  gpu.width, gpu.height = 40, 12
  local ui = UI.new({authorize = function(player) return player == "Owner" end,
    request = function(endpoint, action, player, args)
      if action == "snapshot" then
        assert(endpoint.model == "shields")
        return {shields = {{address = "shield-1", status = {active = endpoint.host == "host-a", composed = true, redstoneMode = "On"}}}, failures = {}}
      end
      calls[#calls + 1] = {action, player, args.address, endpoint.host}
      return true
    end})
  ui:addPanel("main", gpu, "screen", "Owner")
  local tab = Tab.new({{host = "host-a", model = "shields"}, {host = "host-b", model = "shields"}})
  ui:addTab("main", tab)
  assert(ui:select("main", "shields"))
  local shown = false
  for _, call in ipairs(gpu.calls) do
    if call[1] == "set" and call[4]:find("active, formed", 1, true) then shown = true end
  end
  assert(shown)
  assert(ui:input("main", {"touch", "screen", 2, 7, 0, "Owner"}))
  assert(calls[1][1] == "turn_on" and calls[1][2] == "Owner" and calls[1][3] == "shield-1" and calls[1][4] == "host-b")
  assert(ui:input("main", {"touch", "screen", 2, 7, 0, "Admin"}) == nil)
  return H.success()
end

local all_tests = {
  {test_name = "shield_panel_renders_fresh_state_and_routes_owner_button", test = shield_panel_renders_fresh_state_and_routes_owner_button},
}
return all_tests
